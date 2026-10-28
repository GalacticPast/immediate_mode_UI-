package ui

import pl "../platform"
import r "../renderer"
import "base:runtime"
import "core:hash"
import "core:mem"
import "core:slice"

WIDGET_FLAG :: enum {
    NONE,
    PRESSABLE,
    HOVERABLE,
    DRAGGABLE,
    RESIZABLE,
    DRAW_TEXT,
    DRAW_RECT,
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
    h_size:                          Size, // horizontal size
    v_size:                          Size, // vertical size
    flags:                           Widget_Flags,
    children_layout_axis:            Axis_Type,
    str:                             string,

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
    flags:                Maybe(Widget_Flags),
    children_layout_axis: Maybe(Axis_Type),
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
    clip:  Rect,
    color: [3]f32,
    str:   string,
    type:  Draw_Type,
}


@(private)
State :: struct {
    allocator:        runtime.Allocator,
    frame_allocator:  runtime.Allocator,
    arena:            mem.Dynamic_Arena,
    tree:             map[u64]^Box,
    curr_parent:      [dynamic]^Box,
    draw_commands:    [dynamic]Draw_Command,
    def_color:        [3]f32,
    curr_build_index: u64,

    // frame specific
    root:             ^Box,
    events:           pl.Event_List,
    // this one gets cached
    mouse_pos:        [2]i32,
    // this one resets every frame
    mouse_btn_press:  pl.Key_Type,
}

@(private)
state: State

init :: proc() {
    mem.dynamic_arena_init(&state.arena)
    state.allocator = mem.dynamic_arena_allocator(&state.arena)
    state.frame_allocator = context.temp_allocator
    state.draw_commands = make([dynamic]Draw_Command, state.allocator)
    state.curr_parent = make([dynamic]^Box, state.allocator)
    state.tree = make(map[u64]^Box, state.allocator)
    state.def_color = {0.216, 0.247, 0.290}
    state.curr_build_index = 0
}
deinit :: proc() {
    delete(state.draw_commands)
    delete(state.curr_parent)
    delete(state.tree)
    mem.dynamic_arena_destroy(&state.arena)
}

@(deferred_out = end_build)
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
            case .MOUSE_PRESS:
                state.mouse_btn_press = e.key
                eat = e
        }
    }


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


    root := create_box("root", h_size, v_size, flags, children_layout_axis, color)
    state.root = root
    root.pos.x = 0
    root.pos.y = 0

    append(&state.curr_parent, state.root)

    return true
}

end_build :: proc(_: bool) {
    box_counter = 0
    state.mouse_btn_press = .NONE
}

@(deferred_out = panel_end)
panel :: proc(title: string, description := Box_Desc{nil, nil, nil, nil, nil}) -> bool {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 1}
    box_flags := description.flags.? or_else {.HOVERABLE, .DRAGGABLE, .DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color

    // definitive that desc is filled
    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    panel := create_box(title, box_h_size, box_v_size, box_flags, box_children_layout_axis, box_color)
    append(&state.curr_parent, panel)

    return true
}

panel_end :: proc(open: bool) {
    pop(&state.curr_parent)
}

box_counter := 0

@(deferred_out = box_end)
box :: proc(description := Box_Desc{nil, nil, nil, nil, nil}) -> bool {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 0}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_CHILDREN_SUM, strictness = 0}
    box_flags := description.flags.? or_else {.NONE}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color

    // definitive that desc is filled
    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    // warn: this is very bad,
    box := create_box("", box_h_size, box_v_size, box_flags, box_children_layout_axis, box_color)

    append(&state.curr_parent, box)
    box_counter += 1
    return true
}

box_end :: proc(open: bool) {
    pop(&state.curr_parent)
}

button :: proc(str: string, description := Box_Desc{nil, nil, nil, nil, nil}) -> bool {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_flags := description.flags.? or_else {.PRESSABLE, .HOVERABLE, .DRAW_TEXT, .DRAW_RECT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color

    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))

    button := create_box(str, box_h_size, box_v_size, box_flags, box_children_layout_axis, box_color)
    check_action(button)

    return button.clicked
}

label :: proc(str: string, description := Box_Desc{nil, nil, nil, nil, nil}) {

    box_h_size := description.h_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_v_size := description.v_size.? or_else {type = .BASED_ON_TEXT, strictness = 1}
    box_flags := description.flags.? or_else {.DRAW_TEXT}
    box_children_layout_axis := description.children_layout_axis.? or_else .VERTICAL
    box_color := description.color.? or_else state.def_color

    assert(box_h_size.type != .BASED_ON_PARENT_PCT || (box_h_size.value >= 0 && box_h_size.value <= 1))
    assert(box_v_size.type != .BASED_ON_PARENT_PCT || (box_v_size.value >= 0 && box_v_size.value <= 1))
    // label
    create_box(str, box_h_size, box_v_size, box_flags, box_children_layout_axis, box_color)
}

