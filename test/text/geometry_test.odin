package text

import "core:testing"

@(test)
quadratic_bezier_bounds_include_curve_extremum :: proc(t: ^testing.T) {
    glyphs: Glyphs
    glyphs.curves = make([dynamic]Curve)
    defer delete_glyphs(&glyphs)

    append(&glyphs.curves, Curve{p0 = {0, 0, 0, 0}, p1 = {1, 2, 0, 0}, p2 = {2, 0, 0, 0}})
    glyphs.data['A'].curves_indicies = {0, 1}
    compute_glyph_bbox(&glyphs)

    testing.expect_value(t, glyphs.data['A'].aabb.center, [2]f32{1, 0.5})
    testing.expect_value(t, glyphs.data['A'].aabb.half_size, [2]f32{1, 0.5})
    testing.expect_value(t, glyphs.data[' '].aabb.half_size, [2]f32{0, 0})
}
