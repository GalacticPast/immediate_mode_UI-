package ui

import "core:sync"
import "core:testing"

// Tests that use the UI's global state must not run at the same time.
clipping_test_mutex: sync.Mutex

@(test)
clipping_parent_restricts_hit_area :: proc(t: ^testing.T) {
    parent := Box{pos = {0, 0}, dimensions = {100, 100}, flags = {.CLIP}}
    child := Box{parent = &parent, pos = {80, 80}, dimensions = {40, 40}}

    hit := Rect{child.pos, box_clip(&child)}
    testing.expect_value(t, hit.dimen, [2]f32{20, 20})
    testing.expect(t, mouse_collision({99, 99}, hit), "visible child area should be hittable")
    testing.expect(t, !mouse_collision({100, 90}, hit), "right overflow should not be hittable")
    testing.expect(t, !mouse_collision({90, 100}, hit), "bottom overflow should not be hittable")
}

@(test)
rectangle_intersection_handles_overlap_and_empty_area :: proc(t: ^testing.T) {
    a := Rect{pos = {10, 10}, dimen = {50, 50}}
    b := Rect{pos = {30, 0}, dimen = {60, 30}}
    overlap := intersect_rect(a, b)
    testing.expect_value(t, overlap.pos, [2]f32{30, 10})
    testing.expect_value(t, overlap.dimen, [2]f32{30, 20})

    separate := intersect_rect(a, Rect{pos = {80, 80}, dimen = {10, 10}})
    testing.expect_value(t, separate.dimen, [2]f32{0, 0})
    testing.expect(t, !mouse_collision({80, 80}, separate))
}

@(test)
only_clipping_ancestors_restrict_hit_area :: proc(t: ^testing.T) {
    outer := Box{pos = {0, 0}, dimensions = {100, 100}, flags = {.CLIP}}
    inner := Box{parent = &outer, pos = {40, 40}, dimensions = {30, 30}}
    child := Box{parent = &inner, pos = {60, 60}, dimensions = {60, 60}}

    testing.expect_value(t, box_clip(&child), [2]f32{40, 40})
    inner.flags = {.CLIP}
    testing.expect_value(t, box_clip(&child), [2]f32{10, 10})

    child.pos = {100, 60}
    hit := Rect{child.pos, box_clip(&child)}
    testing.expect(t, !mouse_collision({100, 60}, hit), "a child outside the clipping ancestor has no hit area")
}

@(test)
drawing_and_hit_testing_respect_row_clip :: proc(t: ^testing.T) {
    sync.mutex_lock(&clipping_test_mutex)
    defer sync.mutex_unlock(&clipping_test_mutex)

    state = {}
    state.draw_commands = make([dynamic]Draw_Command)
    defer {
        delete(state.draw_commands)
        state = {}
    }

    outer := Box{pos = {0, 0}, dimensions = {200, 200}, flags = {.CLIP}}
    row_box := Box{parent = &outer, pos = {50, 50}, dimensions = {50, 50}, flags = {.CLIP}}
    child := Box{parent = &row_box, pos = {80, 60}, dimensions = {80, 20}, flags = {.DRAW_RECT}}
    row_box.first = &child
    row_box.last = &child
    overflow_point := [2]i32{120, 70}

    pre_order_traversal(&row_box, {outer.pos, outer.dimensions})
    if testing.expect_value(t, len(state.draw_commands), 1) {
        testing.expect(t, !mouse_collision(overflow_point, state.draw_commands[0].clip), "clipped overflow should not be drawn")
        testing.expect(t, !mouse_collision(overflow_point, {child.pos, box_clip(&child)}), "clipped overflow should not be hittable")
    }

    clear(&state.draw_commands)
    row_box.flags = {}
    pre_order_traversal(&row_box, {outer.pos, outer.dimensions})
    if testing.expect_value(t, len(state.draw_commands), 1) {
        testing.expect(t, mouse_collision(overflow_point, state.draw_commands[0].clip), "overflow in a non-clipping row should be drawn")
        testing.expect(t, mouse_collision(overflow_point, {child.pos, box_clip(&child)}), "overflow in a non-clipping row should be hittable")
    }
}

@(test)
named_row_retains_layout_between_builds :: proc(t: ^testing.T) {
    sync.mutex_lock(&clipping_test_mutex)
    defer sync.mutex_unlock(&clipping_test_mutex)

    state = {}
    init()
    defer {
        deinit()
        state = {}
    }

    size := Size{type = .FIXED, value = 200}
    description := Box_Desc{flags = {.CLIP}}
    state.curr_build_index = 1
    root := create_box("root", size, size, {}, {}, .NONE, .VERTICAL, {})
    state.root = root
    append(&state.curr_parent, root)

    first_row: ^Box
    if row("clipping row", description) {
        first_row = state.curr_parent[len(state.curr_parent)-1]
        testing.expect_value(t, first_row.dimensions, [2]f32{0, 0})
        first_row.pos = {50, 50}
        first_row.dimensions = {50, 50}
    }

    state.curr_build_index += 1
    clear(&state.curr_parent)
    root = create_box("root", size, size, {}, {}, .NONE, .VERTICAL, {})
    state.root = root
    append(&state.curr_parent, root)

    if row("clipping row", description) {
        rebuilt_row := state.curr_parent[len(state.curr_parent)-1]
        testing.expect(t, rebuilt_row == first_row, "named row should reuse its box")
        testing.expect_value(t, rebuilt_row.pos, [2]f32{50, 50})
        testing.expect_value(t, rebuilt_row.dimensions, [2]f32{50, 50})
        testing.expect_value(t, rebuilt_row.children_layout_axis, Axis_Type.HORIZONTAL)

        child := Box{parent = rebuilt_row, pos = {80, 60}, dimensions = {40, 20}}
        hit := Rect{child.pos, box_clip(&child)}
        testing.expect(t, mouse_collision({90, 70}, hit), "visible child area should be hittable after rebuilding")
        testing.expect(t, !mouse_collision({110, 70}, hit), "clipped child area should not be hittable after rebuilding")
    }
}
