package ui

import "core:fmt"

begin_container :: proc(s: ^State, name: string, axis: Axis, width, height: Size,
                        padding: Vec2 = {}, gap: f32 = 8, flags: Flags = {}) -> ^Box {
    b := box(s, name, flags)
    b.style.axis = axis
    b.style.width, b.style.height = width, height
    b.style.padding, b.style.gap = padding, gap
    push_parent(s, b)
    return b
}
end_container :: proc(s: ^State) { pop_parent(s) }
label :: proc(s: ^State, text: string) -> ^Box {
    b := box(s, "", {.Text})
    set_text(s, b, text)
    b.style.height = text_size()
    return b
}
button :: proc(s: ^State, name: string, disabled: bool = false) -> Signal {
    flags: Flags = {.Text, .Background, .Border, .Clickable}
    if disabled do flags += {.Disabled}
    b := box(s, name, flags)
    b.style.text_align = .Center
    return b.signal
}

Indicator :: struct { checked: bool, radio: bool }
indicator_draw :: proc(s: ^State, b: ^Box, data: rawptr) {
    v := cast(^Indicator)data
    r := Rect{b.rect.pos + Vec2{8, (b.rect.size.y-14)*0.5}, {14, 14}}
    radius: f32 = v.radio ? 7 : 3
    rect_draw(s, r, b.style.border, b.clip, radius, 1)
    if v.checked {
        r.pos += Vec2{3, 3}
        r.size -= Vec2{6, 6}
        rect_draw(s, r, b.style.accent, b.clip, radius)
    }
}
checkbox :: proc(s: ^State, name: string, value: ^bool) -> Signal {
    b := box(s, name, {.Text, .Clickable})
    if b.signal.clicked do value^ = !value^
    b.text_offset.x = 22
    data := new(Indicator, frame_allocator(s))
    data.checked = value^
    b.custom_data, b.custom_draw = data, indicator_draw
    return b.signal
}
radio :: proc(s: ^State, name: string, choice: ^int, value: int) -> Signal {
    b := box(s, name, {.Text, .Clickable})
    if b.signal.clicked do choice^ = value
    b.text_offset.x = 22
    data := new(Indicator, frame_allocator(s))
    data.checked, data.radio = choice^ == value, true
    b.custom_data, b.custom_draw = data, indicator_draw
    return b.signal
}

Slider_Draw :: struct { fraction: f32 }
slider_draw :: proc(s: ^State, b: ^Box, data: rawptr) {
    v := cast(^Slider_Draw)data
    track := Rect{b.rect.pos + Vec2{2, 2}, b.rect.size - Vec2{4, 4}}
    track.size.x *= v.fraction
    color := b.style.accent*0.42
    rect_draw(s, track, color, b.clip, max(0, b.style.radius-1))
    handle := Rect{b.rect.pos + Vec2{4+max(0, b.rect.size.x-10)*v.fraction, b.rect.size.y-6}, {3, 3}}
    rect_draw(s, handle, b.style.accent, b.clip, 1)
}
slider :: proc(s: ^State, name: string, value: ^f32, minimum, maximum: f32) -> Signal {
    assert(maximum > minimum)
    b := box(s, name, {.Text, .Background, .Border, .Clickable})
    sig := b.signal
    if sig.pressed || sig.dragging || sig.released {
        width := max(1, b.rect.size.x-12)
        t := clamp((sig.drag_pos.x-b.rect.pos.x-6)/width, 0, 1)
        value^ = minimum + t*(maximum-minimum)
    }
    value^ += f32(sig.step)*(maximum-minimum)*0.01
    if sig.home do value^ = minimum
    if sig.end do value^ = maximum
    value^ = clamp(value^, minimum, maximum)
    set_text(s, b, fmt.tprintf("%s   %.2f", display_string(name), value^))
    data := new(Slider_Draw, frame_allocator(s))
    data.fraction = (value^-minimum)/(maximum-minimum)
    b.custom_data, b.custom_draw = data, slider_draw
    return sig
}

// The caller owns expansion state. Begin a container for children when this returns true.
tree_header :: proc(s: ^State, name: string, expanded: ^bool) -> bool {
    b := box(s, name, {.Text, .Clickable, .Background})
    if b.signal.clicked do expanded^ = !expanded^
    set_text(s, b, fmt.tprintf("%s  %s", expanded^ ? "-" : "+", display_string(name)))
    return expanded^
}

color_preview :: proc(s: ^State, name: string, color: Color, width, height: Size) -> ^Box {
    b := box(s, name, {.Background, .Border})
    b.style.background = color
    b.style.width, b.style.height = width, height
    return b
}
