// Overlays: tooltips, context menus, menus, combo boxes, floating windows and scroll regions.
package ui

import "core:fmt"
import "core:slice"

//- tooltips

// Shows the scope's boxes next to the pointer once it has rested on sig's box for a moment.
//     if ui.tooltip(s, sig) { ui.label(s, "Explains the button") }
@(deferred_in_out = end_tooltip)
tooltip :: proc(s: ^State, sig: Signal) -> bool {
    if sig.box == nil || sig.box.key == 0 || .Hovering not_in sig.flags || s.active != {} do return false
    s.tooltip_wanted = true
    if s.tooltip_key != sig.box.key {
        s.tooltip_key, s.tooltip_time = sig.box.key, 0
        return false
    }
    if s.tooltip_time < TOOLTIP_DELAY do return false
    push_parent(s, s.tooltip_root)
    t := animate(s, key_from_string(sig.box.key, "###tooltip"), 1, initial = 0)
    set_next_transparency(s, 1 - t)
    set_next_child_layout_axis(s, .Y)
    set_next_pref_size(s, children_sum(), children_sum())
    set_next_palette(s, s.theme.tooltip)
    set_next_corner_radius(s, s.theme.corner_radius)
    b := build_box_from_key(s, {.Draw_Background, .Draw_Border, .Draw_Drop_Shadow}, 0)
    push_parent(s, b)
    push_pref_width(s, text_dim(4))
    push_pref_height(s, px(s.theme.row_height - 4))
    push_palette(s, s.theme.tooltip)
    return true
}
end_tooltip :: proc(s: ^State, sig: Signal, ok: bool) {
    if !ok do return
    pop_palette(s)
    pop_pref_height(s)
    pop_pref_width(s)
    pop_parent(s)
    pop_parent(s)
}

//- context menus

// Builds the menu's panel if the menu with this key is open. Prefer the scoped ctx_menu.
ctx_menu_begin :: proc(s: ^State, key: Key) -> bool {
    if !ctx_menu_is_open(s, key) do return false
    s.ctx_menu.built = true
    s.ctx_menu_root.fixed_position = ctx_menu_anchor(s)
    push_parent(s, s.ctx_menu_root)
    t := animate(s, key, 1, initial = 0)
    set_next_transparency(s, 1 - t)
    set_next_squish(s, 0.08 * (1 - t))
    set_next_child_layout_axis(s, .Y)
    set_next_pref_size(s, children_sum(), children_sum())
    set_next_palette(s, s.theme.floating)
    set_next_corner_radius(s, s.theme.corner_radius)
    b := build_box_from_key(
        s,
        {.Mouse_Clickable, .Draw_Background, .Draw_Border, .Draw_Drop_Shadow, .Clip, .Squish_Anchored},
        key,
    )
    s.ctx_menu.container, s.ctx_menu.width = b, 0
    push_parent(s, b)
    push_palette(s, s.theme.floating)
    spacer(s, px(4))
    return true
}

ctx_menu_end_build :: proc(s: ^State) {
    spacer(s, px(4))
    pop_palette(s)
    pop_parent(s)
    // the items measured themselves while being built, so the panel can fit the widest one
    b := s.ctx_menu.container
    b.flags += {.Fixed_Width}
    b.fixed_size.x = max(s.ctx_menu.width, 140)
    signal_from_box(s, b) // presses between items stay in the menu
    pop_parent(s)
}

//     if ui.right_clicked(sig) do ui.ctx_menu_open(s, menu_key)
//     if ui.ctx_menu(s, menu_key) { if ui.clicked(ui.menu_item(s, "Copy")) {...} }
@(deferred_in_out = end_ctx_menu)
ctx_menu :: proc(s: ^State, key: Key) -> bool { return ctx_menu_begin(s, key) }
end_ctx_menu :: proc(s: ^State, key: Key, ok: bool) { if ok do ctx_menu_end_build(s) }

@(private)
Shortcut_Draw :: struct {
    text: string,
}

