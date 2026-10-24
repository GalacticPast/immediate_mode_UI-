// Adapted architecture: Epic Games Tools' RAD Debugger (MIT). See attribution.
package ui

import "core:math"
import "core:mem"
import "core:strings"

px :: proc(value: f32, strictness: f32 = 1) -> Size { return {.Pixels, max(0, value), clamp(strictness, 0, 1)} }
text_size :: proc(extra: f32 = 0) -> Size { return {.Text, extra, 1} }
children :: proc() -> Size { return {.Children, 0, 1} }
pct :: proc(value: f32) -> Size { return {.Parent_Percent, max(0, value), 0} }
fill :: proc(weight: f32 = 1) -> Size { return {.Fill, max(0, weight), 0} }

default_style :: proc() -> Style {
    return {
        width = fill(), height = px(30), axis = .Y, gap = 8,
        padding = {8, 4}, font_size = 14, radius = 4,
        background = {0.15, 0.17, 0.20}, border = {0.26, 0.29, 0.34},
        text = {0.87, 0.89, 0.93}, accent = {0.30, 0.60, 0.92},
    }
}

// State must stay at a stable address after init (its allocator points into it).
init :: proc(s: ^State, measure_text: Measure_Text, allocator := context.allocator) {
    s^ = {allocator = allocator, measure_text = measure_text, style = default_style()}
    s.cache = make(map[Key]^Box, allocator)
    s.boxes = make([dynamic]^Box, allocator)
    s.transient = make([dynamic]^Box, allocator)
    s.order = make([dynamic]^Box, allocator)
    s.parents = make([dynamic]^Box, allocator)
    s.styles = make([dynamic]Style, allocator)
    s.commands = make([dynamic]Draw_Command, allocator)
    mem.dynamic_arena_init(&s.frame_arena, allocator, allocator)
}

deinit :: proc(s: ^State) {
    for b in s.boxes do free(b, s.allocator)
    for b in s.transient do free(b, s.allocator)
    delete(s.cache)
    delete(s.boxes)
    delete(s.transient)
    delete(s.order)
    delete(s.parents)
    delete(s.styles)
    delete(s.commands)
    mem.dynamic_arena_destroy(&s.frame_arena)
    s^ = {}
}

frame_allocator :: proc(s: ^State) -> mem.Allocator { return mem.dynamic_arena_allocator(&s.frame_arena) }

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

contains :: proc(r: Rect, p: Vec2) -> bool {
    return p.x >= r.pos.x && p.y >= r.pos.y && p.x < r.pos.x+r.size.x && p.y < r.pos.y+r.size.y
}
intersection :: proc(a, b: Rect) -> Rect {
    lo := Vec2{max(a.pos.x, b.pos.x), max(a.pos.y, b.pos.y)}
    hi := Vec2{min(a.pos.x+a.size.x, b.pos.x+b.size.x), min(a.pos.y+a.size.y, b.pos.y+b.size.y)}
    return {lo, {max(0, hi.x-lo.x), max(0, hi.y-lo.y)}}
}

hit_test :: proc(s: ^State, pos: Vec2, flag: Flag) -> ^Box {
    // Reverse painter order: the visible foreground gets the first chance.
    for i := len(s.order)-1; i >= 0; i -= 1 {
        b := s.order[i]
        if contains(b.rect, pos) && contains(b.clip, pos) {
            // Noninteractive child decorations delegate to their ancestors.
            // A foreground overlay also blocks wheel events to background panels.
            for p := b; p != nil; p = p.parent {
                if .Disabled in p.flags do return nil
                if flag in p.flags do return p
            }
            return nil
        }
    }
    return nil
}

focus_next :: proc(s: ^State, reverse: bool) {
    current := -1
    for b, i in s.order do if b.key == s.focus && s.focus != 0 do current = i
    count := len(s.order)
    for offset in 1 ..= count {
        i := (current + offset) % count
        if reverse {
            start := current < 0 ? count : current
            i = (start - offset + count) % count
        }
        b := s.order[i]
        if .Clickable in b.flags && .Disabled not_in b.flags && b.key != 0 && b.clip.size.x > 0 && b.clip.size.y > 0 {
            s.focus = b.key
            return
        }
    }
    s.focus = 0
}

