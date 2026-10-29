package renderer
import pl "../platform"
import "../text"

import "core:math"

Draw_Instance :: struct {
    pen_offset:                [2]f32,
    curve_indices:             [2]f32,
    color_and_font_px:         [4]f32, // the last value of color is the font size
    translation_matrix:        matrix[4, 4]f32,
    horizontal_band_locations: [4][4]f32,
    vertical_band_locations:   [4][4]f32,
}

Rect :: struct {
    pos:        [2]f32,
    dimensions: [2]f32,
}

Draw_State :: struct {
    glyphs:      ^text.Glyphs,
    // Buffers retain their storage across frames and are released in deinit.
    // for the glyphs
    g_instances: [dynamic]Draw_Instance,
    // for the sdf boxes
    b_instances: [dynamic]Draw_Instance,
    // the final buffer that gets uploaded to the gpu
    gpu_buffer:  [dynamic]Draw_Instance,
}

d_state: Draw_State

// The allocator must remain valid until deinit; buffers are reused across frames.
init :: proc(allocator := context.allocator) {
    backend_init()
    // @info: this is kinda wackk
    d_state.glyphs = text.get_current_font()
    // increased the backing buffer so that the array wont need to keep resizing,
    // could introduce a limit later on
    d_state.g_instances = make([dynamic]Draw_Instance, 0, 1024, allocator)
    d_state.b_instances = make([dynamic]Draw_Instance, 0, 1024, allocator)
    d_state.gpu_buffer = make([dynamic]Draw_Instance, 0, 4098, allocator)
}
deinit :: proc() {
    backend_deinit()
    delete(d_state.g_instances)
    delete(d_state.b_instances)
    delete(d_state.gpu_buffer)
    d_state = {}
}

start_command :: proc() {

}

line_height :: proc() -> f32 {
    g := d_state.glyphs
    return g.ascent - g.descent + g.line_gap
}

// Distance from the top of a text line to its baseline, in logical pixels.
text_baseline_offset :: proc(font_size: f32) -> f32 {
    return d_state.glyphs.ascent * font_size
}

// bytes outside ASCII (e.g. UTF-8 lead bytes) fall back to '?'
get_glyph :: proc(c: u8) -> ^text.Glyph_Data {
    code := c
    if code >= text.TEXT_GLYPH_COUNT do code = '?'
    return &d_state.glyphs.data[code]
}

next_tab_stop :: proc(pen_x: f32, font_size: f32) -> f32 {
    tab := text.TEXT_TAB_WIDTH * d_state.glyphs.data[' '].advance * font_size
    return (math.floor(pen_x / tab) + 1.0) * tab
}

// no wrapping: only '\n' starts a new line
calculate_text_size :: proc(str: string, font_size: f32) -> [2]f32 {
    line_width: f32 = 0.0
    max_width: f32 = 0.0
    line_count: i32 = 1

    for i in 0 ..< len(str) {
        c := str[i]
        switch {
            case c == '\n':
                max_width = max(max_width, line_width)
                line_width = 0.0
                line_count += 1
            case c == '\t':
                line_width = next_tab_stop(line_width, font_size)
            case c < ' ' || c == 127:
            case:
                line_width += get_glyph(c).advance * font_size
        }
    }
    max_width = max(max_width, line_width)

    return {max_width, f32(line_count) * line_height() * font_size}
}

// wrap_width is measured from position.x; 0 disables wrapping
// missing support for multiple font_sizes in the text itself.

push :: proc {
    push_text,
    push_rect,
}

push_text :: proc(str: string, position: [2]f32, color: [3]f32, font_size: f32, wrap_width: f32) {
    d_s := pl.get_display_scale()
    font_px := font_size * d_s
    pos_px := position * d_s
    pen_pos := [2]f32{position.x * d_s, position.y * d_s + d_state.glyphs.ascent * font_px}
    wrap := wrap_width * d_s

    for i in 0 ..< len(str) {
        c := str[i]
        if c == '\n' {
            pen_pos.x = pos_px.x
            pen_pos.y += line_height() * font_px
            continue
        }
        if c == '\t' {
            // tab stops are measured from the start of the string, not the window edge
            pen_pos.x = pos_px.x + next_tab_stop(pen_pos.x - pos_px.x, font_px)
            continue
        }
        // '\r' and every other control code: no glyph, no advance
        if c < ' ' || c == 127 do continue

        g := get_glyph(c)
        line_width := pen_pos.x - pos_px.x
        if wrap > 0.0 && line_width + g.advance * font_px > wrap {
            pen_pos.x = pos_px.x
            pen_pos.y += line_height() * font_px
        }

        // @perf: cache it:
        // all of this could be calculated at the font loading, and every frame we would only need to update the pen_offset
        instance := Draw_Instance {
            // pen goes to em here, so only the pen is scaled. The matrix is already in em
            pen_offset         = pen_pos / font_px,
            curve_indices      = {f32(g.curves_indicies.x), f32(g.curves_indicies.y)},
            color_and_font_px  = {color.r, color.g, color.b, font_px},
            translation_matrix = g.translation_matrix,
        }

        // each vec4 packs two [start, end) ranges
        for k in 0 ..< text.NUMBER_OF_BANDS / 2 {
            h0, h1 := g.bands_loc[2 * k], g.bands_loc[2 * k + 1]
            v0, v1 := g.bands_loc[text.NUMBER_OF_BANDS + 2 * k], g.bands_loc[text.NUMBER_OF_BANDS + 2 * k + 1]
            instance.horizontal_band_locations[k] = {f32(h0.x), f32(h0.y), f32(h1.x), f32(h1.y)}
            instance.vertical_band_locations[k] = {f32(v0.x), f32(v0.y), f32(v1.x), f32(v1.y)}
        }
        append(&d_state.g_instances, instance)
        pen_pos.x += g.advance * font_px
    }
}

push_rect :: proc(r: Rect, color: [3]f32) {
    d_s := pl.get_display_scale()
    pos := r.pos * d_s
    dimensions := r.dimensions * d_s
    instance := Draw_Instance {
        pen_offset                = {pos.x, pos.y},
        curve_indices             = {dimensions.x, dimensions.y},
        color_and_font_px         = {color.r, color.g, color.b, 0},
        translation_matrix        = {},
        horizontal_band_locations = {},
        vertical_band_locations   = {},
    }
    append(&d_state.b_instances, instance)
}

end_command :: proc() {
    // first append all of the box instances
    append(&d_state.gpu_buffer, ..d_state.b_instances[:])
    // append all of the glyph instances
    append(&d_state.gpu_buffer, ..d_state.g_instances[:])
    clear(&d_state.b_instances)
    clear(&d_state.g_instances)
}

render :: proc() {
    update_gpu_buffer(d_state.gpu_buffer[:])
    p_w, p_h := pl.get_framebuffer_size()
    opengl_render(p_w, p_h)
    clear(&d_state.gpu_buffer)
}