// A menu entry. Clicking it closes the menu.
menu_item :: proc(s: ^State, name: string, shortcut := "") -> Signal {
    font := stack_top(&s.stacks.font_size)
    width := s.measure_text(display_string(name), font).x + 24
    if len(shortcut) > 0 do width += s.measure_text(shortcut, font).x + 32
    s.ctx_menu.width = max(s.ctx_menu.width, width)

    pal := top_palette(s)
    pal.overlay = pal.accent
    pal.overlay.a = 0.35
    set_next_palette(s, pal)
    set_next_pref_size(s, fill(), px(s.theme.row_height))
    set_next_text_padding(s, 12)
    set_next_hover_cursor(s, .Pointer)
    b := build_box(s, CLICKABLE + {.Draw_Text, .Draw_Hot_Effects, .Draw_Active_Effects}, name)
    if len(shortcut) > 0 {
        d := new(Shortcut_Draw, build_allocator(s))
        d.text = fmt.aprint(shortcut, allocator = build_allocator(s))
        b.custom_data = d
        b.custom_draw = proc(s: ^State, b: ^Box, data: rawptr) {
            text := (cast(^Shortcut_Draw)data).text
            dim := s.measure_text(text, b.font_size)
            pos := b.rect.pos + Vec2{b.rect.size.x - b.text_padding - dim.x, (b.rect.size.y - dim.y) * 0.5}
            draw_text(s, text, pos, b.palette.text_weak, b.font_size)
        }
    }
    sig := signal_from_box(s, b)
    if clicked(sig) do ctx_menu_close(s)
    return sig
}

//- menu bar

@(deferred_in = end_menu_bar)
menu_bar :: proc(s: ^State) -> bool {
    set_next_child_layout_axis(s, .X)
    set_next_pref_size(s, fill(), px(s.theme.row_height + 2))
    set_next_palette(s, s.theme.menu_bar)
    b := build_box(s, {.Draw_Background, .Draw_Side_Bottom}, "###menu_bar")
    push_parent(s, b)
    push_pref_width(s, text_dim(8))
    push_pref_height(s, fill())
    push_palette(s, s.theme.menu_bar)
    return true
}
end_menu_bar :: proc(s: ^State) {
    pop_palette(s)
    pop_pref_height(s)
    pop_pref_width(s)
    pop_parent(s)
}

// A menu bar entry whose dropdown is the scope:
//     if ui.menu(s, "File") { if ui.clicked(ui.menu_item(s, "Quit", "Ctrl+Q")) {...} }
@(deferred_in_out = end_menu)
menu :: proc(s: ^State, name: string) -> bool {
    set_next_text_align(s, .Center)
    b := build_box(s, CLICKABLE + {.Draw_Text, .Draw_Hot_Effects, .Draw_Active_Effects}, name)
    sig := signal_from_box(s, b)
    key := key_from_string(b.key, "###menu")
    is_open := ctx_menu_is_open(s, key)
    if pressed(sig) {
        if is_open {
            ctx_menu_close(s)
        } else {
            ctx_menu_open(s, key, b.key, {0, b.rect.size.y})
        }
    } else if hovering(sig) && s.ctx_menu.open && !is_open {
        // with one menu of the bar open, hovering a sibling switches to it
        if anchor := box_from_key(s, s.ctx_menu.anchor_key); anchor != nil && anchor.parent == b.parent {
            ctx_menu_open(s, key, b.key, {0, b.rect.size.y})
        }
    }
    if ctx_menu_is_open(s, key) do b.hot_t = 1
    return ctx_menu_begin(s, key)
}
end_menu :: proc(s: ^State, name: string, ok: bool) { if ok do ctx_menu_end_build(s) }

//- combo box

@(private)
combo_draw :: proc(s: ^State, b: ^Box, data: rawptr) {
    c := Vec2{b.rect.pos.x + b.rect.size.x - 14, b.rect.pos.y + b.rect.size.y * 0.5}
    draw_triangle(s, c, 4, true, b.palette.text_weak)
}

// A button showing items[index^] that drops down a menu of all items.
combo :: proc(s: ^State, name: string, index: ^int, items: []string) -> Signal {
    default_palette(s, s.theme.button)
    default_radius(s)
    set_next_hover_cursor(s, .Pointer)
    b := build_box(
        s,
        CLICKABLE + {.Draw_Background, .Draw_Border, .Draw_Text, .Draw_Hot_Effects, .Draw_Active_Effects},
        name,
    )
    current := index^ >= 0 && index^ < len(items) ? items[index^] : ""
    shown := display_string(name)
    set_text(s, b, len(shown) > 0 ? fmt.tprintf("%s: %s", shown, current) : current)
    b.custom_draw = combo_draw
    sig := signal_from_box(s, b)
    key := key_from_string(b.key, "###combo")
    if clicked(sig) {
        if ctx_menu_is_open(s, key) {
            ctx_menu_close(s)
        } else {
            ctx_menu_open(s, key, b.key, {0, b.rect.size.y + 2})
        }
    }
    if ctx_menu(s, key) {
        s.ctx_menu.width = max(s.ctx_menu.width, b.rect.size.x)
        for item, i in items {
            if clicked(menu_item(s, fmt.tprintf("%s###item%d", item, i))) do index^ = i
        }
    }
    return sig
}

//- floating windows

Window_Option :: enum { No_Title_Bar, No_Resize, No_Move }
Window_Options :: bit_set[Window_Option]
Window_Desc :: struct {
    position: Vec2, // initial placement; afterwards the user moves it
    size:     Vec2, // initial size, {} for a default
    options:  Window_Options,
}

