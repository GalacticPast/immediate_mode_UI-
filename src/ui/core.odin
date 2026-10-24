// Adapted architecture: Epic Games Tools' RAD Debugger (MIT). See attribution in docs/ui.md.
package ui

import "core:math"
import "core:mem"
import "core:slice"
import "core:strings"

//- size constructors (RAD: ui_px, ui_text_dim, ui_pct, ui_children_sum)

px :: proc(value: f32, strictness: f32 = 1) -> Size { return {.Pixels, max(0, value), clamp(strictness, 0, 1)} }
text_dim :: proc(padding: f32 = 0, strictness: f32 = 1) -> Size { return {.Text, padding, clamp(strictness, 0, 1)} }
pct :: proc(value: f32, strictness: f32 = 0) -> Size { return {.Parent_Pct, max(0, value), clamp(strictness, 0, 1)} }
children_sum :: proc(strictness: f32 = 1) -> Size { return {.Children_Sum, 0, clamp(strictness, 0, 1)} }
// Takes whatever its siblings leave. Several fills split the space evenly.
fill :: proc() -> Size { return pct(1, 0) }

all_corners :: proc(r: f32) -> [Corner]f32 { return {.Top_Left = r, .Top_Right = r, .Bottom_Right = r, .Bottom_Left = r} }
all_colors :: proc(c: Color) -> [Corner]Color { return {.Top_Left = c, .Top_Right = c, .Bottom_Right = c, .Bottom_Left = c} }

//- lifetime

// State must stay at a stable address between init and deinit.
init :: proc(s: ^State, measure_text: Measure_Text, allocator := context.allocator) {
    s^ = {allocator = allocator, measure_text = measure_text, theme = default_theme()}
    for &arena in s.build_arenas do mem.dynamic_arena_init(&arena, allocator, allocator)
    s.cache = make(map[Key]^Box, allocator)
    s.anims = make(map[Key]Anim, allocator)
    s.windows = make(map[Key]Window_State, allocator)
    s.free_boxes = make([dynamic]^Box, allocator)
    s.events = make([dynamic]Event, allocator)
    s.built_boxes = make([dynamic]^Box, allocator)
    s.hover_chain = make([dynamic]Key, allocator)
    s.drag_data = make([dynamic]u8, allocator)
    s.window_order = make([dynamic]Key, allocator)
    s.window_stack = make([dynamic]^Box, allocator)
    s.scroll_stack = make([dynamic][2]^Box, allocator)
    s.clipboard = make([dynamic]u8, allocator)
    s.commands = make([dynamic]Draw_Command, allocator)
    s.draw_order = make([dynamic]^Box, allocator)
    s.focus_order = make([dynamic]Key, allocator)
    stacks_init(s)
}

deinit :: proc(s: ^State) {
    for _, b in s.cache do free(b, s.allocator)
    for b in s.free_boxes do free(b, s.allocator)
    for &arena in s.build_arenas do mem.dynamic_arena_destroy(&arena)
    delete(s.cache)
    delete(s.anims)
    delete(s.windows)
    delete(s.free_boxes)
    delete(s.events)
    delete(s.built_boxes)
    delete(s.hover_chain)
    delete(s.drag_data)
    delete(s.window_order)
    delete(s.window_stack)
    delete(s.scroll_stack)
    delete(s.clipboard)
    delete(s.commands)
    delete(s.draw_order)
    delete(s.focus_order)
    stacks_destroy(s)
    s^ = {}
}

// Memory that lives until the end of the *next* build: text, transient boxes, draw commands' strings.
build_allocator :: proc(s: ^State) -> mem.Allocator {
    return mem.dynamic_arena_allocator(&s.build_arenas[s.build_index % 2])
}

//- keys

// FNV-1a over the name, seeded with the parent's key. "##" hides the rest from the display text;
// "###" also makes the hash ignore everything before it.
key_from_string :: proc(seed: Key, name: string) -> Key {
    if len(name) == 0 do return 0
    hash_part := name
    if i := strings.index(name, "###"); i >= 0 do hash_part = name[i:]
    hash := u64(seed) ~ u64(14695981039346656037)
    for i in 0 ..< len(hash_part) {
        hash = (hash ~ u64(hash_part[i])) * 1099511628211
    }
    if hash == 0 do hash = 1
    return Key(hash)
}

display_string :: proc(name: string) -> string {
    if i := strings.index(name, "##"); i >= 0 do return name[:i]
    return name
}

