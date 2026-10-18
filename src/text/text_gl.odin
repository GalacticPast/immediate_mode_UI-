package text

import "core:math/linalg"
import "core:mem"
import gl "vendor:OpenGL"

@(private)
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

// SSBO bindings, must match the layout(binding = N) in the fragment shader
@(private)
CURVES_BINDING :: 1
@(private)
HORIZONTAL_BANDS_BINDING :: 2
@(private)
VERTICAL_BANDS_BINDING :: 3

@(private)
gl_init :: proc(allocator: mem.Allocator) {
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
gl_deinit :: proc() {
    gl.DeleteBuffers(1, &t_gl_state.curves_ssbo)
    gl.DeleteBuffers(1, &t_gl_state.horizontal_bands_ssbo)
    gl.DeleteBuffers(1, &t_gl_state.vertical_bands_ssbo)

    gl.DeleteBuffers(1, &t_gl_state.instanced_vbo)
    gl.DeleteBuffers(1, &t_gl_state.b_vbo)
    gl.DeleteBuffers(1, &t_gl_state.b_ebo)
    gl.DeleteVertexArrays(1, &t_gl_state.b_vao)

    gl.DeleteProgram(t_gl_state.shader)

    free(t_gl_state, t_state.allocator)
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
set_shader_uniforms :: proc(physical_width, physical_height: u32) {
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
render :: proc(physical_width, physical_height: u32) {
    gl.UseProgram(t_gl_state.shader)

    set_shader_uniforms(physical_width, physical_height)

    gl.BindVertexArray(t_gl_state.b_vao)

    gl.DrawElementsInstanced(gl.TRIANGLES, len(indices), gl.UNSIGNED_INT, nil, t_gl_state.frame_instance_count)
}