@(private)
grip_draw :: proc(s: ^State, b: ^Box, data: rawptr) {
    color := b.palette.text_weak
    color.a *= 0.5 + 0.5 * b.hot_t
    corner := b.rect.pos + b.rect.size - 3
    for i in 0 ..< 3 {
        for j in 0 ..< 3 - i {
            draw_rect(s, {corner - Vec2{f32(i), f32(j)} * 4 - 1, {2, 2}}, color)
        }
    }
}

// A movable, resizable panel above the main UI. Windows come to the front when clicked.
// open, if given, adds a close button that clears it.
//     if ui.window(s, "Inspector", {position = {40, 40}}, &show_inspector) { ... }
@(deferred_in_out = end_window)
window :: proc(s: ^State, title: string, desc: Window_Desc = {}, open: ^bool = nil) -> bool {
    if open != nil && !open^ do return false
    key := key_from_string(s.windows_root.key, title)
    if key not_in s.windows {
        size := desc.size == {} ? Vec2{320, 240} : desc.size
        s.windows[key] = {pos = desc.position, size = size}
        inject_at(&s.window_order, 0, key)
    }
    ws := &s.windows[key]
    ws.last_build = s.build_index
    for e in s.events {
        if e.kind == .Press && slice.contains(e.chain, key) do raise_window(s, key)
    }

    push_parent(s, s.windows_root)
    set_next_fixed_pos(s, ws.pos)
    set_next_fixed_size(s, ws.size)
    set_next_child_layout_axis(s, .Y)
    set_next_palette(s, s.theme.floating)
    set_next_corner_radius(s, s.theme.corner_radius + 2)
    b := build_box_from_key(s, {.Mouse_Clickable, .Draw_Background, .Draw_Border, .Draw_Drop_Shadow, .Clip}, key)
    push_parent(s, b)

    if .No_Title_Bar not_in desc.options {
        r := s.theme.corner_radius + 2
        set_next_child_layout_axis(s, .X)
        set_next_pref_size(s, fill(), px(s.theme.row_height + 4))
        set_next_palette(s, s.theme.title_bar)
        set_next_corner_radii(s, {.Top_Left = r, .Top_Right = r, .Bottom_Right = 0, .Bottom_Left = 0})
        if .No_Move not_in desc.options do set_next_hover_cursor(s, .Move)
        bar := build_box(s, {.Mouse_Clickable, .Draw_Background, .Draw_Side_Bottom}, "###title_bar")
        push_parent(s, bar)
        push_palette(s, s.theme.title_bar)
        set_next_pref_size(s, fill(), fill())
        label(s, display_string(title))
        if open != nil {
            set_next_pref_size(s, px(s.theme.row_height + 4), fill())
            set_next_text_align(s, .Center)
            if clicked(button_flat(s, "x###close")) do open^ = false
        }
        pop_palette(s)
        pop_parent(s)
        bar_sig := signal_from_box(s, bar)
        if .No_Move not_in desc.options {
            if .Left_Pressed in bar_sig.flags do store_drag_data(s, ws.pos)
            if dragging(bar_sig) {
                pos := get_drag_data(s, Vec2) + drag_delta(s)
                // keep enough of the title bar on screen to grab it again
                pos.x = clamp(pos.x, 60 - ws.size.x, max(0, s.viewport.x - 60))
                pos.y = clamp(pos.y, 0, max(0, s.viewport.y - 30))
                ws.pos = pos
                b.fixed_position = pos
            }
        }
    }

    row_begin(s, fill(), fill(), "###content")
    spacer(s, px(10))
    column_begin(s, fill(), fill())
    spacer(s, px(8))
    append(&s.window_stack, b)
    return true
}

end_window :: proc(s: ^State, title: string, desc: Window_Desc, open: ^bool, ok: bool) {
    if !ok do return
    b := pop(&s.window_stack)
    spacer(s, px(8))
    column_end(s)
    spacer(s, px(10))
    row_end(s)

    ws := &s.windows[b.key]
    if .No_Resize not_in desc.options {
        grip: f32 = 14
        set_next_fixed_pos(s, ws.size - grip)
        set_next_fixed_size(s, {grip, grip})
        set_next_hover_cursor(s, .Resize_NWSE)
        g := build_box(s, {.Mouse_Clickable}, "###resize")
        g.custom_draw = grip_draw
        sig := signal_from_box(s, g)
        if .Left_Pressed in sig.flags do store_drag_data(s, ws.size)
        if dragging(sig) {
            size := get_drag_data(s, Vec2) + drag_delta(s)
            ws.size = {max(size.x, 140), max(size.y, 80)}
            b.fixed_size = ws.size
        }
    }
    pop_parent(s)
    signal_from_box(s, b) // the window's background swallows presses
    pop_parent(s)
}