// Keys are scoped by the nearest keyed ancestor on the parent stack.
seed_key :: proc(s: ^State) -> Key {
    for i := len(s.stacks.parent.items) - 1; i >= 0; i -= 1 {
        if p := s.stacks.parent.items[i].value; p != nil && p.key != 0 do return p.key
    }
    return 0
}

key_make :: proc(s: ^State, name: string) -> Key { return key_from_string(seed_key(s), name) }

box_from_key :: proc(s: ^State, key: Key) -> ^Box { return key == 0 ? nil : s.cache[key] }

//- geometry helpers

contains :: proc(r: Rect, p: Vec2) -> bool {
    return p.x >= r.pos.x && p.y >= r.pos.y && p.x < r.pos.x + r.size.x && p.y < r.pos.y + r.size.y
}
intersection :: proc(a, b: Rect) -> Rect {
    lo := Vec2{max(a.pos.x, b.pos.x), max(a.pos.y, b.pos.y)}
    hi := Vec2{min(a.pos.x + a.size.x, b.pos.x + b.size.x), min(a.pos.y + a.size.y, b.pos.y + b.size.y)}
    return {lo, {max(0, hi.x - lo.x), max(0, hi.y - lo.y)}}
}
pad_rect :: proc(r: Rect, amount: f32) -> Rect { return {r.pos - amount, r.size + 2 * amount} }

//- building boxes

build_box_from_key :: proc(s: ^State, flags: Box_Flags, key: Key) -> ^Box {
    assert(s.building, "Build boxes between begin_build and end_build")
    st := &s.stacks
    parent := stack_top(&st.parent)
    key := key
    b: ^Box
    if key != 0 {
        b = s.cache[key]
        // A second box with the same key in one build would steal the first one's state.
        // Like RAD, it becomes a transient box instead.
        if b != nil && b.last_touched_build == s.build_index {
            key, b = 0, nil
        } else if b == nil {
            if len(s.free_boxes) > 0 {
                b = pop(&s.free_boxes)
            } else {
                b = new(Box, s.allocator)
            }
            b^ = {first_touched_build = s.build_index}
            s.cache[key] = b
        }
    }
    if b == nil {
        b = new(Box, build_allocator(s))
        b.first_touched_build = s.build_index
    }

    // Keep what must survive between builds, rebuild everything else.
    old := b^
    b^ = {
        key                     = key,
        first_touched_build     = old.first_touched_build,
        last_touched_build      = s.build_index,
        rect                    = old.rect,
        clip                    = old.clip,
        fixed_position_animated = old.fixed_position_animated,
        view_off                = old.view_off,
        view_off_target         = old.view_off_target,
        view_bounds             = old.view_bounds,
        hot_t                   = old.hot_t,
        active_t                = old.active_t,
        disabled_t              = old.disabled_t,
        focus_hot_t             = old.focus_hot_t,
        focus_active_t          = old.focus_active_t,
        text_cursor             = old.text_cursor,
        text_mark               = old.text_mark,
    }

    if parent != nil {
        b.parent = parent
        b.prev = parent.last
        if b.prev != nil do b.prev.next = b
        if parent.first == nil do parent.first = b
        parent.last = b
        parent.child_count += 1
    }

    b.flags = flags | stack_top(&st.flags)
    if parent != nil && .Disabled in parent.flags do b.flags += {.Disabled}
    b.child_layout_axis = stack_top(&st.child_layout_axis)
    b.pref_size = {.X = stack_top(&st.pref_width), .Y = stack_top(&st.pref_height)}
    if x, ok := stack_top(&st.fixed_x).?; ok {
        b.flags += {.Floating_X}
        b.fixed_position.x = x
    }
    if y, ok := stack_top(&st.fixed_y).?; ok {
        b.flags += {.Floating_Y}
        b.fixed_position.y = y
    }
    if w, ok := stack_top(&st.fixed_width).?; ok {
        b.flags += {.Fixed_Width}
        b.fixed_size.x = w
    }
    if h, ok := stack_top(&st.fixed_height).?; ok {
        b.flags += {.Fixed_Height}
        b.fixed_size.y = h
    }
    b.text_align = stack_top(&st.text_align)
    b.text_padding = stack_top(&st.text_padding)
    b.font_size = stack_top(&st.font_size)
    b.corner_radii = stack_top(&st.corner_radii)
    b.palette = stack_top(&st.palette)
    b.transparency = stack_top(&st.transparency)
    b.squish = stack_top(&st.squish)
    b.hover_cursor = stack_top(&st.hover_cursor)

    if .Disabled in b.flags && key != 0 {
        for &a in s.active do if a == key do a = 0
        if s.focus_active == key do s.focus_active = 0
    }

    stacks_auto_pop(s)
    append(&s.built_boxes, b)
    return b
}

