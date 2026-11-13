package ui

import r "../renderer"
import "core:fmt"

@(private)
Scroll_Region_Data :: struct {
    value_x: f32,
    min_x:   f32,
    max_x:   f32,
    value_y: f32,
    min_y:   f32,
    max_y:   f32,
}

@(private)
Check_Box_Data :: struct {
    value: ^bool, // @note: passed by the user
}

Checkbox_Padding :: 5
Checkbox_Square :: 10

@(private)
Radio_Box_Data :: struct {
    value:      ^u32,
    identifier: u32,
}

Sliderbox_Padding :: 15

@(private)
Slider_Box_Data :: struct {
    value: ^f32,
    min:   f32,
    max:   f32,
}

@(private)
Collapsable_Box_Data :: struct {
    value: ^bool,
}

@(deferred_out = panel_end)
panel :: proc(title: string, description := Box_Desc{}) -> bool {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 1}
    box_flags := description.flags.? or_else {.HOVERABLE, .DRAGGABLE, .DRAW_RECT, .OVERFLOW_X, .OVERFLOW_Y}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .NONE
    box_pos := description.pos.? or_else {-1, -1}


    // @note: definitive that desc is filled
    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    panel := create_box(
        title,
        box_h_size,
        box_v_size,
        box_pos,
        box_flags,
        text_align,
        box_children_layout_axis,
        box_color,
    )
    append(&state.curr_parent, panel)
    if .FLOATING_X in box_flags && .FLOATING_Y in box_flags {
        make_floating(panel)
    }
    return true
}


panel_end :: proc(_: bool) {
    pop(&state.curr_parent)
}

@(deferred_out = scroll_region_end)
scroll_region :: proc(label: string, description := Box_Desc{}) -> bool {
    //@note parent which encloses all
    box_begin(
        description = Box_Desc {
            h_size = {type = .FIXED, value = 100},
            v_size = {type = .FIXED, value = 100},
            flags = {.CLIP},
        },
    )

    // @note: scroll region
    x_value: f32 = 1.0
    y_value: f32 = 1.0
    scroll_region: ^Box = nil
    box_flags := description.flags.? or_else {.DRAW_RECT, .OVERFLOW_Y, .OVERFLOW_X, .SCROLLABLE_X}

    {
        // @todo: choose better defaults

        if .SCROLLABLE_X in box_flags do x_value -= 0.1
        if .SCROLLABLE_Y in box_flags do y_value -= 0.1

        box_h_size := description.h_size.? or_else {type = .BASED_ON_PARENT_PCT, value = x_value, strictness = 0.5}
        box_v_size := description.v_size.? or_else {type = .BASED_ON_PARENT_PCT, value = y_value, strictness = 0.5}
        box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
        box_color := description.color.? or_else state.def_color
        text_align := description.text_algin_flag.? or_else .CENTER
        box_pos := description.pos.? or_else {-1, -1}

        // @note: definitive that desc is filled
        assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
        assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

        scroll_region = create_box(
            label,
            box_h_size,
            box_v_size,
            box_pos,
            box_flags,
            text_align,
            box_children_layout_axis,
            box_color,
        )
        if scroll_region.custom_data == nil {
            data := new(Scroll_Region_Data, state.allocator)
            data^ = Scroll_Region_Data {
                min_x = 0,
                max_x = 1,
                min_y = 0,
                max_y = 1,
            }
            scroll_region.custom_data = data
        }
    }

    // @note: scroll bar
    {
        if .SCROLLABLE_X in box_flags {
            data := cast(^Scroll_Region_Data)scroll_region.custom_data
            slider(
                fmt.aprintf("%s_hori_bar", label, allocator = state.frame_allocator),
                &data.value_x,
                data.min_x,
                data.max_x,
            )
        }
        if .SCROLLABLE_Y in box_flags {
            box_h_size: Size = {
                type       = .BASED_ON_PARENT_PCT,
                value      = 0.05,
                strictness = 0.5,
            }
            box_v_size: Size = {
                type       = .BASED_ON_PARENT_PCT,
                value      = 1.0,
                strictness = 0.5,
            }
            slider_box_flags := Widget_Flags{.DRAW_CUSTOM, .DRAGGABLE, .HOVERABLE}
            box_children_layout_axis: Axis_Type = .VERTICAL
            box_color: [3]f32 = {1, 0, 1}
            text_align: Text_Align_Flag = .CENTER
            box_pos: [2]f32 = {-1, -1}

            // @note: definitive that desc is filled
            assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
            assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

            bar := create_box(
                fmt.aprintf("%s_hori_bar", label, allocator = state.frame_allocator),
                box_h_size,
                box_v_size,
                box_pos,
                slider_box_flags,
                text_align,
                box_children_layout_axis,
                box_color,
            )
            if bar.custom_data == nil {
                bar_data := new(Slider_Box_Data, state.allocator)
                bar.custom_data = bar_data
                bar.custom_draw = slider_custom_draw
            }
            data := cast(^Scroll_Region_Data)scroll_region.custom_data
            (cast(^Slider_Box_Data)bar.custom_data)^ = {
                value = &data.value_y,
                min   = data.min_y,
                max   = data.max_y,
            }
            check_action(bar)
            if bar.key == state.active_widget_key {
                total_range := data.max_y - data.min_y
                value_change := (f32(state.mouse_dx.x) / box_h_size.value) * total_range
                data.value_y = clamp(value_change + data.value_y, data.min_y, data.max_y)
            }
        }
    }
    append(&state.curr_parent, scroll_region)
    return true
}
scroll_region_end :: proc(_: bool) {
    pop(&state.curr_parent) // the scroll region
    box_end(true)           // the encompassing parent
}

