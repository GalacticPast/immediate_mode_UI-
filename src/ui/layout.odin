// Layout follows RAD's ui_layout_root: five passes per axis, X first, then Y.
package ui

import "core:math"

@(private)
FLOATING_FLAG := [Axis]Box_Flag{.X = .Floating_X, .Y = .Floating_Y}
@(private)
FIXED_FLAG := [Axis]Box_Flag{.X = .Fixed_Width, .Y = .Fixed_Height}
@(private)
OVERFLOW_FLAG := [Axis]Box_Flag{.X = .Allow_Overflow_X, .Y = .Allow_Overflow_Y}
@(private)
SKIP_VIEW_OFF_FLAG := [Axis]Box_Flag{.X = .Skip_View_Off_X, .Y = .Skip_View_Off_Y}
@(private)
ANIMATE_POS_FLAG := [Axis]Box_Flag{.X = .Animate_Pos_X, .Y = .Animate_Pos_Y}

layout_root :: proc(s: ^State, root: ^Box, axis: Axis) {
    layout_standalone(s, root, axis)
    layout_upwards_dependent(root, axis)
    layout_downwards_dependent(root, axis)
    layout_enforce_constraints(root, axis)
    layout_position(s, root, axis)
}

// 1. sizes that need nothing but the box itself: pixels and text
@(private)
layout_standalone :: proc(s: ^State, b: ^Box, axis: Axis) {
    a := int(axis)
    size := b.pref_size[axis]
    if FIXED_FLAG[axis] not_in b.flags {
        #partial switch size.kind {
            case .Pixels:
                b.fixed_size[a] = size.value
            case .Text:
                dim: Vec2
                if s.measure_text != nil && len(b.text) > 0 do dim = s.measure_text(b.text, b.font_size)
                if axis == .X {
                    b.fixed_size[a] = dim.x + 2 * b.text_padding + size.value
                } else {
                    b.fixed_size[a] = max(dim.y, b.font_size) + size.value
                }
        }
    }
    for c := b.first; c != nil; c = c.next do layout_standalone(s, c, axis)
}

// 2. pre-order: percentages of the nearest ancestor whose size doesn't come from its children
@(private)
layout_upwards_dependent :: proc(b: ^Box, axis: Axis) {
    a := int(axis)
    if b.pref_size[axis].kind == .Parent_Pct && FIXED_FLAG[axis] not_in b.flags {
        for p := b.parent; p != nil; p = p.parent {
            kind := p.pref_size[axis].kind
            if FIXED_FLAG[axis] in p.flags || kind == .Pixels || kind == .Text || kind == .Parent_Pct {
                b.fixed_size[a] = p.fixed_size[a] * b.pref_size[axis].value
                break
            }
        }
    }
    for c := b.first; c != nil; c = c.next do layout_upwards_dependent(c, axis)
}

// 3. post-order: sizes that sum up the children
@(private)
layout_downwards_dependent :: proc(b: ^Box, axis: Axis) {
    a := int(axis)
    for c := b.first; c != nil; c = c.next do layout_downwards_dependent(c, axis)
    if b.pref_size[axis].kind != .Children_Sum || FIXED_FLAG[axis] in b.flags do return
    sum: f32
    for c := b.first; c != nil; c = c.next {
        if FLOATING_FLAG[axis] in c.flags do continue
        if axis == b.child_layout_axis {
            sum += c.fixed_size[a]
        } else {
            sum = max(sum, c.fixed_size[a])
        }
    }
    b.fixed_size[a] = sum
}

// 4. pre-order: shrink children that don't fit, each by its (1 - strictness) share
@(private)
layout_enforce_constraints :: proc(b: ^Box, axis: Axis) {
    a := int(axis)
    shrinkable :: proc(c: ^Box, axis: Axis) -> bool {
        return FLOATING_FLAG[axis] not_in c.flags && FIXED_FLAG[axis] not_in c.flags
    }

    if OVERFLOW_FLAG[axis] not_in b.flags {
        allowed := b.fixed_size[a]
        if axis != b.child_layout_axis {
            // across the layout axis every child must fit on its own
            for c := b.first; c != nil; c = c.next {
                if !shrinkable(c, axis) do continue
                violation := c.fixed_size[a] - allowed
                fixup := clamp(violation, 0, c.fixed_size[a] * (1 - c.pref_size[axis].strictness))
                c.fixed_size[a] -= fixup
            }
        } else {
            // along it, the children share the overflow
            total, total_weight: f32
            for c := b.first; c != nil; c = c.next {
                if FLOATING_FLAG[axis] in c.flags do continue
                total += c.fixed_size[a]
                if shrinkable(c, axis) do total_weight += c.fixed_size[a] * (1 - c.pref_size[axis].strictness)
            }
            violation := total - allowed
            if violation > 0 && total_weight > 0 {
                fraction := clamp(violation / total_weight, 0, 1)
                for c := b.first; c != nil; c = c.next {
                    if !shrinkable(c, axis) do continue
                    c.fixed_size[a] -= c.fixed_size[a] * (1 - c.pref_size[axis].strictness) * fraction
                }
            }
        }
    }

    // a box that lets its content overflow still sizes percentages against itself
    if OVERFLOW_FLAG[axis] in b.flags {
        for c := b.first; c != nil; c = c.next {
            if c.pref_size[axis].kind == .Parent_Pct && FIXED_FLAG[axis] not_in c.flags {
                c.fixed_size[a] = b.fixed_size[a] * c.pref_size[axis].value
            }
        }
    }

    for c := b.first; c != nil; c = c.next do layout_enforce_constraints(c, axis)
}

// 5. pre-order: positions relative to the parent, then absolute rects
@(private)
layout_position :: proc(s: ^State, b: ^Box, axis: Axis) {
    a := int(axis)
    if b.parent == nil {
        b.rect.pos[a] = b.fixed_position[a]
        b.rect.size[a] = b.fixed_size[a]
    }
    cursor, bounds: f32
    slow := slow_rate(s)
    for c := b.first; c != nil; c = c.next {
        if FLOATING_FLAG[axis] not_in c.flags {
            if axis == b.child_layout_axis {
                c.fixed_position[a] = cursor
                cursor += c.fixed_size[a]
                bounds += c.fixed_size[a]
            } else {
                c.fixed_position[a] = 0
                bounds = max(bounds, c.fixed_size[a])
            }
        }
        pos := c.fixed_position[a]
        if ANIMATE_POS_FLAG[axis] in c.flags && c.first_touched_build != s.build_index {
            c.fixed_position_animated[a] += (pos - c.fixed_position_animated[a]) * slow
            if abs(pos - c.fixed_position_animated[a]) < 0.5 {
                c.fixed_position_animated[a] = pos
            } else {
                s.animating = true
            }
            pos = c.fixed_position_animated[a]
        } else {
            c.fixed_position_animated[a] = pos
        }
        if SKIP_VIEW_OFF_FLAG[axis] not_in c.flags do pos -= math.floor(b.view_off[a])
        c.rect.pos[a] = b.rect.pos[a] + pos
        c.rect.size[a] = c.fixed_size[a]
        layout_position(s, c, axis)
    }
    b.view_bounds[a] = bounds
}

// Each box's clip is the intersection of its clipping ancestors; it doesn't include the box itself.
layout_clip :: proc(b: ^Box, clip: Rect) {
    b.clip = clip
    child_clip := .Clip in b.flags ? intersection(clip, b.rect) : clip
    for c := b.first; c != nil; c = c.next do layout_clip(c, child_clip)
}
