package renderer

import "core:math/linalg"
import "core:mem"
import gl "vendor:OpenGL"

// uploaded as-is to the instanced vbo, the layout has to match the vertex shader
glyph_instance :: struct {
    pen_offset:                [2]f32,
    curve_indices:             [2]f32,
    color_and_font_px:         [4]f32, // the last value of color is the font size
    translation_matrix:        matrix[4, 4]f32,
    horizontal_band_locations: [4][4]f32,
    vertical_band_locations:   [4][4]f32,
}

text_gl_state :: struct {
    curves_ssbo:           u32,
    horizontal_bands_ssbo: u32,
    vertical_bands_ssbo:   u32,
    b_vao:                 u32,
    b_vbo:                 u32,
    b_ebo:                 u32,
    instanced_vbo:         u32,
    shader:                u32,
    projection_loc:        i32,
    model_loc:             i32,
    view_loc:              i32,
    // frame specific
    frame_instance_count:  i32,
    instances:             [dynamic]glyph_instance,
}

@(private)
t_gl_state: ^text_gl_state

// odinfmt: disable
@(private, rodata)
vertices := [?]f32 {
    //     COORDINATES
    -0.5, -0.5, 0.0,
     0.5, -0.5, 0.0,
     0.5,  0.5, 0.0,
    -0.5,  0.5, 0.0,
}

@(private, rodata)
indices := [?]u32 {
    0, 1, 2,
    0, 2, 3,
}
// odinfmt: enable

MAX_GLYPHS :: 4096

// SSBO bindings, must match the layout(binding = N) in the fragment shader
@(private)
CURVES_BINDING :: 1
@(private)
HORIZONTAL_BANDS_BINDING :: 2
@(private)
VERTICAL_BANDS_BINDING :: 3


@(private)
text_init :: proc(allocator: mem.Allocator) {
    t_gl_state = new(text_gl_state, allocator)
    assert(t_gl_state != nil)

    // relative to the working directory: build.sh puts the binary in the project root, next to assets/
    program, ok := gl.load_shaders_file("assets/shaders/text_vertex.glsl", "assets/shaders/text_fragment.glsl")
    assert(ok, "Text shader creation failed")
    t_gl_state.shader = program

    t_gl_state.projection_loc = gl.GetUniformLocation(program, "projection")
    t_gl_state.model_loc = gl.GetUniformLocation(program, "model")
    t_gl_state.view_loc = gl.GetUniformLocation(program, "view")

    gl.GenVertexArrays(1, &t_gl_state.b_vao)
    gl.BindVertexArray(t_gl_state.b_vao)

    gl.GenBuffers(1, &t_gl_state.b_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, t_gl_state.b_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, size_of(vertices), &vertices, gl.STATIC_DRAW)
    link_attrib(0, 3, 3 * size_of(f32), 0)

    gl.GenBuffers(1, &t_gl_state.instanced_vbo)
    gl.BindBuffer(gl.ARRAY_BUFFER, t_gl_state.instanced_vbo)
    gl.BufferData(gl.ARRAY_BUFFER, MAX_GLYPHS * size_of(glyph_instance), nil, gl.DYNAMIC_DRAW)

    stride :: size_of(glyph_instance)

    link_attrib(1, 2, stride, offset_of(glyph_instance, pen_offset))
    link_attrib(2, 2, stride, offset_of(glyph_instance, curve_indices))
    link_attrib(3, 4, stride, offset_of(glyph_instance, color_and_font_px))
    for i in 0 ..< 4 {
        column := uintptr(i * size_of([4]f32))
        link_attrib(u32(4 + i), 4, stride, offset_of(glyph_instance, translation_matrix) + column)
        link_attrib(u32(8 + i), 4, stride, offset_of(glyph_instance, horizontal_band_locations) + column)
        link_attrib(u32(12 + i), 4, stride, offset_of(glyph_instance, vertical_band_locations) + column)
    }

    // every attribute except the quad position (0) advances once per instance
    first_matrix_location :: 4
    matrix_column_count :: 12
    for i in 1 ..< first_matrix_location + matrix_column_count {
        gl.VertexAttribDivisor(u32(i), 1)
    }
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)

    // bound while the vao is bound, so the vao remembers it
    gl.GenBuffers(1, &t_gl_state.b_ebo)
    gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, t_gl_state.b_ebo)
    gl.BufferData(gl.ELEMENT_ARRAY_BUFFER, size_of(indices), &indices, gl.STATIC_DRAW)

    gl.BindVertexArray(0)
}

// links the currently bound GL_ARRAY_BUFFER to attribute `index` of the bound vao
@(private)
link_attrib :: proc(index: u32, components: i32, stride: i32, offset: uintptr) {
    gl.VertexAttribPointer(index, components, gl.FLOAT, false, stride, offset)
    gl.EnableVertexAttribArray(index)
}

// needs the GL context, so it runs before the context is destroyed
@(private)
text_deinit :: proc() {
    gl.DeleteBuffers(1, &t_gl_state.curves_ssbo)
    gl.DeleteBuffers(1, &t_gl_state.horizontal_bands_ssbo)
    gl.DeleteBuffers(1, &t_gl_state.vertical_bands_ssbo)

    gl.DeleteBuffers(1, &t_gl_state.instanced_vbo)
    gl.DeleteBuffers(1, &t_gl_state.b_vbo)
    gl.DeleteBuffers(1, &t_gl_state.b_ebo)
    gl.DeleteVertexArrays(1, &t_gl_state.b_vao)

    gl.DeleteProgram(t_gl_state.shader)
    // @info: incomplete
    //free(t_gl_state, r_state.allocator)
    t_gl_state = nil
}