@(deferred_out = collapsable_header_end)
collapsable_header :: proc(title: string, value: ^bool, description := Box_Desc{}) -> bool {
    // @note: parent_which_encloses_all
    box_begin()

    // @note: title
    box_h_size := description.h_size.? or_else {type = .BASED_ON_PARENT_PCT, value = 1, strictness = 0.5}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1} // @note: hmm
    box_flags := description.flags.? or_else {.HOVERABLE, .PRESSABLE, .DRAW_TEXT, .DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .CENTER
    box_pos := description.pos.? or_else {-1, -1}

    // @note: definitive that desc is filled
    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    title_box := create_box(
        title,
        box_h_size,
        box_v_size,
        box_pos,
        box_flags,
        text_align,
        box_children_layout_axis,
        box_color,
    )

    check_action(title_box)

    if title_box.clicked {
        value^ = !value^
    }

    if value^ == true {
        // @note: content
        box_begin(description = Box_Desc{children_layout_axis = .VERTICAL})
    }

    return value^
}

@(deferred_out = dropdown_end)
dropdown :: proc(title: string, value: ^bool, description := Box_Desc{}) -> bool {
    // @note: title
    box_h_size := description.h_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1} // @note: hmm
    box_flags := description.flags.? or_else {.HOVERABLE, .PRESSABLE, .DRAW_TEXT, .DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .CENTER
    box_pos: [2]f32 = description.pos.? or_else {-1, -1}

    // @note: definitive that desc is filled
    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    title_box := create_box(
        title,
        box_h_size,
        box_v_size,
        box_pos,
        box_flags,
        text_align,
        box_children_layout_axis,
        box_color,
    )

    append(&state.curr_parent, title_box)

    check_action(title_box)
    if title_box.clicked {
        value^ = !value^
    }

    if value^ == true {
        // @note: content_window
        box_title := fmt.aprintf("dropdown__%s", title, allocator = state.allocator)
        context_menu(box_title, {title_box.pos.x, title_box.pos.y + title_box.dimensions.y + OFFSET_Y})
    }

    return value^
}

