package ui

import pl "../platform"
import r "../renderer"
import "base:runtime"
import "core:fmt"
import "core:hash"
import "core:mem"
import "core:slice"


Text_Align_Flag :: enum {
    NONE,
    CENTER,
    LEFT,
    RIGHT,
}

WIDGET_FLAG :: enum {
    NONE,
    // actions
    PRESSABLE,
    HOVERABLE,
    DRAGGABLE,
    RESIZABLE,
    GRABBABLE,

    // types
    CLIP,
    FLOATING_X,
    FLOATING_Y,

    // draws
    DRAW_TEXT,
    DRAW_RECT,
    DRAW_BORDER,
    DRAW_CUSTOM,
}

Widget_Flags :: bit_set[WIDGET_FLAG;u32]

Size_Type :: enum {
    NONE = 0,
    FIXED,
    BASED_ON_TEXT,
    BASED_ON_CHILDREN_SUM,
    BASED_ON_PARENT_PCT, // percentage of parent given that the parent has FIXED SIZE TYPE
}
// it will default to vertical
Axis_Type :: enum {
    VERTICAL,
    HORIZONTAL,
}

Size :: struct {
    type:       Size_Type,
    value:      f32, // if its parent percentage then the value should be between [0,1] inclusive
    strictness: f32, // 1 means it will never shrink and 0 means it will shrink fully
}

Box :: struct {
    // this should persist between draws
    key:                             u64,
    build_index:                     u64, // up to which version did we build it

    // per build
    // first/last -> children
    prev, next, parent, first, last: ^Box,
    child_count:                     u32,
    h_size:                          Size, // horizontal size
    v_size:                          Size, // vertical size
    flags:                           Widget_Flags,
    text_align_flag:                 Text_Align_Flag,
    children_layout_axis:            Axis_Type,
    title:                           string,

    // atached every_frame
    custom_draw:                     proc(elem: ^Box, value: rawptr),
    custom_data:                     rawptr,

    //signals
    hovered:                         bool,
    clicked:                         bool,


    //after build
    pos:                             [2]f32,
    dimensions:                      [2]f32,
    color:                           [3]f32,
}

Box_Desc :: struct {
    h_size:               Maybe(Size),
    v_size:               Maybe(Size),
    pos:                  Maybe([2]f32), // to set the position you have to set FLOATING_X/FLOATING_Y in flags
    flags:                Maybe(Widget_Flags),
    children_layout_axis: Maybe(Axis_Type),
    text_algin_flag:      Maybe(Text_Align_Flag),
    color:                Maybe([3]f32),
}

Draw_Type :: enum {
    NONE,
    RECTANGLE,
    TEXT,
}

Rect :: struct {
    pos, dimen: [2]f32,
}

Draw_Command :: struct {
    rect:  Rect,
    clip:  Rect,
    color: [3]f32,
    title: string,
    type:  Draw_Type,
}


@(private)
State :: struct {
    arena:                mem.Dynamic_Arena,
    allocator:            runtime.Allocator, // from arena
    frame_allocator:      runtime.Allocator,
    tree:                 map[u64]^Box,
    curr_parent:          [dynamic]^Box,
    draw_commands:        [dynamic]Draw_Command,
    def_color:            [3]f32,
    curr_build_index:     u64,
    font_size:            f32,
    debug:                bool,

    // frame specific
    root:                 ^Box,
    events:               pl.Event_List,

    // this one gets cached
    prev_frame_mouse_pos: [2]i32, // hmm is this guaranteed though ? what if we were sleeping and just woke up
    mouse_pos:            [2]i32,
    mouse_dx:             [2]i32,

    // transient
    active_widget_key:    u64,
    hot_widget_key:       u64,
    inside_floating:      bool,        // @temp:
    mouse_btn_press:      pl.Key_Type, // this is short lived
    mouse_btn_held:       pl.Key_Type,
}