process_input :: proc(s: ^State, events: []Event) {
    for b in s.order do b.signal = {}
    for e in events {
        switch e.kind {
        case .Move, .Press, .Release, .Scroll:
            s.mouse = e.pos
            s.pointer_inside = true
        case .Leave:
            s.pointer_inside = false
        case .Cancel:
            s.active = 0
            s.focus = 0
            s.pointer_inside = false
        case .Key_Press:
        }
        switch e.kind {
        case .Press:
            target := hit_test(s, e.pos, .Clickable)
            s.active, s.focus = 0, 0
            if target != nil {
                s.active, s.focus = target.key, target.key
                s.drag_start = e.pos
                target.signal.pressed = true
                target.signal.drag_pos = e.pos
            }
        case .Move:
            if b := s.cache[s.active]; b != nil {
                b.signal.dragging = true
                b.signal.drag_pos = e.pos
                b.signal.drag_delta = e.pos - s.drag_start
            }
        case .Release:
            if b := s.cache[s.active]; b != nil {
                b.signal.released = true
                b.signal.drag_pos = e.pos
                b.signal.drag_delta = e.pos - s.drag_start
                b.signal.clicked = hit_test(s, e.pos, .Clickable) == b
            }
            s.active = 0
        case .Scroll:
            if b := hit_test(s, e.pos, .Scroll); b != nil {
                b.scroll_y = clamp(b.scroll_y + e.scroll, 0, max(0, b.content_size.y - b.rect.size.y + 2*b.style.padding.y))
            }
        case .Key_Press:
            if e.key == .Tab {
                focus_next(s, e.shift)
            } else if e.key == .Escape {
                s.active, s.focus = 0, 0
            } else if b := s.cache[s.focus]; b != nil {
                switch e.key {
                case .Enter, .Space: b.signal.clicked = true
                case .Left, .Down: b.signal.step -= 1
                case .Right, .Up: b.signal.step += 1
                case .Home: b.signal.home = true
                case .End: b.signal.end = true
                case .None, .Tab, .Escape:
                }
            }
        case .Cancel, .Leave:
        }
    }
    s.hot = 0
    if s.pointer_inside {
        if b := hit_test(s, s.mouse, .Clickable); b != nil {
            s.hot = b.key
            b.signal.hovered = true
        }
    }
    if b := s.cache[s.active]; b != nil {
        b.signal.dragging = true
        b.signal.drag_pos = s.mouse
        b.signal.drag_delta = s.mouse-s.drag_start
    }
}

begin_build :: proc(s: ^State, viewport: Vec2, events: []Event, dt: f32) {
    assert(!s.building)
    process_input(s, events) // Uses last build's rectangles, like RAD's box cache.
    for b in s.transient do free(b, s.allocator)
    clear(&s.transient)
    clear(&s.order)
    clear(&s.commands)
    mem.dynamic_arena_free_all(&s.frame_arena)
    s.build_index += 1
    s.building = true
    s.viewport = {max(0, viewport.x), max(0, viewport.y)}
    s.dt = clamp(dt, 0, 0.1)
    s.animating = false
    s.style = default_style()
    s.parent = nil
    s.root = box(s, "###ui_root", {})
    s.root.style.width = px(s.viewport.x)
    s.root.style.height = px(s.viewport.y)
    s.root.style.padding = {}
    s.root.style.gap = 0
    s.root.flags = {.Clip}
    s.parent = s.root
}

box :: proc(s: ^State, name: string, flags: Flags) -> ^Box {
    assert(s.building)
    seed: Key
    for p := s.parent; p != nil; p = p.parent {
        if p.key != 0 { seed = p.key; break }
    }
    key := key_from_string(seed, name)
    b: ^Box
    if key != 0 {
        b = s.cache[key]
        if b == nil {
            b = new(Box, s.allocator)
            s.cache[key] = b
            append(&s.boxes, b)
        }
        assert(b.last_build != s.build_index, "Duplicate UI key in the same parent scope")
    } else {
        assert(.Clickable not_in flags && .Scroll not_in flags, "Interactive boxes need a stable key")
        b = new(Box, s.allocator)
        append(&s.transient, b)
    }
    // Preserve geometry for interaction and animation, but rebuild the structure.
    old := b^
    b^ = {key = key, flags = flags, style = s.style, parent = s.parent,
          rect = old.rect, clip = old.clip, scroll_y = old.scroll_y,
          content_size = old.content_size, hot_t = old.hot_t, active_t = old.active_t,
          signal = old.signal, last_build = s.build_index}
    if s.parent != nil {
        if .Disabled in s.parent.flags do b.flags += {.Disabled}
        b.prev = s.parent.last
        if b.prev != nil do b.prev.next = b
        if s.parent.first == nil do s.parent.first = b
        s.parent.last = b
        s.parent.child_count += 1
    }
    if .Disabled in b.flags {
        b.signal = {}
        if s.active == key do s.active = 0
        if s.focus == key do s.focus = 0
    }
    if .Text in flags do b.text = strings.clone(display_string(name), frame_allocator(s))
    append(&s.order, b)
    return b
}

set_text :: proc(s: ^State, b: ^Box, text: string) {
    b.text = strings.clone(text, frame_allocator(s))
    b.flags += {.Text}
}
push_parent :: proc(s: ^State, b: ^Box) { append(&s.parents, s.parent); s.parent = b }
pop_parent :: proc(s: ^State) { assert(len(s.parents) > 0); s.parent = pop(&s.parents) }
push_style :: proc(s: ^State, style: Style) { append(&s.styles, s.style); s.style = style }
pop_style :: proc(s: ^State) { assert(len(s.styles) > 0); s.style = pop(&s.styles) }