//- scrolling

// A clipped region that scrolls its content, with scroll bars when the content overflows.
//     if ui.scroll_region(s, "list", height = ui.px(200)) { ...many rows... }
@(deferred_in_out = end_scroll_region)
scroll_region :: proc(
    s: ^State,
    name: string,
    width := Size{.Parent_Pct, 1, 0},
    height := Size{.Parent_Pct, 1, 0},
    axes := bit_set[Axis]{.Y},
) -> bool {
    set_next_child_layout_axis(s, .Y)
    set_next_pref_size(s, width, height)
    outer := build_box(s, {}, name)
    push_parent(s, outer)
    set_next_child_layout_axis(s, .X)
    set_next_pref_size(s, fill(), fill())
    row := build_box(s, {}, "###row")
    push_parent(s, row)

    view_flags := Box_Flags{.Clip, .Scroll}
    if .X in axes do view_flags += {.View_Scroll_X, .Allow_Overflow_X}
    if .Y in axes do view_flags += {.View_Scroll_Y, .Allow_Overflow_Y}
    set_next_child_layout_axis(s, .Y)
    set_next_pref_size(s, fill(), fill())
    view := build_box(s, view_flags, "###view")
    push_parent(s, view)
    append(&s.scroll_stack, [2]^Box{outer, view})
    return true
}

// The view box of the innermost scroll region being built. Its view_off_target scrolls the
// content (end_build clamps it), its rect and view_bounds are the visible and total sizes.
scroll_view :: proc(s: ^State) -> ^Box {
    if len(s.scroll_stack) == 0 do return nil
    return s.scroll_stack[len(s.scroll_stack) - 1][1]
}

end_scroll_region :: proc(s: ^State, name: string, width, height: Size, axes: bit_set[Axis], ok: bool) {
    if !ok do return
    view := pop(&s.scroll_stack)[1]
    pop_parent(s)
    // after the content, so nested regions under the pointer get the wheel first
    signal_from_box(s, view)
    if .Y in axes && view.view_bounds.y > view.rect.size.y + 0.5 do scroll_bar(s, view, .Y)
    pop_parent(s)
    if .X in axes && view.view_bounds.x > view.rect.size.x + 0.5 do scroll_bar(s, view, .X)
    pop_parent(s)
}

// A track and a draggable thumb that scroll view along axis. Clicking the track pages.
scroll_bar :: proc(s: ^State, view: ^Box, axis: Axis) {
    a := int(axis)
    thickness: f32 = 10
    if axis == .Y {
        set_next_pref_size(s, px(thickness), fill())
    } else {
        set_next_pref_size(s, fill(), px(thickness))
    }
    set_next_palette(s, s.theme.scroll_bar)
    track := build_box(s, {.Mouse_Clickable, .Draw_Background}, axis == .Y ? "###scroll_y" : "###scroll_x")

    length := track.rect.size[a]
    content := max(view.view_bounds[a], 1)
    visible := view.rect.size[a]
    max_off := max(0, content - visible)
    thumb_len := clamp(length * visible / content, min(24, length), length)
    travel := max(1, length - thumb_len)
    thumb_pos := max_off > 0 ? travel * view.view_off[a] / max_off : 0

    push_parent(s, track)
    pos, size: Vec2
    pos[a], size[a] = thumb_pos, thumb_len
    pos[1 - a], size[1 - a] = 2, thickness - 4
    thumb_pal := s.theme.scroll_bar
    thumb_pal.background = thumb_pal.border
    set_next_fixed_pos(s, pos)
    set_next_fixed_size(s, size)
    set_next_corner_radius(s, (thickness - 4) * 0.5)
    set_next_palette(s, thumb_pal)
    thumb := build_box(s, {.Mouse_Clickable, .Draw_Background, .Draw_Hot_Effects, .Draw_Active_Effects}, "###thumb")
    pop_parent(s)

    thumb_sig := signal_from_box(s, thumb)
    if .Left_Pressed in thumb_sig.flags do store_drag_data(s, view.view_off_target[a])
    if dragging(thumb_sig) {
        off := get_drag_data(s, f32) + drag_delta(s)[a] * max_off / travel
        view.view_off_target[a] = clamp(off, 0, max_off)
        view.view_off[a] = view.view_off_target[a]
    }
    track_sig := signal_from_box(s, track)
    if .Left_Pressed in track_sig.flags {
        before_thumb := s.mouse[a] < track.rect.pos[a] + thumb_pos
        view.view_off_target[a] = clamp(view.view_off_target[a] + (before_thumb ? -visible : visible), 0, max_off)
    }
}