build_box :: proc(s: ^State, flags: Box_Flags, name: string) -> ^Box {
    b := build_box_from_key(s, flags, key_make(s, name))
    if text := display_string(name); len(text) > 0 do b.text = strings.clone(text, build_allocator(s))
    return b
}

// Replaces the display text; the string is copied.
set_text :: proc(s: ^State, b: ^Box, text: string) {
    b.text = strings.clone(text, build_allocator(s))
}

//- signals

clicked :: proc(sig: Signal) -> bool { return sig.flags & {.Left_Clicked, .Keyboard_Pressed} != {} }
pressed :: proc(sig: Signal) -> bool { return sig.flags & {.Left_Pressed, .Keyboard_Pressed} != {} }
released :: proc(sig: Signal) -> bool { return .Left_Released in sig.flags }
dragging :: proc(sig: Signal) -> bool { return .Left_Dragging in sig.flags }
double_clicked :: proc(sig: Signal) -> bool { return .Left_Double_Clicked in sig.flags }
right_clicked :: proc(sig: Signal) -> bool { return .Right_Clicked in sig.flags }
right_pressed :: proc(sig: Signal) -> bool { return .Right_Pressed in sig.flags }
middle_clicked :: proc(sig: Signal) -> bool { return .Middle_Clicked in sig.flags }
hovering :: proc(sig: Signal) -> bool { return .Hovering in sig.flags }
mouse_over :: proc(sig: Signal) -> bool { return .Mouse_Over in sig.flags }
committed :: proc(sig: Signal) -> bool { return .Commit in sig.flags }

@(private)
PRESSED_FLAG := [Mouse_Button]Signal_Flag{.Left = .Left_Pressed, .Middle = .Middle_Pressed, .Right = .Right_Pressed}
@(private)
RELEASED_FLAG := [Mouse_Button]Signal_Flag{.Left = .Left_Released, .Middle = .Middle_Released, .Right = .Right_Released}
@(private)
CLICKED_FLAG := [Mouse_Button]Signal_Flag{.Left = .Left_Clicked, .Middle = .Middle_Clicked, .Right = .Right_Clicked}
@(private)
DRAGGING_FLAG := [Mouse_Button]Signal_Flag{.Left = .Left_Dragging, .Middle = .Middle_Dragging, .Right = .Right_Dragging}

DOUBLE_CLICK_TIME :: 0.45
TOOLTIP_DELAY :: 0.5

