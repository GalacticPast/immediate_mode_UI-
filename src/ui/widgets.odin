// Basic widgets in the style of RAD's ui_basic_widgets.c: each one is a few boxes plus a signal.
package ui

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

// Widgets use the theme's palette and radius unless the caller pushed or set_next'd their own.
@(private)
default_palette :: proc(s: ^State, p: Palette) {
    if len(s.stacks.palette.items) == 1 do set_next_palette(s, p)
}
@(private)
default_radius :: proc(s: ^State) {
    if len(s.stacks.corner_radii.items) == 1 do set_next_corner_radius(s, s.theme.corner_radius)
}

//- layout helpers

row_begin :: proc(s: ^State, width := Size{.Parent_Pct, 1, 0}, height := Size{.Children_Sum, 0, 1}, name := "") -> ^Box {
    set_next_child_layout_axis(s, .X)
    set_next_pref_size(s, width, height)
    b := build_box(s, {}, name)
    push_parent(s, b)
    return b
}
column_begin :: proc(s: ^State, width := Size{.Parent_Pct, 1, 0}, height := Size{.Children_Sum, 0, 1}, name := "") -> ^Box {
    set_next_child_layout_axis(s, .Y)
    set_next_pref_size(s, width, height)
    b := build_box(s, {}, name)
    push_parent(s, b)
    return b
}
row_end :: proc(s: ^State) { pop_parent(s) }
column_end :: proc(s: ^State) { pop_parent(s) }

// if ui.row(s) { ... } lays the scope's boxes out left to right. Pass a name when the row
// holds widgets whose names repeat in sibling rows: an unnamed row doesn't scope keys.
@(deferred_in = end_row)
row :: proc(s: ^State, width := Size{.Parent_Pct, 1, 0}, height := Size{.Children_Sum, 0, 1}, name := "") -> bool {
    row_begin(s, width, height, name)
    return true
}
end_row :: proc(s: ^State, width := Size{}, height := Size{}, name := "") { pop_parent(s) }

@(deferred_in = end_column)
column :: proc(s: ^State, width := Size{.Parent_Pct, 1, 0}, height := Size{.Children_Sum, 0, 1}, name := "") -> bool {
    column_begin(s, width, height, name)
    return true
}
end_column :: proc(s: ^State, width := Size{}, height := Size{}, name := "") { pop_parent(s) }

// Empty space along the parent's layout axis.
spacer :: proc(s: ^State, size: Size) -> ^Box {
    p := top_parent(s)
    axis := p != nil ? p.child_layout_axis : Axis.Y
    if axis == .X {
        set_next_pref_size(s, size, px(0))
    } else {
        set_next_pref_size(s, px(0), size)
    }
    return build_box_from_key(s, {}, 0)
}

// Space before and after the scope's boxes (RAD: UI_Padding).
@(deferred_in = end_padding)
padding :: proc(s: ^State, size: Size) -> bool {
    spacer(s, size)
    return true
}
end_padding :: proc(s: ^State, size: Size) { spacer(s, size) }

// A row inset on both sides, and a column inset top and bottom: padding on all four sides.
// Inside a scroll region pass height = children_sum() so the content can grow past the view.
@(deferred_in_out = end_panel)
panel :: proc(s: ^State, inset: f32 = 8, name := "", height := Size{.Parent_Pct, 1, 0}) -> bool {
    row_begin(s, fill(), height, name)
    spacer(s, px(inset))
    column_begin(s, fill(), height)
    spacer(s, px(inset))
    return true
}
end_panel :: proc(s: ^State, inset: f32, name: string, height: Size, ok: bool) {
    spacer(s, px(inset))
    column_end(s)
    spacer(s, px(inset))
    row_end(s)
}

//- text

label :: proc(s: ^State, text: string) -> Signal {
    b := build_box_from_key(s, {.Draw_Text}, 0)
    set_text(s, b, text)
    return {box = b}
}

// Secondary text in the palette's weak color.
label_weak :: proc(s: ^State, text: string) -> Signal {
    p := top_palette(s)
    p.text = p.text_weak
    set_next_palette(s, p)
    return label(s, text)
}

labelf :: proc(s: ^State, format: string, args: ..any) -> Signal {
    return label(s, fmt.tprintf(format, ..args))
}

separator :: proc(s: ^State) {
    p := top_parent(s)
    if p != nil && p.child_layout_axis == .X {
        set_next_pref_size(s, px(1), fill())
    } else {
        set_next_pref_size(s, fill(), px(1))
    }
    pal := top_palette(s)
    pal.background = pal.border
    set_next_palette(s, pal)
    build_box_from_key(s, {.Draw_Background}, 0)
}

