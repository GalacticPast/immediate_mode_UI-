package ui

import pl "../platform"
import r "../renderer"
import "base:runtime"
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
    // @note: actions
    PRESSABLE,
    HOVERABLE,
    DRAGGABLE,
    RESIZABLE,
    GRABBABLE,

    // @note: types
    CLIP,
    FLOATING_X,
    FLOATING_Y,
    OVERFLOW_X,
    OVERFLOW_Y,
    SCROLLABLE_X,
    SCROLLABLE_Y,

    // @note: draws
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
    BASED_ON_PARENT_PCT, // @note: percentage of parent given that the parent has FIXED SIZE TYPE
}
// @note: it will default to vertical
Axis_Type :: enum {
    VERTICAL,
    HORIZONTAL,
}

Size :: struct {
    type:       Size_Type,
    value:      f32, // @note: if its parent percentage then the value should be between [0,1] inclusive
    strictness: f32, // @note: 1 means it will never shrink and 0 means it will shrink fully
}

Box :: struct {
    // @note: this should persist between draws
    key:                             u64,
    build_index:                     u64, // @note: up to which version did we build it

    // @note: per build
    // @note: first/last -> children
    prev, next, parent, first, last: ^Box,
    child_count:                     u32,
    h_size:                          Size, // @note: horizontal size
    v_size:                          Size, // @note: vertical size
    flags:                           Widget_Flags,
    text_align_flag:                 Text_Align_Flag,
    children_layout_axis:            Axis_Type,
    title:                           string,

    // @note: atached every_frame
    custom_draw:                     proc(elem: ^Box, value: rawptr),
    custom_data:                     rawptr,

    // @note: signals
    hovered:                         bool,
    clicked:                         bool,


    // @note: after build
    pos:                             [2]f32,
    dimensions:                      [2]f32,
    color:                           [3]f32,
}