// Consumes this build's input for the box, using the geometry from the previous build.
// A box only receives a press if it's the deepest clickable box under the pointer, so the
// order of signal calls doesn't decide who wins.
signal_from_box :: proc(s: ^State, b: ^Box) -> Signal {
    sig := Signal{box = b, mods = s.mods}
    if b.key == 0 || .Disabled in b.flags do return sig
    rect := intersection(b.rect, b.clip)
    on_top := slice.contains(s.hover_chain[:], b.key)
    mouse_in := s.mouse_inside && on_top && contains(rect, s.mouse)

    for &e in s.events {
        if e.consumed do continue
        #partial switch e.kind {
            case .Press:
                if .Mouse_Clickable not_in b.flags || e.target != b.key do continue
                e.consumed = true
                sig.flags += {PRESSED_FLAG[e.button]}
                s.active[e.button] = b.key
                s.drag_start_mouse = e.pos
                s.focus_visible = false
                if e.button == .Left {
                    near := linalg_length(e.pos - s.last_press_pos) < 6
                    if b.key == s.last_press_key && near && s.time - s.last_press_time < DOUBLE_CLICK_TIME {
                        s.press_count += 1
                    } else {
                        s.press_count = 1
                    }
                    s.last_press_key, s.last_press_time, s.last_press_pos = b.key, s.time, e.pos
                    if s.press_count == 2 do sig.flags += {.Left_Double_Clicked}
                    if s.press_count >= 3 do sig.flags += {.Left_Triple_Clicked}
                }
                if .Click_To_Focus in b.flags {
                    s.focus_hot, s.focus_active = b.key, b.key
                } else {
                    if .Keyboard_Clickable in b.flags do s.focus_hot = b.key
                    // pressing anything else ends text editing
                    if s.focus_active != b.key do s.focus_active = 0
                }
            case .Release:
                if s.active[e.button] != b.key do continue
                e.consumed = true
                sig.flags += {RELEASED_FLAG[e.button]}
                if contains(rect, e.pos) do sig.flags += {CLICKED_FLAG[e.button]}
                s.active[e.button] = 0
            case .Scroll:
                if .Scroll not_in b.flags || e.target != b.key do continue
                e.consumed = true
                delta := e.scroll
                if .Shift in e.mods do delta = {delta.y, delta.x}
                // a box that only scrolls sideways takes the ordinary wheel too
                if .View_Scroll_Y not_in b.flags && .View_Scroll_X in b.flags && delta.x == 0 do delta = {delta.y, 0}
                sig.scroll += delta
                if .View_Scroll_X in b.flags do b.view_off_target.x += delta.x
                if .View_Scroll_Y in b.flags do b.view_off_target.y += delta.y
                clamp_view(b)
            case .Key_Press:
                if .Keyboard_Clickable not_in b.flags || s.focus_hot != b.key || s.focus_active == b.key do continue
                if (e.key == .Enter || e.key == .Space) && e.mods == {} {
                    e.consumed = true
                    sig.flags += {.Keyboard_Pressed}
                }
        }
    }

    for button in Mouse_Button {
        if s.active[button] == b.key do sig.flags += {DRAGGING_FLAG[button]}
    }
    if mouse_in {
        sig.flags += {.Mouse_Over}
        nothing_active := s.active == {}
        if nothing_active || s.active[.Left] == b.key || s.active[.Right] == b.key || s.active[.Middle] == b.key {
            sig.flags += {.Hovering}
            if .Mouse_Clickable in b.flags && b.key == hover_clickable(s) do s.hot = b.key
        }
    }
    return sig
}

@(private)
linalg_length :: proc(v: Vec2) -> f32 { return math.sqrt(v.x * v.x + v.y * v.y) }

@(private)
hover_clickable :: proc(s: ^State) -> Key {
    for key in s.hover_chain {
        if b := s.cache[key]; b != nil && .Mouse_Clickable in b.flags do return key
    }
    return 0
}

clamp_view :: proc(b: ^Box) {
    for axis in 0 ..< 2 {
        limit := max(0, b.view_bounds[axis] - b.rect.size[axis])
        b.view_off_target[axis] = clamp(b.view_off_target[axis], 0, limit)
    }
}

// Mouse movement since the current drag's press.
drag_delta :: proc(s: ^State) -> Vec2 { return s.mouse - s.drag_start_mouse }
drag_start_mouse :: proc(s: ^State) -> Vec2 { return s.drag_start_mouse }

// Saves a value at the start of a drag (an offset, a size) to read back while dragging.
store_drag_data :: proc(s: ^State, value: $T) {
    value := value
    resize(&s.drag_data, size_of(T))
    mem.copy(raw_data(s.drag_data), &value, size_of(T))
}
get_drag_data :: proc(s: ^State, $T: typeid) -> (value: T) {
    if len(s.drag_data) == size_of(T) do mem.copy(&value, raw_data(s.drag_data), size_of(T))
    return
}

//- animation: the fraction of the remaining distance covered this frame
// fast/slow are RAD's default_animation_rate and slow_rate (ui_core.c); slug is ours.

fast_rate :: proc(s: ^State) -> f32 { return 1 - math.pow(2, -60 * s.dt) }
slow_rate :: proc(s: ^State) -> f32 { return 1 - math.pow(2, -30 * s.dt) }
slug_rate :: proc(s: ^State) -> f32 { return 1 - math.pow(2, -15 * s.dt) }

// Smoothly follows target across builds. A new key starts at initial (or at target).
animate :: proc(s: ^State, key: Key, target: f32, rate: f32 = -1, initial: Maybe(f32) = nil) -> f32 {
    a, found := s.anims[key]
    if !found do a.value = initial.? or_else target
    a.target, a.last_build = target, s.build_index
    a.value += (target - a.value) * (rate < 0 ? fast_rate(s) : rate)
    if abs(target - a.value) < 0.001 {
        a.value = target
    } else {
        s.animating = true
    }
    s.anims[key] = a
    return a.value
}