//- buttons

button :: proc(s: ^State, name: string) -> Signal {
    default_palette(s, s.theme.button)
    default_radius(s)
    set_next_text_align(s, .Center)
    set_next_hover_cursor(s, .Pointer)
    b := build_box(
        s,
        CLICKABLE + {.Draw_Background, .Draw_Border, .Draw_Text, .Draw_Hot_Effects, .Draw_Active_Effects},
        name,
    )
    return signal_from_box(s, b)
}

// A button without a background until hovered (RAD: implicit buttons in lists and menus).
button_flat :: proc(s: ^State, name: string) -> Signal {
    set_next_hover_cursor(s, .Pointer)
    default_radius(s)
    b := build_box(s, CLICKABLE + {.Draw_Text, .Draw_Hot_Effects, .Draw_Active_Effects}, name)
    return signal_from_box(s, b)
}

@(private)
Check_Draw :: struct {
    t:     f32, // 0 unchecked, 1 checked, animated
    radio: bool,
}

@(private)
check_draw :: proc(s: ^State, b: ^Box, data: rawptr) {
    d := cast(^Check_Draw)data
    size: f32 = 16
    r := Rect{{b.rect.pos.x + 6, b.rect.pos.y + (b.rect.size.y - size) * 0.5}, {size, size}}
    radius: f32 = d.radio ? size * 0.5 : 3
    draw_rect(s, r, s.theme.input.background, radius)
    draw_rect(s, r, b.palette.border, radius, 1)
    if d.t > 0.01 {
        inner := pad_rect(r, -(d.radio ? 4.5 : 3.5) - (1 - d.t) * 4)
        color := b.palette.accent
        color.a *= d.t
        draw_rect(s, inner, color, d.radio ? inner.size.x * 0.5 : 2)
    }
}

@(private)
toggle_box :: proc(s: ^State, name: string, radio: bool) -> (^Box, Signal) {
    set_next_text_padding(s, 30)
    set_next_hover_cursor(s, .Pointer)
    default_radius(s)
    b := build_box(s, CLICKABLE + {.Draw_Text, .Draw_Hot_Effects}, name)
    sig := signal_from_box(s, b)
    d := new(Check_Draw, build_allocator(s))
    d.radio = radio
    b.custom_draw, b.custom_data = check_draw, d
    return b, sig
}

checkbox :: proc(s: ^State, name: string, value: ^bool) -> Signal {
    b, sig := toggle_box(s, name, false)
    if clicked(sig) do value^ = !value^
    (cast(^Check_Draw)b.custom_data).t = animate(s, b.key, value^ ? 1 : 0)
    return sig
}

radio :: proc(s: ^State, name: string, choice: ^int, value: int) -> Signal {
    b, sig := toggle_box(s, name, true)
    if clicked(sig) do choice^ = value
    (cast(^Check_Draw)b.custom_data).t = animate(s, b.key, choice^ == value ? 1 : 0)
    return sig
}

// A collapsible section header; build the section's content while it returns open.
expander :: proc(s: ^State, name: string, open: ^bool) -> Signal {
    set_next_text_padding(s, 24)
    set_next_hover_cursor(s, .Pointer)
    default_radius(s)
    b := build_box(s, CLICKABLE + {.Draw_Text, .Draw_Hot_Effects, .Draw_Active_Effects}, name)
    sig := signal_from_box(s, b)
    if clicked(sig) do open^ = !open^
    d := new(f32, build_allocator(s))
    d^ = animate(s, b.key, open^ ? 1 : 0)
    b.custom_data = d
    b.custom_draw = proc(s: ^State, b: ^Box, data: rawptr) {
        open := (cast(^f32)data)^ > 0.5
        draw_triangle(s, {b.rect.pos.x + 12, b.rect.pos.y + b.rect.size.y * 0.5}, 4, open, b.palette.text_weak)
    }
    return sig
}

// A small arrow drawn from one-pixel strips: pointing right, or down when down is set.
draw_triangle :: proc(s: ^State, center: Vec2, size: f32, down: bool, color: Color) {
    n := int(size)
    for i in 0 ..< n {
        extent := f32(n - i) * 2 - 1
        if down {
            draw_rect(s, {{center.x - extent * 0.5, center.y - size * 0.5 + f32(i)}, {extent, 1}}, color)
        } else {
            draw_rect(s, {{center.x - size * 0.5 + f32(i), center.y - extent * 0.5}, {1, extent}}, color)
        }
    }
}

//- values