context_menu :: proc(title: string, pref_pos: [2]f32) {
    box_h_size := Size {
        type       = .BASED_ON_CHILDREN_SUM,
        strictness = 0,
    }
    box_v_size := Size {
        type       = .BASED_ON_CHILDREN_SUM,
        strictness = 0,
    }
    box_flags := Widget_Flags{.DRAW_RECT, .FLOATING_X, .FLOATING_Y}
    box_children_layout_axis: Axis_Type = .VERTICAL
    box_color := state.def_color
    box_pos: [2]f32 = pref_pos

    if state.debug do box_flags += {.DRAW_BORDER}


    box := create_box(title, box_h_size, box_v_size, box_pos, box_flags, .NONE, box_children_layout_axis, box_color)
    make_floating(box)
    append(&state.curr_parent, box)
}


button :: proc(label: string, description := Box_Desc{}) -> bool {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_flags := description.flags.? or_else {.PRESSABLE, .HOVERABLE, .DRAW_TEXT, .DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .CENTER
    box_pos: [2]f32 = description.pos.? or_else {-1, -1}

    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    button := create_box(
        label,
        box_h_size,
        box_v_size,
        box_pos,
        box_flags,
        text_align,
        box_children_layout_axis,
        box_color,
    )
    check_action(button)

    return button.clicked
}

slider :: proc(title: string, value: ^f32, min: f32, max: f32) {
    assert(value != nil)
    assert(min != max)
    assert(min < max)
    text_size := r.calculate_text_size(title, state.font_size)

    box_h_size := Size {
        type       = .FIXED,
        value      = text_size.x + 2 * Sliderbox_Padding + 2 * OFFSET_X,
        strictness = 1,
    }
    box_v_size := Size {
        type       = .FIXED,
        value      = text_size.y + 2 * OFFSET_Y,
        strictness = 1,
    }
    box_flags := Widget_Flags{.DRAW_CUSTOM, .DRAGGABLE, .HOVERABLE}
    box_children_layout_axis: Axis_Type = .VERTICAL
    box_color := state.def_color
    text_align: Text_Align_Flag = .CENTER
    box_pos: [2]f32 = {-1, -1}

    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    slider := create_box(
        title,
        box_h_size,
        box_v_size,
        box_pos,
        box_flags,
        text_align,
        box_children_layout_axis,
        box_color,
    )

    if slider.custom_data == nil {
        slider_box_data := new(Slider_Box_Data, state.allocator)
        slider.custom_data = slider_box_data
        slider.custom_draw = slider_custom_draw
    }

    (cast(^Slider_Box_Data)slider.custom_data)^ = {
        value = value,
        min   = min,
        max   = max,
    }
    check_action(slider)
    if slider.key == state.active_widget_key {
        total_range := max - min
        value_change := (f32(state.mouse_dx.x) / box_h_size.value) * total_range
        value^ = clamp(value_change + value^, min, max)
    }
}

checkbox :: proc(title: string, value: ^bool) {
    assert(value != nil)
    checkbox := toggle_box(title)

    if checkbox.custom_data == nil {
        check_box_data := new(Check_Box_Data, state.allocator)
        checkbox.custom_data = check_box_data
        checkbox.custom_draw = checkbox_custom_draw
    }
    (cast(^Check_Box_Data)checkbox.custom_data).value = value

    check_action(checkbox)

    if checkbox.clicked {
        value^ = !value^
    }
}

radio :: proc(title: string, ind: ^u32, identifier: u32) {
    assert(ind != nil)
    radio := toggle_box(title)

    if radio.custom_data == nil {
        radio_box_data := new(Radio_Box_Data, state.allocator)
        radio.custom_data = radio_box_data
    }
    (cast(^Radio_Box_Data)radio.custom_data)^ = {
        value      = ind,
        identifier = identifier,
    }

    radio.custom_draw = radio_custom_draw

    check_action(radio)
    if radio.clicked {
        data: ^Radio_Box_Data = cast(^Radio_Box_Data)radio.custom_data
        data.value^ = identifier
    }
}

label :: proc(title: string, description := Box_Desc{}) {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_flags := description.flags.? or_else {.DRAW_TEXT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .CENTER
    box_pos: [2]f32 = description.pos.? or_else {-1, -1}

    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))
    // @note: title
    create_box(title, box_h_size, box_v_size, box_pos, box_flags, text_align, box_children_layout_axis, box_color)
}

