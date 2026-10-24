package ui

rect_draw :: proc(s: ^State, rect: Rect, color: Color, clip: Rect, radius: f32 = 0, border: f32 = 0) {
    if rect.size.x <= 0 || rect.size.y <= 0 || clip.size.x <= 0 || clip.size.y <= 0 do return
    append(&s.commands, Draw_Command{clip, Rect_Draw{rect, color, radius, border}})
}

build_draw_commands :: proc(s: ^State) {
    for b in s.order {
        if b.clip.size.x <= 0 || b.clip.size.y <= 0 do continue
        bg := b.style.background
        if .Clickable in b.flags {
            bg += Color{0.045, 0.055, 0.065}*b.hot_t
            bg += Color{0.035, 0.045, 0.055}*b.active_t
        }
        if .Disabled in b.flags do bg *= 0.65
        if .Background in b.flags do rect_draw(s, b.rect, bg, b.clip, b.style.radius)
        if b.custom_draw != nil do b.custom_draw(s, b, b.custom_data)
        if .Text in b.flags && len(b.text) > 0 {
            dim := s.measure_text(b.text, b.style.font_size)
            pos := b.rect.pos + b.style.padding + b.text_offset
            pos.y = b.rect.pos.y + max(b.style.padding.y, (b.rect.size.y-dim.y)*0.5) + b.text_offset.y
            switch b.style.text_align {
            case .Left:
            case .Center: pos.x = b.rect.pos.x + (b.rect.size.x-dim.x)*0.5 + b.text_offset.x
            case .Right: pos.x = b.rect.pos.x + b.rect.size.x-dim.x-b.style.padding.x + b.text_offset.x
            }
            color := b.style.text
            if .Disabled in b.flags do color *= 0.5
            append(&s.commands, Draw_Command{b.clip, Text_Draw{b.text, pos, color, b.style.font_size}})
        }
        if .Border in b.flags do rect_draw(s, b.rect, b.style.border, b.clip, b.style.radius, 1)
        if b.key != 0 && b.key == s.focus do rect_draw(s, b.rect, b.style.accent, b.clip, b.style.radius, 2)
        if s.debug_bounds do rect_draw(s, b.rect, {0.9, 0.45, 0.3}, b.clip, 0, 1)
        if .Scroll in b.flags {
            visible := max(0, b.rect.size.y-2*b.style.padding.y)
            if b.content_size.y > visible && visible > 0 {
                h := max(16, visible*visible/b.content_size.y)
                y := b.rect.pos.y+b.style.padding.y+(visible-h)*b.scroll_y/(b.content_size.y-visible)
                rect_draw(s, {{b.rect.pos.x+b.rect.size.x-5, y}, {3, h}}, b.style.border, b.clip, 1)
            }
        }
    }
}