@(private)
Fill_Draw :: struct {
    fraction: f32,
    color:    Color,
}

@(private)
fill_draw :: proc(s: ^State, b: ^Box, data: rawptr) {
    d := cast(^Fill_Draw)data
    r := pad_rect(b.rect, -2)
    r.size.x *= clamp(d.fraction, 0, 1)
    radii := b.corner_radii
    for &x in radii do x = max(0, x - 2)
    draw_rect_ex(s, r, all_colors(d.color), radii)
}

slider :: proc(s: ^State, name: string, value: ^f32, minimum, maximum: f32, format := "%.2f") -> Signal {
    assert(maximum > minimum)
    default_palette(s, s.theme.input)
    default_radius(s)
    set_next_text_align(s, .Center)
    set_next_hover_cursor(s, .Resize_EW)
    b := build_box(s, CLICKABLE + {.Draw_Background, .Draw_Border, .Draw_Text, .Draw_Hot_Effects}, name)
    sig := signal_from_box(s, b)
    span := maximum - minimum
    if .Left_Pressed in sig.flags || dragging(sig) {
        t := (s.mouse.x - b.rect.pos.x - 2) / max(1, b.rect.size.x - 4)
        value^ = minimum + clamp(t, 0, 1) * span
    }
    if s.focus_hot == b.key {
        for &e in s.events {
            if e.consumed || e.kind != .Key_Press do continue
            step := span * (.Shift in e.mods ? 0.1 : 0.01)
            #partial switch e.key {
                case .Left, .Down: value^ -= step
                case .Right, .Up: value^ += step
                case .Home: value^ = minimum
                case .End: value^ = maximum
                case: continue
            }
            e.consumed = true
        }
    }
    value^ = clamp(value^, minimum, maximum)
    shown := display_string(name)
    if len(shown) > 0 {
        set_text(s, b, fmt.tprintf("%s  %s", shown, fmt.tprintf(format, value^)))
    } else {
        set_text(s, b, fmt.tprintf(format, value^))
    }
    d := new(Fill_Draw, build_allocator(s))
    d.fraction = (value^ - minimum) / span
    d.color = b.palette.accent
    d.color.a *= 0.45 + 0.2 * b.hot_t
    b.custom_draw, b.custom_data = fill_draw, d
    return sig
}

// One labelled row of sliders, e.g. a color: ui.slider_n(s, "color", color[:], 0, 1)
slider_n :: proc(s: ^State, name: string, values: []f32, minimum, maximum: f32, format := "%.2f") -> (changed: bool) {
    row_begin(s, fill(), px(s.theme.row_height), name)
    set_next_pref_width(s, text_dim(8))
    label(s, display_string(name))
    for &v, i in values {
        before := v
        slider(s, fmt.tprintf("##%d", i), &v, minimum, maximum, format)
        changed ||= v != before
        if i + 1 < len(values) do spacer(s, px(4))
    }
    row_end(s)
    return
}

progress_bar :: proc(s: ^State, fraction: f32) {
    default_palette(s, s.theme.input)
    default_radius(s)
    b := build_box_from_key(s, {.Draw_Background, .Draw_Border}, 0)
    d := new(Fill_Draw, build_allocator(s))
    d.fraction, d.color = fraction, b.palette.accent
    b.custom_draw, b.custom_data = fill_draw, d
}

color_swatch :: proc(s: ^State, name: string, color: Color) -> Signal {
    p := top_palette(s)
    p.background = color
    set_next_palette(s, p)
    default_radius(s)
    b := build_box(s, {.Mouse_Clickable, .Draw_Background, .Draw_Border}, name)
    b.text = ""
    return signal_from_box(s, b)
}

//- text input

@(private)
Line_Edit_Draw :: struct {
    text:            string,
    cursor, mark:    int,
    editing:         bool,
    scroll:          f32,
}

@(private)
line_edit_draw :: proc(s: ^State, b: ^Box, data: rawptr) {
    d := cast(^Line_Edit_Draw)data
    height := s.measure_text("|", b.font_size).y
    origin := Vec2{b.rect.pos.x + b.text_padding - d.scroll, b.rect.pos.y + (b.rect.size.y - height) * 0.5}
    x_at :: proc(s: ^State, b: ^Box, text: string, i: int) -> f32 { return s.measure_text(text[:i], b.font_size).x }
    if d.editing && d.cursor != d.mark {
        lo, hi := min(d.cursor, d.mark), max(d.cursor, d.mark)
        x0, x1 := x_at(s, b, d.text, lo), x_at(s, b, d.text, hi)
        draw_rect(s, {{origin.x + x0, origin.y}, {x1 - x0, height}}, b.palette.selection, 2)
    }
    draw_text(s, d.text, origin, b.palette.text, b.font_size)
    if d.editing {
        x := x_at(s, b, d.text, d.cursor)
        draw_rect(s, {{origin.x + x - 1, origin.y}, {2, height}}, b.palette.cursor, 1)
    }
}