Box_Desc :: struct {
    h_size:               Maybe(Size),
    v_size:               Maybe(Size),
    pos:                  Maybe([2]f32), // @note: to set the position you have to set FLOATING_X/FLOATING_Y in flags
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
    allocator:            runtime.Allocator, // @note: from arena
    frame_allocator:      runtime.Allocator,
    tree:                 map[u64]^Box,
    curr_parent:          [dynamic]^Box,
    draw_commands:        [dynamic]Draw_Command,
    def_color:            [3]f32,
    curr_build_index:     u64,
    font_size:            f32,
    debug:                bool,

    // @note: frame specific
    root:                 ^Box,
    events:               pl.Event_List,

    // @note: this one gets cached
    prev_frame_mouse_pos: [2]i32, // @note: hmm is this guaranteed though ? what if we were sleeping and just woke up
    mouse_pos:            [2]i32,
    mouse_dx:             [2]i32,

    // @note: transient
    active_widget_key:    u64,
    hot_widget_key:       u64,
    inside_floating:      bool,        // @todo: @temp:
    mouse_btn_press:      pl.Key_Type, // @note: this is short lived
    mouse_btn_held:       pl.Key_Type,
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

    clear(&state.draw_commands) // @note: clear it
    clear(&state.curr_parent)

    state.events = events

    eat: ^pl.Event
    // @warn: even if a widget didnt get clicked I still eat the event
    // @note: could be a issue
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
                if state.mouse_btn_press == e.key {
                    state.mouse_btn_held = .NONE
                } else {
                    state.mouse_btn_held = .NONE
                    state.mouse_btn_press = .NONE
                }
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

build_draw_commands :: proc() -> []Draw_Command {
    root := state.root
    calc_size_independent(root)         // @note: hmmm
    calc_size_upwards_dependent(root)   // @note: hmmm
    calc_size_downwards_dependent(root) // @note: hmmm
    calc_final_sizes(root)

    // @note: important so that we only work on the first child index
    calc_positions(root.first)
    // @note: welp
    pre_order_traversal(root, {root.pos, root.dimensions})
    return state.draw_commands[:]
}

@(private)
make_floating :: proc(box: ^Box) {
    del_ll(box.parent, box)
    box.prev, box.next = nil, nil
    box.parent = state.root
    insert_ll(state.root, box)
}

@(private)
text_align :: proc(elem: ^Box) -> [2]f32 {
    // @perf: cache the text_size
    text_size := r.calculate_text_size(elem.title, state.font_size)
    // @note: hmmm
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
            // @note: can never be placed on the left of the parent
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
    // @note: hot
    if state.active_widget_key == 0 && state.hot_widget_key == 0 {     // @note: if there is an interaction going on or a key is already being hovered , skip the following code
        // @note: clip
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
        // @note: active and hot
        if state.hot_widget_key == elem.key && state.mouse_btn_press == .BTN_LEFT {
            state.active_widget_key = elem.key
            elem.clicked = true
        }
    }
    // @note: active
    if state.active_widget_key == elem.key {
        if .PRESSABLE in elem.flags {
            pl.set_cursor_icon(.POINTER)
        } else if .DRAGGABLE in elem.flags {
            pl.set_cursor_icon(.DRAGGING)
        }
    }

    // @note: none
    if state.mouse_btn_held == .NONE {
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

    key: u64 = 0 // @note: useful for transient boxes that have no state to store between frames
    imm_parent: ^Box = nil
    key_parent: ^Box = nil

    if len(state.curr_parent) > 0 {
        imm_parent = slice.last(state.curr_parent[:])
        key_parent = imm_parent
        // @note: parent might have key == 0
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
            node = new(Box, state.frame_allocator) // @note: for transient boxes
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

    // @note: invalidate the list
    node.prev, node.next, node.first, node.last = nil, nil, nil, nil
    node.parent = imm_parent
    node.clicked = false
    node.hovered = false
    node.color = color
    node.build_index = state.curr_build_index

    // @fix: damn this kinda doesnt work if we were to move the floating window but oh well
    if .FLOATING_X in flags {
        node.pos.x = pref_pos.x
    }
    if .FLOATING_Y in flags {
        node.pos.y = pref_pos.y
    }

    // @note: damn the parent changed
    if imm_parent != nil do insert_ll(imm_parent, node)

    // @note: insert/update the hashmap
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
                elem.dimensions.x = text_size[0] + 5 // @note: 2.5 units in each dir
            case .FIXED:
                elem.dimensions.x = elem.h_size.value
            case .NONE:
        }
        #partial switch (elem.v_size.type) {
            case .BASED_ON_TEXT:
                elem.dimensions.y = text_size[1] + 5 // @note: 2.5 units in each dir
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
        // @note: lol
        if (elem.h_size.type == .BASED_ON_PARENT_PCT) {
            // @note: could be that the dimenions are still 0 because no parent with type fixed was found
            // @note: well root is always fixed so
            for parent := elem.parent; parent != nil; parent = parent.parent {
                if parent.h_size.type == .BASED_ON_CHILDREN_SUM || parent.h_size.type == .NONE {
                    continue
                }
                elem.dimensions.x = parent.dimensions.x * elem.h_size.value
                break
            }
        }
        if (elem.v_size.type == .BASED_ON_PARENT_PCT) {
            // @note: could be tvat the dimenions are still 0 because no parent with type fixed was found
            // @note: well root is always fixed so
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
                    elem.dimensions.x = OFFSET_X // @note: add the initial offset size
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
// @note: this is the pass that will check whether to shrink it or not
// @note: weighted allocation of the overflow
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
        if .OVERFLOW_X not_in elem.flags {
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
            }
        }
        if .OVERFLOW_Y not_in elem.flags {
            if elem.children_layout_axis == .VERTICAL {
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
                    pen_pos.y += elem.dimensions.y // @note: hmm
                }
            case .HORIZONTAL:
                if .FLOATING_X not_in elem.flags {
                    pen_pos.x += elem.dimensions.x // @note: hmm
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
