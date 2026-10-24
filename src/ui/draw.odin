package ui

import "core:math"
import "core:strings"

//- primitives for widgets and custom draw callbacks
// They apply the current subtree's squish transform, transparency and clip.

draw_rect_ex :: proc(s: ^State, r: Rect, colors: [Corner]Color, radii: [Corner]f32, border: f32 = 0, softness: f32 = 0) {
    k := s.draw_scale
    rect := Rect{r.pos * k + s.draw_offset, r.size * k}
    if rect.size.x <= 0 || rect.size.y <= 0 || s.draw_clip.size.x <= 0 || s.draw_clip.size.y <= 0 do return
    out := Rect_Draw{rect = rect, border = border * k, softness = softness * k}
    visible := false
    for c in Corner {
        out.colors[c] = colors[c]
        out.colors[c].a *= s.draw_alpha
        out.radii[c] = radii[c] * k
        visible ||= out.colors[c].a > 0
    }
    if !visible do return
    append(&s.commands, Draw_Command{s.draw_clip, out})
}

draw_rect :: proc(s: ^State, r: Rect, color: Color, radius: f32 = 0, border: f32 = 0, softness: f32 = 0) {
    draw_rect_ex(s, r, all_colors(color), all_corners(radius), border, softness)
}

// Vertical gradient.
draw_rect_gradient :: proc(s: ^State, r: Rect, top, bottom: Color, radii: [Corner]f32) {
    draw_rect_ex(s, r, {.Top_Left = top, .Top_Right = top, .Bottom_Right = bottom, .Bottom_Left = bottom}, radii)
}

draw_text :: proc(s: ^State, text: string, pos: Vec2, color: Color, font_size: f32) {
    if len(text) == 0 || color.a * s.draw_alpha <= 0 || s.draw_clip.size.x <= 0 || s.draw_clip.size.y <= 0 do return
    c := color
    c.a *= s.draw_alpha
    p := pos * s.draw_scale + s.draw_offset
    append(&s.commands, Draw_Command{s.draw_clip, Text_Draw{text, {math.round(p.x), math.round(p.y)}, c, font_size * s.draw_scale}})
}

// Where a box's text starts, after alignment.
text_position :: proc(s: ^State, b: ^Box, text: string) -> Vec2 {
    dim := s.measure_text(text, b.font_size)
    pos := Vec2{b.rect.pos.x + b.text_padding, b.rect.pos.y + (b.rect.size.y - dim.y) * 0.5}
    switch b.text_align {
        case .Left:
        case .Center: pos.x = b.rect.pos.x + (b.rect.size.x - dim.x) * 0.5
        case .Right: pos.x = b.rect.pos.x + b.rect.size.x - b.text_padding - dim.x
    }
    return pos
}

// Cuts text to fit width, ending in "...".
truncate_text :: proc(s: ^State, text: string, font_size, width: f32) -> string {
    if s.measure_text(text, font_size).x <= width do return text
    ellipsis :: "..."
    budget := width - s.measure_text(ellipsis, font_size).x
    used: f32
    n := 0
    for n < len(text) {
        w := s.measure_text(text[n:n + 1], font_size).x
        if used + w > budget do break
        used += w
        n += 1
    }
    return strings.concatenate({text[:n], ellipsis}, build_allocator(s))
}

//- traversal

build_draw_commands :: proc(s: ^State) {
    clear(&s.commands)
    clear(&s.draw_order)
    clear(&s.focus_order)
    draw_box(s, s.root, 1, {}, 1, true)
}