@(private)
Check_Box_Data :: struct {
    value: ^bool, // passed by the user
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

@(private)
state: State

init :: proc() {
    mem.dynamic_arena_init(&state.arena)
    state.font_size = 12
    state.allocator = mem.dynamic_arena_allocator(&state.arena)
    state.frame_allocator = context.temp_allocator
    state.draw_commands = make([dynamic]Draw_Command, state.allocator)
    state.curr_parent = make([dynamic]^Box, state.allocator)
    state.tree = make(map[u64]^Box, state.allocator)
    state.def_color = {0.216, 0.247, 0.290}
    state.curr_build_index = 0

    state.debug = false
}

deinit :: proc() {
    delete(state.draw_commands)
    delete(state.curr_parent)
    delete(state.tree)
    mem.dynamic_arena_destroy(&state.arena)
}

@(deferred_out = build_end)
build :: proc(events: pl.Event_List) -> bool {
    state.curr_build_index += 1

    clear(&state.draw_commands) // clear it
    clear(&state.curr_parent)

    state.events = events

    eat: ^pl.Event
    // warn: even if a widget didnt get clicked I still eat the event
    // could be a issue
    for e := state.events.head; e != nil; e = e.next {
        if eat != nil {
            pl.eat_event(&state.events, eat)
            eat = nil
        }
        #partial switch (e.type) {
            case .MOUSE_MOVE:
                state.mouse_pos = e.pos
                eat = e
            case .MOUSE_BTN_PRESSED:
                state.mouse_btn_press = e.key
                state.mouse_btn_held = e.key
                eat = e
            case .MOUSE_BTN_RELEASED:
                state.mouse_btn_press = .NONE
                state.mouse_btn_held = .NONE
                eat = e
            case .KEY_PRESS:
                {
                    if e.key == .D {
                        state.debug = !state.debug
                        eat = e
                    }
                    if e.key == .I {
                        state.font_size += 1
                    }
                    if e.key == .U {
                        state.font_size -= 1
                        state.font_size = max(6, state.font_size)
                    }
                }
        }
    }
    if eat != nil {
        pl.eat_event(&state.events, eat)
        eat = nil
    }

    state.mouse_dx = state.mouse_pos - state.prev_frame_mouse_pos

    p_w, p_h := pl.get_window_size()
    h_size := Size {
        type  = .FIXED,
        value = f32(p_w),
    }
    v_size := Size {
        type  = .FIXED,
        value = f32(p_h),
    }
    flags := Widget_Flags{.NONE}
    children_layout_axis: Axis_Type = .HORIZONTAL
    color := [3]f32{1, 1, 1}


    root := create_box("root", h_size, v_size, {-1, -1}, flags, .NONE, children_layout_axis, color)
    state.root = root
    root.pos.x = 0
    root.pos.y = 0

    append(&state.curr_parent, state.root)
    pl.set_cursor_icon(.DEFAULT)
    return true
}

build_end :: proc(_: bool) {
    state.hot_widget_key = 0
    state.mouse_btn_press = .NONE
    state.prev_frame_mouse_pos = state.mouse_pos
}

@(deferred_out = panel_end)
panel :: proc(title: string, description := Box_Desc{}) -> bool {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 1}
    box_flags := description.flags.? or_else {.HOVERABLE, .DRAGGABLE, .DRAW_RECT, .CLIP}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .NONE
    box_pos := description.pos.? or_else {-1, -1}


    // definitive that desc is filled
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

@(deferred_out = collapsable_header_end)
collapsable_header :: proc(title: string, value: ^bool, description := Box_Desc{}) -> bool {
    // parent_which_encloses_all
    box_begin()

    // title
    box_h_size := description.h_size.? or_else {type = .BASED_ON_PARENT_PCT, value = 1, strictness = 0.5}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1} // hmm
    box_flags := description.flags.? or_else {.HOVERABLE, .PRESSABLE, .DRAW_TEXT, .DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .CENTER
    box_pos := description.pos.? or_else {-1, -1}

    // definitive that desc is filled
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
        // content
        box_begin(description = Box_Desc{children_layout_axis = .VERTICAL})
    }

    return value^
}

@(deferred_out = dropdown_end)
dropdown :: proc(title: string, value: ^bool, description := Box_Desc{}) -> bool {
    // title
    box_h_size := description.h_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1} // hmm
    box_flags := description.flags.? or_else {.HOVERABLE, .PRESSABLE, .DRAW_TEXT, .DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color
    text_align := description.text_algin_flag.? or_else .CENTER
    box_pos: [2]f32 = description.pos.? or_else {-1, -1}

    // definitive that desc is filled
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
        // content_window
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
    // title
    create_box(title, box_h_size, box_v_size, box_pos, box_flags, text_align, box_children_layout_axis, box_color)
}

