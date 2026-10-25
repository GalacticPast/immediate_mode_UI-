package ui

import "base:runtime"
import "core:mem"
import "core:slice"

Action_Type :: enum {
    NONE,
    PRESSABLE,
    HOVERABLE,
    DRAGGABLE,
    RESIZABLE,
}

Action_Types :: bit_set[Action_Type;u32]

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
    value:      f32,
    strictness: f32, // 1 means it will never shrink and 0 means it will shrink fully
}

Box :: struct {
    // per build
    // first/last -> children
    prev, next, parent, first, last: ^Box,
    h_size:                          Size, // horizontal size
    v_size:                          Size, // vertical size
    action_type:                     Action_Types,
    children_layout_axis:            Axis_Type,

    //after build
    pos:                             [2]f32,
    dimensions:                      [2]f32,
}

Box_Desc :: struct {
    h_size:               Size,
    v_size:               Size,
    action_type:          Action_Types,
    children_layout_axis: Axis_Type,
}

@(private)
State :: struct {
    root:               ^Box,
    ind:                i32,
    arenas:             [2]mem.Dynamic_Arena, // double buffered

    // frame specific
    curr_parent:        [dynamic]^Box,
    ui_frame_allocator: runtime.Allocator,
}

@(private)
state: State

init :: proc() {
    mem.dynamic_arena_init(&state.arenas[0])
    mem.dynamic_arena_init(&state.arenas[1])
}

@(deferred_out = end_build)
build :: proc() {
    state.ui_frame_allocator = mem.dynamic_arena_allocator(&state.arenas[state.ind])

    allocator := state.ui_frame_allocator
    state.curr_parent = make([dynamic]^Box, allocator)
}

end_build :: proc() {
    state.ind = (state.ind + 1) % 2 // 2 because its double buffered
    delete(state.curr_parent)
    mem.dynamic_arena_reset(&state.arenas[state.ind]) // reset the current arena
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


create_box :: proc(
    title: string,
    description := Box_Desc {
        h_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        v_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        action_type = {.HOVERABLE, .DRAGGABLE},
        children_layout_axis = .VERTICAL,
    },
) -> ^Box {

    allocator := state.ui_frame_allocator
    node := new(Box, allocator)

    node.h_size = description.h_size
    node.v_size = description.v_size
    node.action_type = description.action_type
    node.children_layout_axis = description.children_layout_axis

    if len(state.curr_parent) > 0 {
        node.parent = slice.last(state.curr_parent[:])

    }


    return node
}

@(deferred_out = panel_end)
panel :: proc(
    title: string,
    description := Box_Desc {
        h_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        v_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        action_type = {.HOVERABLE, .DRAGGABLE},
        children_layout_axis = .VERTICAL,
    },
) -> bool {

    panel := create_box(title, description)
    append(&state.curr_parent, panel)

    return false
}

panel_end :: proc(open: bool) {     // if the panel is clicked or focused
    if open {
        pop(&state.curr_parent)
    }
}