@(private)
upload_ssbo :: proc(ssbo: ^u32, binding: u32, data: []$T) {
    // a reloaded font replaces the old buffer
    if ssbo^ != 0 do gl.DeleteBuffers(1, ssbo)

    gl.GenBuffers(1, ssbo)
    gl.BindBuffer(gl.SHADER_STORAGE_BUFFER, ssbo^)
    gl.BufferData(gl.SHADER_STORAGE_BUFFER, len(data) * size_of(T), raw_data(data), gl.STATIC_DRAW)
    gl.BindBufferBase(gl.SHADER_STORAGE_BUFFER, binding, ssbo^)
}

@(private)
upload_to_gpu :: proc(g: ^glyphs) {
    upload_ssbo(&t_gl_state.curves_ssbo, CURVES_BINDING, g.curves[:])
    upload_ssbo(&t_gl_state.horizontal_bands_ssbo, HORIZONTAL_BANDS_BINDING, g.horizontal_bands[:])
    upload_ssbo(&t_gl_state.vertical_bands_ssbo, VERTICAL_BANDS_BINDING, g.vertical_bands[:])
}

@(private)
update_gpu_buffer :: proc(instances: []glyph_instance) {
    assert(len(instances) <= MAX_GLYPHS, "Insufficient size on the gpu to hold glyph data")
    t_gl_state.frame_instance_count = i32(len(instances))

    gl.BindBuffer(gl.ARRAY_BUFFER, t_gl_state.instanced_vbo)
    gl.BufferSubData(gl.ARRAY_BUFFER, 0, len(instances) * size_of(glyph_instance), raw_data(instances))
    gl.BindBuffer(gl.ARRAY_BUFFER, 0)
}

@(private)
set_shader_uniforms :: proc(physical_width, physical_height: i32) {
    // the projection works in physical pixels, matching the buffer and font_px
    // top = 0, so y grows downwards
    ortho := linalg.matrix_ortho3d_f32(0, f32(physical_width), f32(physical_height), 0, -1, 1)
    view := linalg.MATRIX4F32_IDENTITY
    model := linalg.MATRIX4F32_IDENTITY

    gl.UniformMatrix4fv(t_gl_state.view_loc, 1, false, &view[0, 0])
    gl.UniformMatrix4fv(t_gl_state.projection_loc, 1, false, &ortho[0, 0])
    gl.UniformMatrix4fv(t_gl_state.model_loc, 1, false, &model[0, 0])
}

@(private)
text_render :: proc(physical_width, physical_height: i32) {
    gl.UseProgram(t_gl_state.shader)

    set_shader_uniforms(physical_width, physical_height)

    gl.BindVertexArray(t_gl_state.b_vao)

    gl.DrawElementsInstanced(gl.TRIANGLES, len(indices), gl.UNSIGNED_INT, nil, t_gl_state.frame_instance_count)
}
// wrap_width is measured from position.x; 0 disables wrapping
// missing support for multiple font_sizes in the text itself.
push_string :: proc(str: string, position: [2]f32, color: [3]f32, font_size: f32, wrap_width: f32) {
    pen_pos := [2]f32{position.x, position.y + t_state.glyphs.ascent * font_size}

    for i in 0 ..< len(str) {
        c := str[i]
        if c == '\n' {
            pen_pos.x = position.x
            pen_pos.y += line_height() * font_size
            continue
        }
        if c == '\t' {
            // tab stops are measured from the start of the string, not the window edge
            pen_pos.x = position.x + next_tab_stop(pen_pos.x - position.x, font_size)
            continue
        }
        // '\r' and every other control code: no glyph, no advance
        if c < ' ' || c == 127 do continue

        g := get_glyph(c)
        line_width := pen_pos.x - position.x
        if wrap_width > 0.0 && line_width + g.advance * font_size > wrap_width {
            pen_pos.x = position.x
            pen_pos.y += line_height() * font_size
        }

        instance := r.glyph_instance {
            // pen goes to em here, so only the pen is scaled. The matrix is already in em
            pen_offset         = pen_pos / font_size,
            curve_indices      = {f32(g.curves_indicies.x), f32(g.curves_indicies.y)},
            color_and_font_px  = {color.r, color.g, color.b, font_size},
            translation_matrix = g.translation_matrix,
        }

        // each vec4 packs two [start, end) ranges
        for k in 0 ..< NUMBER_OF_BANDS / 2 {
            h0, h1 := g.bands_loc[2 * k], g.bands_loc[2 * k + 1]
            v0, v1 := g.bands_loc[NUMBER_OF_BANDS + 2 * k], g.bands_loc[NUMBER_OF_BANDS + 2 * k + 1]
            instance.horizontal_band_locations[k] = {f32(h0.x), f32(h0.y), f32(h1.x), f32(h1.y)}
            instance.vertical_band_locations[k] = {f32(v0.x), f32(v0.y), f32(v1.x), f32(v1.y)}
        }
        append(&t_state.instances, instance)
        pen_pos.x += g.advance * font_size
    }
}

flush :: proc() {
    r.update_gpu_buffer(t_state.instances[:])
    p_w, p_h := pl.get_framebuffer_size()
    r.render(p_w, p_h)
    clear(&t_state.instances)
}