build_draw_commands :: proc() -> []Draw_Command {
    root := state.root
    calc_size_independent(root)         // hmmm
    calc_size_upwards_dependent(root)   // hmmm
    calc_size_downwards_dependent(root) // hmmm
    //@todo: missing shrinking
    calc_final_sizes(root)

    // important so that we only work on the first child index
    calc_positions(root.first)
    // welp
    pre_order_traversal(root, {root.pos, root.dimensions})
    return state.draw_commands[:]
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
make_floating :: proc(box: ^Box) {
    del_ll(box.parent, box)
    box.prev, box.next = nil, nil
    box.parent = state.root
    insert_ll(state.root, box)
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
text_align :: proc(elem: ^Box) -> [2]f32 {
    // @perf: cache the text_size
    text_size := r.calculate_text_size(elem.title, state.font_size)
    // hmmm
    pos: [2]f32 = {}
    switch (elem.text_align_flag) {
        case .LEFT:
            pos = {elem.pos.x + OFFSET_X, elem.pos.y + OFFSET_Y}
        case .CENTER:
            text_center_p_x := elem.pos.x + (text_size.x / 2)
            box_center_p_x := elem.pos.x + (elem.dimensions.x / 2)
            pos = {elem.pos.x + abs(text_center_p_x - box_center_p_x), elem.pos.y + OFFSET_Y}
        case .RIGHT:
            pos = {elem.pos.x + elem.dimensions.x - text_size.x - OFFSET_X, elem.pos.y + OFFSET_Y}
        case .NONE:
    }

    return pos
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

    // find the center first
    title := fmt.aprintf("%s %.2f", elem.title, data.value^, allocator = state.frame_allocator)
    // should I do this ? I think this will kind of fuck it up
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

    // if the clicked value's id matches the identifier
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
    //border
    // append(&state.draw_commands, {rect = {elem.pos - 1, elem.dimensions + 2}, color = {1, 0, 0}, type = .RECTANGLE})
    // append(&state.draw_commands, {rect = {elem.pos, elem.dimensions}, color = state.def_color, type = .RECTANGLE})
    // checkbox_square pos
    pos := [2]f32{elem.pos.x + OFFSET_X, elem.pos.y + OFFSET_Y}
    dimensions := [2]f32{Checkbox_Square, Checkbox_Square}
    append(&state.draw_commands, {rect = {pos, dimensions}, color = {1, 1, 1}, type = .RECTANGLE})
    append(&state.draw_commands, {rect = {pos.xy + 1, dimensions.xy - 2}, color = state.def_color, type = .RECTANGLE})

    // if its clicked then
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

    // definitive that desc is filled
    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    box := create_box(title, box_h_size, box_v_size, box_pos, box_flags, .NONE, box_children_layout_axis, box_color)

    append(&state.curr_parent, box)
    return true
}

@(private)
mouse_collision :: proc(m_pos: [2]i32, box: Rect) -> bool {
    res :=
        f32(m_pos.x) >= box.pos.x &&
        f32(m_pos.x) < box.pos.x + box.dimen.x &&
        f32(m_pos.y) >= box.pos.y &&
        f32(m_pos.y) < box.pos.y + box.dimen.y

    return res
}

box_clip :: proc(box: ^Box) -> [2]f32 {

    dimen := box.dimensions

    for parent := box.parent; parent != nil; parent = parent.parent {
        if .CLIP in parent.flags {
            // can never be placed on the left of the parent
            if box.pos.x < parent.pos.x + parent.dimensions.x &&
               parent.pos.x + parent.dimensions.x < box.pos.x + dimen.x {
                dimen.x = max(0, dimen.x - (box.pos.x + dimen.x - parent.pos.x - parent.dimensions.x))
            } else if box.pos.x >= parent.pos.x + parent.dimensions.x {
                dimen.x = 0
            }
            if box.pos.y < parent.pos.y + parent.dimensions.y &&
               parent.pos.y + parent.dimensions.y < box.pos.y + dimen.y {
                dimen.y = max(0, dimen.y - (box.pos.y + dimen.y - parent.pos.y - parent.dimensions.y))
            } else if box.pos.y >= parent.pos.y + parent.dimensions.y {
                dimen.y = 0
            }
        }
    }
    return dimen
}

@(private)
check_action :: proc(elem: ^Box) {
    // hot
    if state.active_widget_key == 0 && state.hot_widget_key == 0 {     // if there is an interaction going on or a key is already being hovered , skip the following code
        // clip
        clip_rect := box_clip(elem)
        if mouse_collision(state.mouse_pos, {elem.pos, clip_rect}) {
            state.hot_widget_key = elem.key
            elem.hovered = true
            if .PRESSABLE in elem.flags {
                pl.set_cursor_icon(.POINTER)
            } else if .DRAGGABLE in elem.flags {
                pl.set_cursor_icon(.DRAGGING)
            }
        }
        // active and hot
        if state.hot_widget_key == elem.key && state.mouse_btn_press == .BTN_LEFT {
            state.active_widget_key = elem.key
            elem.clicked = true
        }
    }
    // active
    if state.active_widget_key == elem.key {
        if .PRESSABLE in elem.flags {
            pl.set_cursor_icon(.POINTER)
        } else if .DRAGGABLE in elem.flags {
            pl.set_cursor_icon(.DRAGGING)
        }
    }

    // none
    if state.mouse_btn_press == .NONE && state.mouse_btn_held == .NONE {
        state.active_widget_key = 0
    }
}


@(private)
insert_ll :: proc(list: ^Box, node: ^Box) {
    if node == nil do return

    if list.last != nil {
        list.last.next = node
        node.prev = list.last
    }
    if list.first == nil {
        list.first = node
    }
    list.last = node
    list.child_count += 1
}

@(private)
del_ll :: proc(list: ^Box, node: ^Box) {
    if node == nil do return

    if node.next != nil {
        node.next.prev = node.prev
    }
    if node.prev != nil {
        node.prev.next = node.next
    }
    if list.first == node {
        list.first = node.next
    }
    if list.last == node {
        list.last = node.prev
    }
    list.child_count -= 1
}
@(private)
hash_key :: proc(label: string, parent_key := u64(0xcbf29ce484222325)) -> u64 {
    return hash.fnv64a(transmute([]u8)label, parent_key)
}
@(private)
create_box :: proc(
    title: string,
    h_size: Size,
    v_size: Size,
    pref_pos: [2]f32,
    flags: Widget_Flags,
    text_align_flag: Text_Align_Flag,
    children_layout_axis: Axis_Type,
    color: [3]f32,
) -> ^Box {

    key: u64 = 0 // useful for transient boxes that have no state to store between frames
    imm_parent: ^Box = nil
    key_parent: ^Box = nil

    if len(state.curr_parent) > 0 {
        imm_parent = slice.last(state.curr_parent[:])
        key_parent = imm_parent
        // parent might have key == 0
        for key_parent != nil && key_parent.key == 0 {
            key_parent = key_parent.parent
        }
        if key_parent == nil {
            assert(
                false,
                "This is very bad. Couldnt hash Id for this because the all of the parents in its chain are nil",
            )
        }
    }

    if len(title) > 0 {
        if key_parent != nil {
            key = hash_key(title, key_parent.key)
        } else {
            key = hash_key(title)
        }
    }

    node, found := state.tree[key]
    if !found {
        if key == 0 {
            node = new(Box, state.frame_allocator) // for transient boxes
        } else {
            node = new(Box, state.allocator)
        }
    } else {
        assert(
            node.build_index != state.curr_build_index,
            "This box was already touched/created this frame. It means that the ID of the widget matches.",
        )
    }

    node.title = title
    node.h_size = h_size
    node.v_size = v_size
    node.flags = flags
    node.text_align_flag = text_align_flag
    node.children_layout_axis = children_layout_axis
    node.key = key
    node.child_count = 0

    // invalidate the list
    node.prev, node.next, node.first, node.last = nil, nil, nil, nil
    node.parent = imm_parent
    node.clicked = false
    node.hovered = false
    node.color = color
    node.build_index = state.curr_build_index

    // damn this kinda doesnt work if we were to move the floating window but oh well
    if .FLOATING_X in flags {
        node.pos.x = pref_pos.x
    }
    if .FLOATING_Y in flags {
        node.pos.y = pref_pos.y
    }

    // damn the parent changed
    if imm_parent != nil do insert_ll(imm_parent, node)

    //insert/update the hashmap
    if key != 0 {
        state.tree[key] = node
    }

    return node
}

@(private)
calc_size_independent :: proc(node: ^Box) {
    if node == nil do return
    for elem := node; elem != nil; elem = elem.next {
        calc_size_independent(elem.first)
        text_size := r.calculate_text_size(elem.title, state.font_size)
        #partial switch (elem.h_size.type) {
            case .BASED_ON_TEXT:
                elem.dimensions.x = text_size[0] + 5 // 2.5 units in each dir
            case .FIXED:
                elem.dimensions.x = elem.h_size.value
            case .NONE:
        }
        #partial switch (elem.v_size.type) {
            case .BASED_ON_TEXT:
                elem.dimensions.y = text_size[1] + 5 // 2.5 units in each dir
            case .FIXED:
                elem.dimensions.y = elem.v_size.value
            case .NONE:
        }
    }
}

