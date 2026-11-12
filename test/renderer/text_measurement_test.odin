package renderer

import "core:testing"
import "../text"

@(test)
text_measurement_handles_lines_tabs_and_fallback_glyphs :: proc(t: ^testing.T) {
    glyphs: text.Glyphs
    glyphs.ascent = 1
    glyphs.descent = -0.25
    glyphs.data['A'].advance = 0.5
    glyphs.data['B'].advance = 1
    glyphs.data[' '].advance = 0.25
    glyphs.data['?'].advance = 0.75
    d_state.glyphs = &glyphs
    defer { d_state.glyphs = nil }

    testing.expect_value(t, calculate_text_size("AB", 8), [2]f32{12, 10})
    testing.expect_value(t, calculate_text_size("A\tB", 8), [2]f32{16, 10})
    testing.expect_value(t, calculate_text_size("AB\nA", 8), [2]f32{12, 20})
    testing.expect_value(t, calculate_text_size("A\rB", 8), [2]f32{12, 10})
    testing.expect_value(t, calculate_text_size("\xff", 8), [2]f32{6, 10})
    testing.expect_value(t, text_baseline_offset(8), f32(8))
}