@(deferred_out = box_end)
spacer :: proc() -> bool {
    box_begin(
        description = Box_Desc {
            h_size = {type = .BASED_ON_PARENT_PCT, value = 1},
            v_size = {type = .FIXED, value = 50},
            flags = {.CLIP},
        },
    )
    return true
}

@(private)
collapsable_header_end :: proc(open: bool) {
    if open {
        box_end(open)
    }
    box_end(open)
}
@(private)
dropdown_end :: proc(open: bool) {
    if open {
        box_end(open)
    }
    box_end(open)
}

row :: proc {
    transient_row,
    named_row,
}


@(deferred_out = box_end)
transient_row :: proc() -> bool {
    return box_begin(description = Box_Desc{children_layout_axis = .HORIZONTAL})
}
@(deferred_out = box_end)
named_row :: proc(title: string, description: Box_Desc) -> bool {
    des := description
    des.children_layout_axis = .HORIZONTAL
    return box_begin(title, des)
}

column :: proc {
    transient_column,
    named_column,
}

@(deferred_out = box_end)
transient_column :: proc() -> bool {
    return box_begin(description = Box_Desc{children_layout_axis = .VERTICAL})
}
@(deferred_out = box_end)
named_column :: proc(title: string, description: Box_Desc) -> bool {
    des := description
    des.children_layout_axis = .VERTICAL
    return box_begin(title, des)
}

@(deferred_out = box_end)
box :: proc(description := Box_Desc{}) -> bool {
    return box_begin(description = description)
}
box_end :: proc(_: bool) {
    pop(&state.curr_parent)
}

@(private)
toggle_box :: proc(title: string) -> ^Box {
    text_size := r.calculate_text_size(title, state.font_size)
    box_h_size := Size {
        type       = .FIXED,
        value      = text_size.x + Checkbox_Padding + Checkbox_Square + 2 * OFFSET_X,
        strictness = 1,
    }
    box_v_size := Size {
        type       = .FIXED,
        value      = max(text_size.y, Checkbox_Square) + 2 * OFFSET_Y,
        strictness = 1,
    }
    box_flags := Widget_Flags{.DRAW_CUSTOM, .PRESSABLE}
    box_children_layout_axis: Axis_Type = .VERTICAL
    box_color := state.def_color
    text_align: Text_Align_Flag = .CENTER
    box_pos: [2]f32 = {-1, -1}

    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    toggle_box := create_box(
        title,
        box_h_size,
        box_v_size,
        box_pos,
        box_flags,
        text_align,
        box_children_layout_axis,
        box_color,
    )

    return toggle_box
}
@(private)
normalize_f32 :: proc(value, min, max: f32) -> f32 {
    return (value - min) / (max - min)
}

@(private)
collapsable_custom_draw :: proc(elem: ^Box, value: rawptr) {
    data := cast(^Collapsable_Box_Data)value
    if data.value^ == true {
    }
    r_color := [3]f32{1, 0, 0}
    if elem.hovered {
        r_color = {1, 1, 0}
    }
    text_size := r.calculate_text_size(elem.title, state.font_size)
    append(
        &state.draw_commands,
        {rect = {elem.pos, {elem.dimensions.x, text_size.y + 2 * OFFSET_Y}}, color = r_color, type = .RECTANGLE},
    )
    t_pos := text_align(elem)
    append(&state.draw_commands, {rect = {t_pos, {}}, type = .TEXT, color = {1, 1, 1}, title = elem.title})
}