@(private)
calc_size_upwards_dependent :: proc(node: ^Box) {
    if node == nil do return

    for elem := node; elem != nil; elem = elem.next {
        // lol
        if (elem.h_size.type == .BASED_ON_PARENT_PCT) {
            // could be that the dimenions are still 0 because no parent with type fixed was found
            // well root is always fixed so
            for parent := elem.parent; parent != nil; parent = parent.parent {
                if parent.h_size.type == .BASED_ON_CHILDREN_SUM || parent.h_size.type == .NONE {
                    continue
                }
                elem.dimensions.x = parent.dimensions.x * elem.h_size.value
                break
            }
        }
        if (elem.v_size.type == .BASED_ON_PARENT_PCT) {
            // could be tvat the dimenions are still 0 because no parent with type fixed was found
            // well root is always fixed so
            for parent := elem.parent; parent != nil; parent = parent.parent {
                if parent.v_size.type == .BASED_ON_CHILDREN_SUM || parent.v_size.type == .NONE {
                    continue
                }
                elem.dimensions.y = parent.dimensions.y * elem.v_size.value
                break
            }
        }
        calc_size_upwards_dependent(elem.first)
    }
}

@(private)
calc_size_downwards_dependent :: proc(node: ^Box) {
    if node == nil do return

    for elem := node; elem != nil; elem = elem.next {
        calc_size_downwards_dependent(elem.first)
        if elem.h_size.type == .BASED_ON_CHILDREN_SUM {
            switch (elem.children_layout_axis) {
                case .VERTICAL:
                    elem.dimensions.x = 0
                    for child := elem.first; child != nil; child = child.next {
                        if .FLOATING_X not_in child.flags {
                            elem.dimensions.x = max(child.dimensions.x + OFFSET_X * 2, elem.dimensions.x)
                        }
                    }
                case .HORIZONTAL:
                    elem.dimensions.x = OFFSET_X // add the initial offset size
                    for child := elem.first; child != nil; child = child.next {
                        if .FLOATING_X not_in child.flags {
                            elem.dimensions.x += child.dimensions.x + OFFSET_X
                        }
                    }
            }
        }
        if elem.v_size.type == .BASED_ON_CHILDREN_SUM {
            switch (elem.children_layout_axis) {
                case .VERTICAL:
                    elem.dimensions.y = OFFSET_Y
                    for child := elem.first; child != nil; child = child.next {
                        if .FLOATING_Y not_in child.flags {
                            elem.dimensions.y += child.dimensions.y + OFFSET_Y
                        }
                    }
                case .HORIZONTAL:
                    elem.dimensions.y = 0
                    for child := elem.first; child != nil; child = child.next {
                        if .FLOATING_Y not_in child.flags {
                            elem.dimensions.y = max(child.dimensions.y + OFFSET_Y * 2, elem.dimensions.y)
                        }
                    }
            }
        }
    }
}
// this is the pass that will check whether to shrink it or not
// weighted allocation of the overflow
calc_final_sizes :: proc(node: ^Box) {
    if node == nil do return
    for elem := node; elem != nil; elem = elem.next {
        defer (calc_final_sizes(elem.first))
        c_width: f32 = 0
        c_height: f32 = 0
        combined_max_height_shrinkage: f32 = 0
        combined_max_width_shrinkage: f32 = 0
        for child := elem.first; child != nil; child = child.next {
            if .FLOATING_X not_in child.flags {
                c_width += child.dimensions.x + OFFSET_X
                combined_max_width_shrinkage += child.dimensions.x * (1 - child.h_size.strictness)
            }
            if .FLOATING_Y not_in child.flags {
                c_height += child.dimensions.y + OFFSET_Y
                combined_max_height_shrinkage += child.dimensions.y * (1 - child.v_size.strictness)
            }
        }
        if elem.children_layout_axis == .HORIZONTAL {
            overflow_width := max(0, c_width - elem.dimensions.x)
            if overflow_width > 0 && combined_max_width_shrinkage > 0 {
                total_shrinkage := min(overflow_width, combined_max_width_shrinkage)
                for child := elem.first; child != nil; child = child.next {
                    if .FLOATING_X not_in child.flags {
                        child_share :=
                            (child.dimensions.x * (1 - child.h_size.strictness)) / combined_max_width_shrinkage
                        child.dimensions.x -= total_shrinkage * child_share
                    }
                }
            }
            for child := elem.first; child != nil; child = child.next {
                if .FLOATING_Y not_in child.flags {
                    child.dimensions.y = min(elem.dimensions.y, child.dimensions.y)
                }
            }
        } else if elem.children_layout_axis == .VERTICAL {
            overflow_height := max(0, c_height - elem.dimensions.y)
            if overflow_height > 0 && combined_max_height_shrinkage > 0 {
                total_shrinkage := min(overflow_height, combined_max_height_shrinkage)
                for child := elem.first; child != nil; child = child.next {
                    if .FLOATING_Y not_in child.flags {
                        child_share :=
                            (child.dimensions.y * (1 - child.v_size.strictness)) / combined_max_height_shrinkage
                        child.dimensions.y -= total_shrinkage * child_share
                    }
                }
            }
            for child := elem.first; child != nil; child = child.next {
                if .FLOATING_X not_in child.flags {
                    child.dimensions.x = min(elem.dimensions.x, child.dimensions.x)
                }
            }
        }
    }
}