// Consumes an unhandled key press, for application shortcuts. mods must match exactly.
key_pressed :: proc(s: ^State, key: Input_Key, mods: Modifiers = {}) -> bool {
    for &e in s.events {
        if !e.consumed && e.kind == .Key_Press && e.key == key && e.mods == mods {
            e.consumed = true
            return true
        }
    }
    return false
}

//- keyboard focus

focus_next :: proc(s: ^State, reverse: bool) {
    count := len(s.focus_order)
    if count == 0 {
        s.focus_hot = 0
        return
    }
    current := -1
    for k, i in s.focus_order do if k == s.focus_hot do current = i
    if current < 0 {
        current = reverse ? 0 : count - 1
    }
    s.focus_hot = s.focus_order[(current + (reverse ? count - 1 : 1)) % count]
}

//- context menus

ctx_menu_open :: proc(s: ^State, key: Key, anchor_key: Key = 0, anchor_off := Vec2{}) {
    s.ctx_menu = {
        key          = key,
        anchor_key   = anchor_key,
        anchor_off   = anchor_key == 0 ? s.mouse + anchor_off : anchor_off,
        open         = true,
        opened_build = s.build_index,
    }
}
ctx_menu_close :: proc(s: ^State) { s.ctx_menu.open = false }
ctx_menu_is_open :: proc(s: ^State, key: Key) -> bool { return s.ctx_menu.open && s.ctx_menu.key == key }

@(private)
ctx_menu_anchor :: proc(s: ^State) -> Vec2 {
    pos := s.ctx_menu.anchor_off
    if a := box_from_key(s, s.ctx_menu.anchor_key); a != nil do pos += a.rect.pos
    return pos
}

//- clipboard

clipboard_set :: proc(s: ^State, text: string) {
    if s.set_clipboard != nil {
        s.set_clipboard(text)
        return
    }
    clear(&s.clipboard)
    append(&s.clipboard, text)
}
clipboard_get :: proc(s: ^State) -> string {
    if s.get_clipboard != nil do return s.get_clipboard()
    return string(s.clipboard[:])
}

//- hit testing against the previous build

// Fills chain with every box under p, top-most first: the top box, then its ancestors.
@(private)
hit_chain :: proc(s: ^State, p: Vec2, chain: ^[dynamic]Key) {
    clear(chain)
    for i := len(s.draw_order) - 1; i >= 0; i -= 1 {
        b := s.draw_order[i]
        if !contains(intersection(b.rect, b.clip), p) do continue
        for a := b; a != nil; a = a.parent {
            if a.key != 0 do append(chain, a.key)
        }
        return
    }
}

@(private)
first_with_flag :: proc(s: ^State, chain: []Key, flag: Box_Flag) -> Key {
    for key in chain {
        b := s.cache[key]
        if b == nil do continue
        if .Disabled in b.flags do return 0
        if flag in b.flags do return key
    }
    return 0
}

//- frame