@(private)
// hit: whether the box takes part in hit testing (tooltips never block the pointer)
draw_box :: proc(s: ^State, b: ^Box, parent_scale: f32, parent_offset: Vec2, parent_alpha: f32, parent_hit: bool) {
    hit := parent_hit && b != s.tooltip_root
    alpha := parent_alpha * (1 - clamp(b.transparency, 0, 1))
    if alpha <= 0.002 do return
    scale, offset := parent_scale, parent_offset
    if b.squish > 0 {
        // squish scales the subtree around its center (or top edge) when drawn; hit testing ignores it
        k := 1 - clamp(b.squish, 0, 1)
        anchor := b.rect.pos + b.rect.size * Vec2{0.5, .Squish_Anchored in b.flags ? 0 : 0.5}
        offset += anchor * (1 - k) * scale
        scale *= k
    }
    visible := b.clip.size.x > 0 && b.clip.size.y > 0 && b.rect.size.x > 0 && b.rect.size.y > 0
    if visible && intersection(b.rect, b.clip).size.x > 0 && intersection(b.rect, b.clip).size.y > 0 {
        if hit && b.flags & HIT_FLAGS != {} do append(&s.draw_order, b)
        if .Keyboard_Clickable in b.flags && .Disabled not_in b.flags && b.key != 0 do append(&s.focus_order, b.key)
    }

    set_draw_state :: proc(s: ^State, clip: Rect, scale: f32, offset: Vec2, alpha: f32) {
        s.draw_clip = {clip.pos * scale + offset, clip.size * scale}
        s.draw_scale, s.draw_offset, s.draw_alpha = scale, offset, alpha
    }
    set_draw_state(s, b.clip, scale, offset, alpha)
    pal := b.palette
    radii := b.corner_radii

    if .Draw_Drop_Shadow in b.flags {
        shadow := pad_rect(b.rect, 4)
        shadow.pos.y += 4
        r := radii
        for &x in r do x += 4
        draw_rect_ex(s, shadow, all_colors(s.theme.shadow), r, 0, 10)
    }
    if .Draw_Background in b.flags {
        draw_rect_ex(s, b.rect, all_colors(pal.background), radii)
    }
    if .Draw_Hot_Effects in b.flags && b.hot_t > 0.001 {
        top, bottom := pal.overlay, pal.overlay
        top.a *= b.hot_t
        bottom.a *= b.hot_t * 0.45
        draw_rect_gradient(s, b.rect, top, bottom, radii)
    }
    if .Draw_Active_Effects in b.flags && b.active_t > 0.001 {
        draw_rect_gradient(s, b.rect, {0, 0, 0, 0.32 * b.active_t}, {0, 0, 0, 0.08 * b.active_t}, radii)
    }

    // the box's own content clips to the box when it clips its children
    content_clip := .Clip in b.flags ? intersection(b.clip, b.rect) : b.clip
    set_draw_state(s, content_clip, scale, offset, alpha)
    if .Draw_Text in b.flags && len(b.text) > 0 && s.measure_text != nil {
        text := b.text
        if .Disable_Text_Trunc not_in b.flags {
            text = truncate_text(s, text, b.font_size, b.rect.size.x - 2 * b.text_padding)
        }
        draw_text(s, text, text_position(s, b, text), pal.text, b.font_size)
    }
    if b.custom_draw != nil do b.custom_draw(s, b, b.custom_data)

    // RAD order: the last child is drawn first, so earlier siblings end up on top
    for c := b.last; c != nil; c = c.prev do draw_box(s, c, scale, offset, alpha, hit)

    set_draw_state(s, b.clip, scale, offset, alpha)
    if .Draw_Border in b.flags {
        border := pal.border
        border.rgb += pal.overlay.rgb * pal.overlay.a * 2 * b.hot_t
        draw_rect_ex(s, b.rect, all_colors(border), radii, 1)
    }
    side := pal.border
    if .Draw_Side_Top in b.flags do draw_rect(s, {b.rect.pos, {b.rect.size.x, 1}}, side)
    if .Draw_Side_Bottom in b.flags do draw_rect(s, {{b.rect.pos.x, b.rect.pos.y + b.rect.size.y - 1}, {b.rect.size.x, 1}}, side)
    if .Draw_Side_Left in b.flags do draw_rect(s, {b.rect.pos, {1, b.rect.size.y}}, side)
    if .Draw_Side_Right in b.flags do draw_rect(s, {{b.rect.pos.x + b.rect.size.x - 1, b.rect.pos.y}, {1, b.rect.size.y}}, side)
    if s.focus_visible && b.focus_hot_t > 0.01 && .Keyboard_Clickable in b.flags && .Disable_Focus_Border not_in b.flags {
        focus := pal.accent
        focus.a *= b.focus_hot_t
        draw_rect_ex(s, pad_rect(b.rect, 1), all_colors(focus), radii, 1.5)
    }
    if b.disabled_t > 0.01 {
        // dims the box and everything in it
        veil := s.theme.base.background
        veil.a = 0.5 * b.disabled_t
        draw_rect_ex(s, b.rect, all_colors(veil), radii)
    }
    if s.debug_bounds do draw_rect(s, b.rect, {0.95, 0.45, 0.3, 0.7}, 0, 1)
}