OFFSET_X :: 3
OFFSET_Y :: 3

@(private)
calc_positions :: proc(node: ^Box) {
    if node == nil do return

    parent := node.parent
    pen_pos: [2]f32 = {parent.pos.x, parent.pos.y}

    for elem := node; elem != nil; elem = elem.next {
        if .FLOATING_X not_in elem.flags {
            elem.pos.x = pen_pos.x + OFFSET_X
        }
        if .FLOATING_Y not_in elem.flags {
            elem.pos.y = pen_pos.y + OFFSET_Y
        }

        switch (parent.children_layout_axis) {
            case .VERTICAL:
                if .FLOATING_Y not_in elem.flags {
                    pen_pos.y += elem.dimensions.y // hmm
                }
            case .HORIZONTAL:
                if .FLOATING_X not_in elem.flags {
                    pen_pos.x += elem.dimensions.x // hmm
                }
            case:
                assert(false, "Children layout not specified.")
        }
        calc_positions(elem.first)
    }
    return
}

@(private)
intersect_rect :: proc(a, b: Rect) -> Rect {
    min_pos := [2]f32{max(a.pos.x, b.pos.x), max(a.pos.y, b.pos.y)}
    max_pos := [2]f32{min(a.pos.x + a.dimen.x, b.pos.x + b.dimen.x), min(a.pos.y + a.dimen.y, b.pos.y + b.dimen.y)}
    return {min_pos, {max(0, max_pos.x - min_pos.x), max(0, max_pos.y - min_pos.y)}}
}