begin_build :: proc(s: ^State, viewport: Vec2, events: []Event, dt: f32) {
    assert(!s.building, "begin_build called twice")
    s.build_index += 1
    free_all(build_allocator(s))
    s.building = true
    s.viewport = {max(0, viewport.x), max(0, viewport.y)}
    s.dt = clamp(dt, 0, 0.1)
    s.time += f64(s.dt)
    s.animating = false
    s.hot = 0
    s.tooltip_wanted = false
    clear(&s.built_boxes)
    clear(&s.window_stack)
    clear(&s.scroll_stack)

    // Route input through last build's boxes (the draw order still points at them).
    clear(&s.events)
    chain := make([dynamic]Key, build_allocator(s))
    for ev in events {
        e := ev
        e.consumed = false
        #partial switch e.kind {
            case .Move, .Press, .Release, .Scroll:
                s.mouse = e.pos
                s.mouse_inside = true
                s.mods = e.mods
            case .Leave:
                s.mouse_inside = false
            case .Cancel:
                s.active = {}
                s.mouse_inside = false
                s.mods = {}
            case .Key_Press, .Key_Release, .Text:
                s.mods = e.mods
        }
        if e.kind == .Press || e.kind == .Scroll {
            hit_chain(s, e.pos, &chain)
            e.chain = slice.clone(chain[:], build_allocator(s))
            e.target = first_with_flag(s, e.chain, e.kind == .Press ? .Mouse_Clickable : .Scroll)
        }
        append(&s.events, e)
    }
    hit_chain(s, s.mouse, &s.hover_chain)
    if !s.mouse_inside do clear(&s.hover_chain)

    for &e in s.events {
        if e.consumed do continue
        #partial switch e.kind {
            case .Press:
                s.tooltip_key = 0
                // clicking outside an open context menu closes it; its anchor toggles it itself
                if s.ctx_menu.open && s.ctx_menu.opened_build != s.build_index {
                    menu_root := key_from_string(0, "###ctx_menu_root")
                    if !slice.contains(e.chain, menu_root) && !slice.contains(e.chain, s.ctx_menu.anchor_key) {
                        s.ctx_menu.open = false
                    }
                }
            case .Key_Press:
                if e.key == .Tab && e.mods - {.Shift} == {} {
                    e.consumed = true
                    s.focus_active = 0
                    s.focus_visible = true
                    focus_next(s, .Shift in e.mods)
                } else if e.key == .Escape && s.ctx_menu.open && s.focus_active == 0 {
                    e.consumed = true
                    s.ctx_menu.open = false
                }
        }
    }

    stacks_reset(s)

    // RAD convention: earlier siblings draw on top. The overlay roots are built first.
    st := &s.stacks
    stack_push(&st.pref_width, px(s.viewport.x), true)
    stack_push(&st.pref_height, px(s.viewport.y), true)
    s.root = build_box_from_key(s, {.Clip}, key_from_string(0, "###root"))
    stack_reset(&st.parent, s.root)

    s.ctx_menu_root = overlay_root(s, "###ctx_menu_root", s.ctx_menu.open ? ctx_menu_anchor(s) : {})
    s.tooltip_root = overlay_root(s, "###tooltip_root", s.mouse + Vec2{14, 18})
    stack_push(&st.pref_width, px(s.viewport.x), true)
    stack_push(&st.pref_height, px(s.viewport.y), true)
    s.windows_root = build_box_from_key(s, FLOATING, key_from_string(0, "###windows_root"))
}

@(private)
overlay_root :: proc(s: ^State, name: string, pos: Vec2) -> ^Box {
    st := &s.stacks
    stack_push(&st.pref_width, children_sum(), true)
    stack_push(&st.pref_height, children_sum(), true)
    b := build_box_from_key(s, FLOATING, key_from_string(0, name))
    b.fixed_position = pos
    return b
}

end_build :: proc(s: ^State) {
    assert(s.building, "end_build without begin_build")
    assert(len(s.window_stack) == 0 && len(s.scroll_stack) == 0, "Unbalanced window or scroll region")
    assert(stacks_balanced(s), "Unbalanced UI stack: a push without its pop")

    // a context menu that wasn't built this time is gone
    if s.ctx_menu.open && !s.ctx_menu.built && s.ctx_menu.opened_build != s.build_index do s.ctx_menu.open = false
    s.ctx_menu.built = false

    for e in s.events {
        if e.consumed do continue
        #partial switch e.kind {
            case .Press:
                // clicking empty space drops keyboard focus
                s.focus_active, s.focus_hot = 0, 0
            case .Release:
                s.active[e.button] = 0
            case .Key_Press:
                if e.key == .Escape {
                    if s.focus_active != 0 {
                        s.focus_active = 0
                    } else {
                        s.focus_hot = 0
                    }
                }
        }
    }

    prune(s)
    order_windows(s)

    // Animate before layout so this frame shows the new scroll offsets.
    fast, slow := fast_rate(s), slow_rate(s)
    for b in s.built_boxes {
        if b.flags & VIEW_SCROLL != {} do clamp_view(b)
        is_hot: f32 = b.key != 0 && b.key == s.hot ? 1 : 0
        is_active: f32 = b.key != 0 && (b.key == s.active[.Left] || b.key == s.active[.Right] || b.key == s.active[.Middle]) ? 1 : 0
        is_disabled: f32 = .Disabled in b.flags ? 1 : 0
        is_focus_hot: f32 = b.key != 0 && b.key == s.focus_hot ? 1 : 0
        is_focus_active: f32 = b.key != 0 && b.key == s.focus_active ? 1 : 0
        approach(s, &b.hot_t, is_hot, fast)
        approach(s, &b.active_t, is_active, fast)
        approach(s, &b.disabled_t, is_disabled, slow)
        approach(s, &b.focus_hot_t, is_focus_hot, fast)
        approach(s, &b.focus_active_t, is_focus_active, fast)
        for axis in 0 ..< 2 {
            delta := b.view_off_target[axis] - b.view_off[axis]
            b.view_off[axis] += delta * fast
            if abs(b.view_off_target[axis] - b.view_off[axis]) < 0.5 {
                b.view_off[axis] = b.view_off_target[axis]
            } else {
                s.animating = true
            }
        }
    }

    for axis in Axis do layout_root(s, s.root, axis)
    layout_clip(s.root, {{0, 0}, s.viewport})
    keep_in_viewport(s, s.tooltip_root)
    keep_in_viewport(s, s.ctx_menu_root)

    // tooltips appear after the pointer rests on the same box for a moment
    if s.tooltip_wanted {
        s.tooltip_time += s.dt
        if s.tooltip_time < TOOLTIP_DELAY do s.animating = true
    } else {
        s.tooltip_key, s.tooltip_time = 0, 0
    }

    s.cursor = .Default
    if active := box_from_key(s, s.active[.Left]); active != nil {
        s.cursor = active.hover_cursor
    } else if hot := box_from_key(s, s.hot); hot != nil {
        s.cursor = hot.hover_cursor
    }

    build_draw_commands(s)
    s.building = false
}

