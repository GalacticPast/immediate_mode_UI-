package ui

// Colors for one kind of surface. Widgets pick a palette from the theme; the palette stack
// overrides it for a scope, like RAD's palette stack.
Palette :: struct {
    background: Color,
    text:       Color,
    text_weak:  Color,
    border:     Color,
    overlay:    Color, // hot/active highlight drawn over the background
    accent:     Color, // slider fills, checks, focus border
    cursor:     Color, // text caret
    selection:  Color, // selected text
}

Theme :: struct {
    base:          Palette, // panels and plain text
    button:        Palette,
    input:         Palette, // text fields, slider tracks
    floating:      Palette, // windows, context menus
    title_bar:     Palette,
    menu_bar:      Palette,
    tooltip:       Palette,
    scroll_bar:    Palette,
    shadow:        Color,
    font_size:     f32,
    row_height:    f32,
    corner_radius: f32,
}

rgb :: proc(hex: u32, alpha: f32 = 1) -> Color {
    return {f32((hex >> 16) & 0xff) / 255, f32((hex >> 8) & 0xff) / 255, f32(hex & 0xff) / 255, alpha}
}

default_theme :: proc() -> Theme {
    base := Palette {
        background = rgb(0x1f2227),
        text       = rgb(0xdfe3e9),
        text_weak  = rgb(0x8a929e),
        border     = rgb(0x363b43),
        overlay    = rgb(0xffffff, 0.09),
        accent     = rgb(0x4d8fe0),
        cursor     = rgb(0x8fd0ff),
        selection  = rgb(0x3f6fb0, 0.55),
    }
    button := base
    button.background = rgb(0x2c3138)
    button.border = rgb(0x3d434c)
    input := base
    input.background = rgb(0x17191d)
    floating := base
    floating.background = rgb(0x262a30)
    floating.border = rgb(0x444b55)
    title_bar := floating
    title_bar.background = rgb(0x2e333b)
    menu_bar := base
    menu_bar.background = rgb(0x191b1f)
    tooltip := base
    tooltip.background = rgb(0x121417)
    tooltip.border = rgb(0x3a4049)
    scroll_bar := base
    scroll_bar.background = rgb(0x16181b)
    scroll_bar.border = rgb(0x4a515c)
    return {
        base = base,
        button = button,
        input = input,
        floating = floating,
        title_bar = title_bar,
        menu_bar = menu_bar,
        tooltip = tooltip,
        scroll_bar = scroll_bar,
        shadow = {0, 0, 0, 0.55},
        font_size = 14,
        row_height = 26,
        corner_radius = 4,
    }
}

light_theme :: proc() -> Theme {
    base := Palette {
        background = rgb(0xf3f5f8),
        text       = rgb(0x1d232b),
        text_weak  = rgb(0x67717e),
        border     = rgb(0xcbd2dc),
        overlay    = rgb(0x000000, 0.06),
        accent     = rgb(0x2f6fc4),
        cursor     = rgb(0x1d5fbf),
        selection  = rgb(0x2f6fc4, 0.28),
    }
    button := base
    button.background = rgb(0xffffff)
    button.border = rgb(0xc4ccd7)
    input := base
    input.background = rgb(0xffffff)
    floating := base
    floating.background = rgb(0xfbfcfd)
    floating.border = rgb(0xbfc7d2)
    title_bar := floating
    title_bar.background = rgb(0xe7ebf0)
    menu_bar := base
    menu_bar.background = rgb(0xe8ecf1)
    tooltip := base
    tooltip.background = rgb(0x2a3038)
    tooltip.text = rgb(0xf0f2f5)
    tooltip.text_weak = rgb(0xb4bcc7)
    tooltip.border = rgb(0x2a3038)
    scroll_bar := base
    scroll_bar.background = rgb(0xe4e8ed)
    scroll_bar.border = rgb(0xb3bbc6)
    return {
        base = base,
        button = button,
        input = input,
        floating = floating,
        title_bar = title_bar,
        menu_bar = menu_bar,
        tooltip = tooltip,
        scroll_bar = scroll_bar,
        shadow = {0, 0, 0, 0.2},
        font_size = 14,
        row_height = 26,
        corner_radius = 4,
    }
}