@(private)
slider_custom_draw :: proc(elem: ^Box, value: rawptr) {
    data := cast(^Slider_Box_Data)value

    append(&state.draw_commands, {rect = {elem.pos, elem.dimensions}, color = {0.2, 0.5, 0}, type = .RECTANGLE})
    normalized_val := normalize_f32(data.value^, data.min, data.max)
    append(
        &state.draw_commands,
        {
            rect = {elem.pos, {elem.dimensions.x * normalized_val, elem.dimensions.y}},
            color = {1, 0, 0},
            type = .RECTANGLE,
        },
    )

    // @note: find the center first
    title := fmt.aprintf("%s %.2f", elem.title, data.value^, allocator = state.frame_allocator)
    // @note: should I do this ? I think this will kind of fuck it up
    temp := elem.title
    elem.title = title
    t_pos := text_align(elem)
    append(&state.draw_commands, {rect = {t_pos, {}}, type = .TEXT, color = {1, 1, 1}, title = elem.title})
    elem.title = temp
}

@(private)
radio_custom_draw :: proc(elem: ^Box, value: rawptr) {
    data := cast(^Radio_Box_Data)value

    pos := [2]f32{elem.pos.x + OFFSET_X, elem.pos.y + OFFSET_Y}
    dimensions := [2]f32{Checkbox_Square, Checkbox_Square}
    append(&state.draw_commands, {rect = {pos, dimensions}, color = {1, 1, 1}, type = .RECTANGLE})
    append(&state.draw_commands, {rect = {pos.xy + 1, dimensions.xy - 2}, color = state.def_color, type = .RECTANGLE})

    // @note: if the clicked value's id matches the identifier
    if data.value^ == data.identifier {
        s_r_pos := pos.xy + 1
        s_r_dimensions := [2]f32{Checkbox_Square - 2, Checkbox_Square - 2}
        append(&state.draw_commands, {rect = {s_r_pos, s_r_dimensions}, color = {1, 0, 0}, type = .RECTANGLE})
    }

    t_pos := text_align(elem)
    t_pos.x += Checkbox_Padding
    append(&state.draw_commands, {rect = {t_pos, {}}, type = .TEXT, color = {1, 1, 1}, title = elem.title})
}

@(private)
checkbox_custom_draw :: proc(elem: ^Box, value: rawptr) {
    data := cast(^Check_Box_Data)value
    // @note: border
    // @note: append(&state.draw_commands, {rect = {elem.pos - 1, elem.dimensions + 2}, color = {1, 0, 0}, type = .RECTANGLE})
    // @note: append(&state.draw_commands, {rect = {elem.pos, elem.dimensions}, color = state.def_color, type = .RECTANGLE})
    // @note: checkbox_square pos
    pos := [2]f32{elem.pos.x + OFFSET_X, elem.pos.y + OFFSET_Y}
    dimensions := [2]f32{Checkbox_Square, Checkbox_Square}
    append(&state.draw_commands, {rect = {pos, dimensions}, color = {1, 1, 1}, type = .RECTANGLE})
    append(&state.draw_commands, {rect = {pos.xy + 1, dimensions.xy - 2}, color = state.def_color, type = .RECTANGLE})

    // @note: if its clicked then
    if data.value^ == true {
        s_r_pos := pos.xy + 1
        s_r_dimensions := [2]f32{Checkbox_Square - 2, Checkbox_Square - 2}
        append(&state.draw_commands, {rect = {s_r_pos, s_r_dimensions}, color = {1, 0, 0}, type = .RECTANGLE})
    }

    t_pos := text_align(elem)
    t_pos.x += Checkbox_Padding
    append(&state.draw_commands, {rect = {t_pos, {}}, type = .TEXT, color = {1, 1, 1}, title = elem.title})
}

@(private)
box_begin :: proc(title: string = {}, description := Box_Desc{}) -> bool {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 0}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 0}
    box_flags := description.flags.? or_else {.DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    box_pos := description.pos.? or_else {-1, -1}

    if state.debug do box_flags += {.DRAW_BORDER}

    // @note: definitive that desc is filled
    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    box := create_box(title, box_h_size, box_v_size, box_pos, box_flags, .NONE, box_children_layout_axis, box_color)

    append(&state.curr_parent, box)
    return true
}
