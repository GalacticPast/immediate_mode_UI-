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

    // per build
    // first/last -> children
    prev, next, parent, first, last: ^Box,
    h_size:                          Size, // horizontal size
    v_size:                          Size, // vertical size
    flags:                           Widget_Flags,
    children_layout_axis:            Axis_Type,
    str:                             string,

    //after build
    pos:                             [2]f32,
    dimensions:                      [2]f32,
}

Box_Desc :: struct {
    h_size:               Size,
    v_size:               Size,
    flags:                Widget_Flags,
    children_layout_axis: Axis_Type,
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
    clip: Rect,
    str:  string,
    type: Draw_Type,
}


@(private)
State :: struct {
    allocator:     runtime.Allocator,
    arena:         mem.Dynamic_Arena,
    tree:          map[u64]^Box,
    curr_parent:   [dynamic]^Box,
    draw_commands: [dynamic]Draw_Command,

    // frame specific
    root:          ^Box,
    events:        pl.Event_List,
}

@(private)
state: State

init :: proc() {
    mem.dynamic_arena_init(&state.arena)
    state.allocator = mem.dynamic_arena_allocator(&state.arena)
    state.draw_commands = make([dynamic]Draw_Command, state.allocator)
    state.curr_parent = make([dynamic]^Box, state.allocator)
    state.tree = make(map[u64]^Box, state.allocator)
}
deinit :: proc() {
    delete(state.draw_commands)
    delete(state.curr_parent)
    delete(state.tree)
    mem.dynamic_arena_destroy(&state.arena)
}

@(deferred_out = end_build)
build :: proc(events: pl.Event_List) -> bool {
    clear(&state.draw_commands) // clear it
    clear(&state.curr_parent)

    state.events = events

    // todo: root panel
    p_w, p_h := pl.get_window_size()
    description: Box_Desc = {
        h_size = {type = .FIXED, value = f32(p_w)},
        v_size = {type = .FIXED, value = f32(p_h)},
        flags = {},
        children_layout_axis = .HORIZONTAL,
    }

    root := create_box("root", description)
    state.root = root
    root.pos.x = 0
    root.pos.y = 0

    append(&state.curr_parent, state.root)

    return true
}

end_build :: proc(_: bool) {
}

@(deferred_out = panel_end)
panel :: proc(
    title: string,
    description := Box_Desc {
        h_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        v_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        flags = {.HOVERABLE, .DRAGGABLE},
        children_layout_axis = .VERTICAL,
    },
) -> bool {
    assert(
        description.h_size.type != .BASED_ON_PARENT_PCT ||
        (description.h_size.value >= 0 && description.h_size.value <= 1),
    )
    assert(
        description.v_size.type != .BASED_ON_PARENT_PCT ||
        (description.v_size.value >= 0 && description.v_size.value <= 1),
    )
    panel := create_box(title, description)
    append(&state.curr_parent, panel)

    return true
}

panel_end :: proc(open: bool) {     // if the panel is clicked or focused
    pop(&state.curr_parent)
}

button :: proc(
    str: string,
    description := Box_Desc {
        h_size = {type = .BASED_ON_TEXT, strictness = 1},
        v_size = {type = .BASED_ON_TEXT, strictness = 1},
        flags = {.HOVERABLE, .PRESSABLE, .DRAW_TEXT},
    },
) -> bool {

    button := create_box(str, description)
    return check_action(button)
}

mouse_collision :: proc(m_pos: [2]i32, box: Rect) -> bool {
    res :=
        f32(m_pos.x) >= box.pos.x &&
        f32(m_pos.x) < box.pos.x + box.dimen.x &&
        f32(m_pos.y) >= box.pos.y &&
        f32(m_pos.y) < box.pos.y + box.dimen.y

    return res
}

check_action :: proc(elem: ^Box) -> bool {
    for e := state.events.head; e != nil; e = e.next {
        if e.type == .MOUSE_MOVE {
            if mouse_collision(e.pos, {elem.pos, elem.dimensions}) {
                pl.eat_event(&state.events, e)
                return true
            }
        }
    }
    return false
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
    description := Box_Desc {
        h_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        v_size = {type = .BASED_ON_CHILDREN_SUM, strictness = 1},
        flags = {.HOVERABLE, .DRAGGABLE},
        children_layout_axis = .VERTICAL,
    },
) -> ^Box {

    key: u64
    parent: ^Box = nil
    if len(state.curr_parent) > 0 {
        parent = slice.last(state.curr_parent[:])
        key = hash_key(title, parent.key)
    } else {
        key = hash_key(title)
    }

    node, found := state.tree[key]

    if !found {
        node = new(Box, state.allocator)
    }

    node.str = title
    node.h_size = description.h_size
    node.v_size = description.v_size
    node.flags = description.flags
    node.children_layout_axis = description.children_layout_axis
    node.key = key
    // invalidate the list
    node.prev, node.next, node.first, node.last = nil, nil, nil, nil
    node.parent = parent
    if parent != nil do insert_ll(parent, node)

    //insert/update the hashmap
    state.tree[key] = node

    return node
}


calc_sizes :: proc(node: ^Box) {
    if node == nil do return
    calc_sizes(node.first)
    for elem := node; elem != nil; elem = elem.next {
        text_size := r.calculate_size(elem.str, 12)
        switch (node.h_size.type) {
            case .BASED_ON_TEXT:
                elem.dimensions.x = text_size[0] + 5 // 2.5 units in each dir
            case .BASED_ON_CHILDREN_SUM:
            //@todo:
            case .BASED_ON_PARENT_PCT:
                parent: ^Box = node.parent
                assert(parent.h_size.type == .FIXED) // this should be fixed
                elem.dimensions.x = parent.h_size.value * elem.h_size.value
            case .NONE, .FIXED:
        }
        switch (node.v_size.type) {
            case .BASED_ON_TEXT:
                elem.dimensions.y = text_size[1] + 5 // 2.5 units in each dir
            case .BASED_ON_CHILDREN_SUM:
            //@todo:
            case .BASED_ON_PARENT_PCT:
                parent: ^Box = node.parent
                assert(parent.v_size.type == .FIXED) // this should be fixed
                elem.dimensions.y = parent.v_size.value * elem.v_size.value
            case .NONE, .FIXED:
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
    }
    calc_positions(node.first)
}

pre_order_traversal :: proc(node: ^Box) {
    if node == nil do return
    for elem := node; elem != nil; elem = elem.next {
        append(&state.draw_commands, {clip = {elem.pos, elem.dimensions}, type = .RECTANGLE})
        if .DRAW_TEXT in elem.flags {
            text_pos: [2]f32 = {elem.pos.x + 2, elem.pos.y + 2}
            append(&state.draw_commands, {clip = {text_pos, {}}, type = .TEXT, str = elem.str})
        }
    }
    pre_order_traversal(node.first)
}

build_draw_commands :: proc() -> []Draw_Command {
    root := state.root
    calc_sizes(root)
    calc_positions(root.first)
    // welp
    for elem := root.first; elem != nil; elem = elem.next {
        pre_order_traversal(elem)
    }
    return state.draw_commands[:]
}