@(private)
pre_order_traversal :: proc(node: ^Box, inherited_clip: Rect) {
    if node == nil do return
    for elem := node; elem != nil; elem = elem.next {
        clip := inherited_clip
        if .CLIP in elem.flags {
            clip = intersect_rect(inherited_clip, {elem.pos, elem.dimensions})
        }
        color := elem.color
        if .DRAW_BORDER in elem.flags || state.debug == true {
            append(
                &state.draw_commands,
                {
                    rect = {{elem.pos.x - 1.5, elem.pos.y - 1.5}, elem.dimensions + 2.5},
                    clip = inherited_clip,
                    color = {1, 0, 0},
                    type = .RECTANGLE,
                },
            )
        }
        if elem.hovered {
            color = {1, 1, 0}
        }
        if .DRAW_RECT in elem.flags {
            rect := Rect{elem.pos, elem.dimensions}
            append(&state.draw_commands, {clip = clip, rect = rect, color = color, type = .RECTANGLE})
        }
        if .DRAW_TEXT in elem.flags {
            text_pos := text_align(elem)
            rect := Rect{text_pos, {}}
            append(
                &state.draw_commands,
                Draw_Command{clip = clip, rect = rect, type = .TEXT, color = {1, 1, 1}, title = elem.title},
            )
        }
        if .DRAW_CUSTOM in elem.flags {
            assert(elem.custom_draw != nil, "Set DRAW_CUSTOM but no custom draw proc attached")
            first_command := len(state.draw_commands)
            elem.custom_draw(elem, elem.custom_data)
            for i in first_command ..< len(state.draw_commands) {
                state.draw_commands[i].clip = clip
            }
        }
        pre_order_traversal(elem.first, clip)
    }
}