mouse_collision :: proc(m_pos: [2]i32, box: Rect) -> bool {
    res :=
        f32(m_pos.x) >= box.pos.x &&
        f32(m_pos.x) < box.pos.x + box.dimen.x &&
        f32(m_pos.y) >= box.pos.y &&
        f32(m_pos.y) < box.pos.y + box.dimen.y

    return res
}

check_action :: proc(elem: ^Box) {
    if mouse_collision(state.mouse_pos, {elem.pos, elem.dimensions}) {
        elem.hovered = true
    }
    if state.mouse_btn_press == .BTN_RIGHT {
        elem.clicked = true
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
}
@(private)
hash_key :: proc(str: string, parent_key := u64(0xcbf29ce484222325)) -> u64 {
    return hash.fnv64a(transmute([]u8)str, parent_key)
}
create_box :: proc(
    title: string,
    h_size: Size,
    v_size: Size,
    flags: Widget_Flags,
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

    node.str = title
    node.h_size = h_size
    node.v_size = v_size
    node.flags = flags
    node.children_layout_axis = children_layout_axis
    node.key = key

    // invalidate the list
    node.prev, node.next, node.first, node.last = nil, nil, nil, nil
    node.parent = imm_parent
    node.clicked = false
    node.hovered = false
    node.color = color
    node.build_index = state.curr_build_index

    // damn the parent changed
    if imm_parent != nil do insert_ll(imm_parent, node)

    //insert/update the hashmap
    if key != 0 {
        state.tree[key] = node
    }

    return node
}


calc_sizes :: proc(node: ^Box) {
    if node == nil do return
    for elem := node; elem != nil; elem = elem.next {
        calc_sizes(elem.first)
        text_size := r.calculate_size(elem.str, 12)
        switch (elem.h_size.type) {
            case .BASED_ON_TEXT:
                elem.dimensions.x = text_size[0] + 5 // 2.5 units in each dir
            case .BASED_ON_CHILDREN_SUM:
                for child := elem.first; child != nil; child = child.next {
                    elem.dimensions.x += child.dimensions.x + OFFSET_X
                }
            case .BASED_ON_PARENT_PCT:
                parent: ^Box = elem.parent
                assert(parent.h_size.type == .FIXED) // this should be fixed
                elem.dimensions.x = parent.h_size.value * elem.h_size.value
            case .FIXED:
                elem.dimensions.x = elem.h_size.value
            case .NONE:
        }
        switch (elem.v_size.type) {
            case .BASED_ON_TEXT:
                elem.dimensions.y = text_size[1] + 5 // 2.5 units in each dir
            case .BASED_ON_CHILDREN_SUM:
                for child := node.first; child != nil; child = child.next {
                    elem.dimensions.y += child.dimensions.y + OFFSET_Y
                }
            case .BASED_ON_PARENT_PCT:
                parent: ^Box = elem.parent
                assert(parent.v_size.type == .FIXED) // this should be fixed
                elem.dimensions.y = parent.v_size.value * elem.v_size.value
            case .FIXED:
                elem.dimensions.y = elem.v_size.value
            case .NONE:

        }
    }
}

OFFSET_X :: 3
OFFSET_Y :: 3

calc_positions :: proc(node: ^Box) {
    if node == nil do return

    parent := node.parent
    pen_pos: [2]f32 = {parent.pos.x + OFFSET_X, parent.pos.y + OFFSET_Y}
    // @warn: we kinda dont clip anything here so
    for elem := node; elem != nil; elem = elem.next {
        elem.pos.x = pen_pos.x
        elem.pos.y = pen_pos.y

        switch (parent.children_layout_axis) {
            case .VERTICAL:
                pen_pos.y += elem.dimensions.y + OFFSET_Y
            case .HORIZONTAL:
                pen_pos.x += elem.dimensions.x + OFFSET_X
            case:
                assert(false, "Children layout not specified.")
        }
        calc_positions(elem.first)
    }
}

pre_order_traversal :: proc(node: ^Box) {
    if node == nil do return
    for elem := node; elem != nil; elem = elem.next {
        color := elem.color
        if elem.hovered {
            color = {1, 1, 0}
        }
        if .DRAW_RECT in elem.flags {
            append(&state.draw_commands, {clip = {elem.pos, elem.dimensions}, color = color, type = .RECTANGLE})
        }
        if .DRAW_TEXT in elem.flags {
            text_pos: [2]f32 = {elem.pos.x + 2, elem.pos.y + 2}
            append(&state.draw_commands, {clip = {text_pos, {}}, type = .TEXT, color = {1, 1, 1}, str = elem.str})
        }
        pre_order_traversal(elem.first)
    }
}

build_draw_commands :: proc() -> []Draw_Command {
    root := state.root
    calc_sizes(root)
    // important so that we only work on the first child index
    calc_positions(root.first)
    // welp
    pre_order_traversal(root)
    return state.draw_commands[:]
}