// Byte offset in text closest to x, measured from the text's start.
@(private)
index_from_x :: proc(s: ^State, text: string, font_size, x: f32) -> int {
    pen: f32
    for i := 0; i < len(text); {
        _, size := utf8.decode_rune_in_string(text[i:])
        w := s.measure_text(text[i:i + size], font_size).x
        if x < pen + w * 0.5 do return i
        pen += w
        i += size
    }
    return len(text)
}

// Single-line text field editing buffer[:length^]. Click or press Enter to edit;
// Enter commits (the signal has .Commit), Escape or clicking elsewhere stops editing.
line_edit :: proc(s: ^State, name: string, buffer: []u8, length: ^int) -> Signal {
    default_palette(s, s.theme.input)
    default_radius(s)
    set_next_hover_cursor(s, .Text)
    b := build_box(s, CLICKABLE + {.Click_To_Focus, .Draw_Background, .Draw_Border, .Draw_Hot_Effects, .Clip}, name)
    b.text = ""
    length^ = clamp(length^, 0, len(buffer))
    text := string(buffer[:length^])
    b.text_cursor = clamp(b.text_cursor, 0, length^)
    b.text_mark = clamp(b.text_mark, 0, length^)
    sig := signal_from_box(s, b)

    // keyboard focus plus Enter starts editing with everything selected
    if .Keyboard_Pressed in sig.flags {
        s.focus_active = b.key
        b.text_mark, b.text_cursor = 0, length^
    }
    editing := s.focus_active == b.key

    text_x := s.mouse.x - (b.rect.pos.x + b.text_padding - b.view_off.x)
    if .Left_Pressed in sig.flags {
        i := index_from_x(s, text, b.font_size, text_x)
        b.text_cursor = i
        if .Shift not_in s.mods do b.text_mark = i
        if .Left_Double_Clicked in sig.flags {
            b.text_mark, b.text_cursor = word_start(text, i), word_end(text, i)
        }
        if .Left_Triple_Clicked in sig.flags {
            b.text_mark, b.text_cursor = 0, length^
        }
    } else if dragging(sig) {
        b.text_cursor = index_from_x(s, text, b.font_size, text_x)
    }

    if editing {
        rune_bytes: [4]u8
        for &e in s.events {
            if e.consumed do continue
            if e.kind == .Key_Press && (e.key == .Enter || e.key == .Escape) {
                e.consumed = true
                if e.key == .Enter do sig.flags += {.Commit}
                s.focus_active = 0
                editing = false
                break
            }
            op, handled := text_op_from_event(text, b.text_cursor, b.text_mark, e)
            if !handled do continue
            e.consumed = true
            if op.copy do clipboard_set(s, text[op.replace_start:op.replace_end])
            insert: string
            if op.paste {
                insert = clipboard_get(s)
                // a single line field keeps only the first line
                if i := strings.index_any(insert, "\r\n"); i >= 0 do insert = insert[:i]
            } else if op.insert_rune != 0 {
                n: int
                rune_bytes, n = utf8.encode_rune(op.insert_rune)
                insert = string(rune_bytes[:n])
            }
            if op.edits {
                end := text_op_apply(op, insert, buffer, length)
                b.text_cursor, b.text_mark = end, end
                text = string(buffer[:length^])
            } else {
                b.text_cursor, b.text_mark = op.cursor, op.mark
            }
        }
    }

    // keep the cursor in view by scrolling the text sideways
    cursor_x := s.measure_text(text[:b.text_cursor], b.font_size).x
    visible := max(0, b.rect.size.x - 2 * b.text_padding)
    if cursor_x - b.view_off_target.x > visible do b.view_off_target.x = cursor_x - visible
    if cursor_x < b.view_off_target.x do b.view_off_target.x = cursor_x
    if !editing && cursor_x <= visible do b.view_off_target.x = 0
    b.view_off.x = b.view_off_target.x

    d := new(Line_Edit_Draw, build_allocator(s))
    d^ = {
        text    = strings.clone(text, build_allocator(s)),
        cursor  = b.text_cursor,
        mark    = b.text_mark,
        editing = editing,
        scroll  = b.view_off.x,
    }
    b.custom_draw, b.custom_data = line_edit_draw, d
    return sig
}