measure_box :: proc(s: ^State, b: ^Box) {
    if b == nil do return
    sizes := [2]Size{b.style.width, b.style.height}
    text_dim: Vec2
    if .Text in b.flags && s.measure_text != nil do text_dim = s.measure_text(b.text, b.style.font_size)
    for axis in 0 ..< 2 {
        spec := sizes[axis]
        switch spec.kind {
        case .Pixels: b.measured[axis] = spec.value
        case .Text: b.measured[axis] = text_dim[axis] + 2*b.style.padding[axis] + spec.value
        case .Children, .Parent_Percent, .Fill: b.measured[axis] = 0
        }
    }
    extent: Vec2
    count := 0
    for c := b.first; c != nil; c = c.next {
        measure_box(s, c)
        if .Floating in c.flags do continue
        main := int(b.style.axis)
        cross := 1-main
        extent[main] += c.measured[main]
        extent[cross] = max(extent[cross], c.measured[cross])
        count += 1
    }
    if count > 1 do extent[int(b.style.axis)] += f32(count-1)*b.style.gap
    for axis in 0 ..< 2 {
        if sizes[axis].kind == .Children do b.measured[axis] = extent[axis] + 2*b.style.padding[axis]
    }
}

arrange_box :: proc(b: ^Box, rect, inherited_clip: Rect) {
    b.rect = rect
    b.clip = intersection(rect, inherited_clip)
    inner := Vec2{max(0, rect.size.x-2*b.style.padding.x), max(0, rect.size.y-2*b.style.padding.y)}
    axis := int(b.style.axis)
    cross := 1-axis
    total, weight, shrink: f32
    count := 0
    for c := b.first; c != nil; c = c.next {
        specs := [2]Size{c.style.width, c.style.height}
        for a in 0 ..< 2 {
            if specs[a].kind == .Parent_Percent do c.measured[a] = inner[a]*specs[a].value
            if specs[a].kind == .Fill do c.measured[a] = 0
        }
        if specs[cross].kind == .Fill do c.measured[cross] = inner[cross]
        if .Floating in c.flags do continue
        total += c.measured[axis]
        if specs[axis].kind == .Fill do weight += specs[axis].value
        shrink += c.measured[axis]*(1-specs[axis].strictness)
        count += 1
    }
    if count > 1 do total += f32(count-1)*b.style.gap
    remaining := max(0, inner[axis]-total)
    excess := max(0, total-inner[axis])
    if .Scroll in b.flags && axis == 1 do excess = 0
    b.content_size = {}
    for c := b.first; c != nil; c = c.next {
        if .Floating in c.flags do continue
        spec := axis == 0 ? c.style.width : c.style.height
        if spec.kind == .Fill && weight > 0 do c.measured[axis] = remaining*spec.value/weight
        if excess > 0 && shrink > 0 do c.measured[axis] -= min(1, excess/shrink)*c.measured[axis]*(1-spec.strictness)
        b.content_size[axis] += c.measured[axis]
        b.content_size[cross] = max(b.content_size[cross], c.measured[cross])
    }
    if count > 1 do b.content_size[axis] += f32(count-1)*b.style.gap
    b.scroll_y = clamp(b.scroll_y, 0, max(0, b.content_size.y-inner.y))
    child_clip := inherited_clip
    if .Clip in b.flags || .Scroll in b.flags do child_clip = b.clip
    offset: f32
    for c := b.first; c != nil; c = c.next {
        pos := rect.pos + b.style.padding
        if .Floating in c.flags {
            pos += c.floating_pos
        } else {
            pos[axis] += offset
            offset += c.measured[axis]+b.style.gap
            if .Scroll in b.flags do pos.y -= b.scroll_y
        }
        arrange_box(c, {pos, c.measured}, child_clip)
    }
}

end_build :: proc(s: ^State) {
    assert(s.building && len(s.parents) == 0 && len(s.styles) == 0, "Unbalanced UI scope")
    measure_box(s, s.root)
    arrange_box(s.root, {{0, 0}, s.viewport}, {{0, 0}, s.viewport})
    for i := 0; i < len(s.boxes); {
        b := s.boxes[i]
        if b.last_build != s.build_index {
            if s.active == b.key do s.active = 0
            if s.focus == b.key do s.focus = 0
            if s.hot == b.key do s.hot = 0
            delete_key(&s.cache, b.key)
            free(b, s.allocator)
            unordered_remove(&s.boxes, i)
        } else {
            i += 1
        }
    }
    blend := 1 - math.exp(-18*s.dt)
    for b in s.order {
        hot: f32 = b.key != 0 && b.key == s.hot ? 1 : 0
        active: f32 = b.key != 0 && b.key == s.active ? 1 : 0
        b.hot_t += (hot-b.hot_t)*blend
        b.active_t += (active-b.active_t)*blend
        if abs(hot-b.hot_t) > 0.005 || abs(active-b.active_t) > 0.005 do s.animating = true
    }
    build_draw_commands(s)
    s.building = false
}
