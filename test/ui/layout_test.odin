package ui

import "core:sync"
import "core:testing"

@(test)
percentage_size_uses_nearest_sized_ancestor :: proc(t: ^testing.T) {
    root := Box{h_size = {type = .FIXED}, v_size = {type = .FIXED}, dimensions = {200, 120}}
    wrapper := Box{parent = &root, h_size = {type = .BASED_ON_CHILDREN_SUM}, v_size = {type = .NONE}}
    child := Box{
        parent = &wrapper,
        h_size = {type = .BASED_ON_PARENT_PCT, value = 0.5},
        v_size = {type = .BASED_ON_PARENT_PCT, value = 0.25},
    }
    root.first = &wrapper
    wrapper.first = &child

    calc_size_upwards_dependent(&root)
    testing.expect_value(t, child.dimensions, [2]f32{100, 30})
}

@(test)
children_sum_fits_normal_children_and_ignores_floating_axes :: proc(t: ^testing.T) {
    parent := Box{
        h_size = {type = .BASED_ON_CHILDREN_SUM},
        v_size = {type = .BASED_ON_CHILDREN_SUM},
        children_layout_axis = .HORIZONTAL,
    }
    first := Box{parent = &parent, dimensions = {10, 6}}
    second := Box{parent = &parent, dimensions = {20, 8}}
    floating := Box{parent = &parent, dimensions = {500, 500}, flags = {.FLOATING_X, .FLOATING_Y}}
    parent.first = &first
    first.next = &second
    second.next = &floating

    calc_size_downwards_dependent(&parent)
    testing.expect_value(t, parent.dimensions, [2]f32{39, 14})

    parent.children_layout_axis = .VERTICAL
    calc_size_downwards_dependent(&parent)
    testing.expect_value(t, parent.dimensions, [2]f32{26, 23})
}

@(test)
strict_children_keep_their_size_when_siblings_can_shrink :: proc(t: ^testing.T) {
    parent := Box{dimensions = {106, 40}, children_layout_axis = .HORIZONTAL}
    strict := Box{parent = &parent, dimensions = {80, 60}, h_size = {strictness = 1}}
    flexible := Box{parent = &parent, dimensions = {40, 20}, h_size = {strictness = 0}}
    parent.first = &strict
    strict.next = &flexible

    calc_final_sizes(&parent)
    testing.expect_value(t, strict.dimensions, [2]f32{80, 40})
    testing.expect_value(t, flexible.dimensions, [2]f32{20, 20})
}

@(test)
vertical_overflow_is_shared_by_flexible_children :: proc(t: ^testing.T) {
    parent := Box{dimensions = {40, 66}, children_layout_axis = .VERTICAL}
    first := Box{parent = &parent, dimensions = {20, 40}, v_size = {strictness = 0}}
    second := Box{parent = &parent, dimensions = {20, 40}, v_size = {strictness = 0}}
    parent.first = &first
    first.next = &second

    calc_final_sizes(&parent)
    testing.expect_value(t, first.dimensions, [2]f32{20, 30})
    testing.expect_value(t, second.dimensions, [2]f32{20, 30})
}

@(test)
fully_strict_children_are_not_shrunk_on_layout_axis :: proc(t: ^testing.T) {
    parent := Box{dimensions = {50, 50}, children_layout_axis = .HORIZONTAL}
    first := Box{parent = &parent, dimensions = {40, 20}, h_size = {strictness = 1}}
    second := Box{parent = &parent, dimensions = {40, 20}, h_size = {strictness = 1}}
    parent.first = &first
    first.next = &second

    calc_final_sizes(&parent)
    testing.expect_value(t, first.dimensions.x, f32(40))
    testing.expect_value(t, second.dimensions.x, f32(40))
}

@(test)
positions_follow_layout_and_leave_floating_position_unchanged :: proc(t: ^testing.T) {
    parent := Box{pos = {10, 20}, children_layout_axis = .HORIZONTAL}
    floating := Box{parent = &parent, pos = {150, 160}, dimensions = {50, 20}, flags = {.FLOATING_X, .FLOATING_Y}}
    first := Box{parent = &parent, dimensions = {20, 10}}
    second := Box{parent = &parent, dimensions = {15, 10}}
    parent.first = &floating
    floating.next = &first
    first.next = &second

    calc_positions(parent.first)
    testing.expect_value(t, floating.pos, [2]f32{150, 160})
    testing.expect_value(t, first.pos, [2]f32{13, 23})
    testing.expect_value(t, second.pos, [2]f32{33, 23})
}

@(test)
floating_panel_moves_out_of_original_parent :: proc(t: ^testing.T) {
    sync.mutex_lock(&clipping_test_mutex)
    defer sync.mutex_unlock(&clipping_test_mutex)
    state = {}
    defer { state = {} }

    root := Box{}
    parent := Box{parent = &root}
    floating := Box{parent = &parent, flags = {.FLOATING_X, .FLOATING_Y}}
    state.root = &root
    insert_ll(&root, &parent)
    insert_ll(&parent, &floating)

    make_floating(&floating)
    testing.expect(t, floating.parent == &root, "floating panel should have the root as parent")
    testing.expect(t, parent.first == nil && parent.last == nil, "old parent should no longer contain the floating panel")
    testing.expect_value(t, parent.child_count, u32(0))
    testing.expect(t, root.first == &parent && root.last == &floating, "root should retain the old parent and contain the floating panel")
    testing.expect(t, parent.next == &floating && floating.prev == &parent, "root sibling links should be consistent")
}
