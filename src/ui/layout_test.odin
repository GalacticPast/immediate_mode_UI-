package ui

import "core:testing"

// These tests use local box trees so they do not depend on a display or fonts.
@(test)
layout_children_fit_and_follow_axis :: proc(t: ^testing.T) {
    axes := [2]Axis_Type{.VERTICAL, .HORIZONTAL}
    for axis in axes {
        parent := Box{
            children_layout_axis = axis,
            h_size = {type = .BASED_ON_CHILDREN_SUM},
            v_size = {type = .BASED_ON_CHILDREN_SUM},
        }
        first := Box{parent = &parent, dimensions = {40, 20}}
        second := Box{parent = &parent, dimensions = {25, 15}}
        parent.first, parent.last = &first, &second
        first.next, second.prev = &second, &first

        calc_size_downwards_dependent(&parent)
        calc_positions(parent.first)

        children := [2]^Box{&first, &second}
        for child in children {
            testing.expectf(t, child.pos.x >= parent.pos.x && child.pos.y >= parent.pos.y &&
                            child.pos.x + child.dimensions.x <= parent.pos.x + parent.dimensions.x &&
                            child.pos.y + child.dimensions.y <= parent.pos.y + parent.dimensions.y,
                            "%v parent should contain child at %v with size %v (parent size %v)",
                            axis, child.pos, child.dimensions, parent.dimensions)
        }
        if axis == .VERTICAL {
            testing.expect(t, second.pos.y >= first.pos.y + first.dimensions.y,
                           "vertical children should not overlap")
            testing.expect(t, second.pos.x == first.pos.x, "vertical children should align horizontally")
        } else {
            testing.expect(t, second.pos.x >= first.pos.x + first.dimensions.x,
                           "horizontal children should not overlap")
            testing.expect(t, second.pos.y == first.pos.y, "horizontal children should align vertically")
        }
    }
}

@(test)
layout_parent_percentages :: proc(t: ^testing.T) {
    root := Box{dimensions = {200, 120}, h_size = {type = .FIXED}, v_size = {type = .FIXED}}
    wrapper := Box{parent = &root, h_size = {type = .BASED_ON_CHILDREN_SUM},
                   v_size = {type = .BASED_ON_CHILDREN_SUM}}
    child := Box{parent = &wrapper, h_size = {type = .BASED_ON_PARENT_PCT, value = 0.5},
                 v_size = {type = .BASED_ON_PARENT_PCT, value = 0.25}}
    root.first, wrapper.first = &wrapper, &child

    calc_size_upwards_dependent(&root)
    testing.expect_value(t, child.dimensions, [2]f32{100, 30})
}