@(private)
approach :: proc(s: ^State, value: ^f32, target, rate: f32) {
    value^ += (target - value^) * rate
    if abs(target - value^) < 0.005 {
        value^ = target
    } else {
        s.animating = true
    }
}

// Frees boxes, animations and windows that weren't part of this build.
@(private)
prune :: proc(s: ^State) {
    stale := make([dynamic]Key, context.temp_allocator)
    for key, b in s.cache do if b.last_touched_build != s.build_index do append(&stale, key)
    for key in stale {
        b := s.cache[key]
        delete_key(&s.cache, key)
        append(&s.free_boxes, b)
        for &a in s.active do if a == key do a = 0
        if s.focus_hot == key do s.focus_hot = 0
        if s.focus_active == key do s.focus_active = 0
        if s.hot == key do s.hot = 0
    }
    clear(&stale)
    for key, a in s.anims do if a.last_build != s.build_index do append(&stale, key)
    for key in stale do delete_key(&s.anims, key)
    clear(&stale)
    for key, w in s.windows do if w.last_build != s.build_index do append(&stale, key)
    for key in stale {
        delete_key(&s.windows, key)
        if i, found := slice.linear_search(s.window_order[:], key); found do ordered_remove(&s.window_order, i)
    }
}

// Relinks the window boxes front to back. With earlier siblings drawn on top, the front window wins.
@(private)
order_windows :: proc(s: ^State) {
    root := s.windows_root
    if root.child_count < 2 do return
    kids := make([dynamic]^Box, 0, root.child_count, context.temp_allocator)
    for key in s.window_order {
        for c := root.first; c != nil; c = c.next do if c.key == key do append(&kids, c)
    }
    // anything that isn't a registered window keeps its place behind the windows
    for c := root.first; c != nil; c = c.next {
        if !slice.contains(s.window_order[:], c.key) do append(&kids, c)
    }
    root.first, root.last = kids[0], kids[len(kids) - 1]
    for c, j in kids {
        c.prev = j > 0 ? kids[j - 1] : nil
        c.next = j + 1 < len(kids) ? kids[j + 1] : nil
    }
}

raise_window :: proc(s: ^State, key: Key) {
    if i, found := slice.linear_search(s.window_order[:], key); found do ordered_remove(&s.window_order, i)
    inject_at(&s.window_order, 0, key)
}

// Shifts a floating overlay back inside the window once its size is known.
@(private)
keep_in_viewport :: proc(s: ^State, b: ^Box) {
    if b == nil || b.first == nil do return
    shift: Vec2
    for axis in 0 ..< 2 {
        over := b.rect.pos[axis] + b.rect.size[axis] - s.viewport[axis]
        if over > 0 do shift[axis] = -min(over, b.rect.pos[axis])
    }
    if shift == {} do return
    offset_tree(b, shift)
    layout_clip(b, b.clip)
}

@(private)
offset_tree :: proc(b: ^Box, delta: Vec2) {
    b.rect.pos += delta
    for c := b.first; c != nil; c = c.next do offset_tree(c, delta)
}
