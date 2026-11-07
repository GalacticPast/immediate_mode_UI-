#version 430 core

struct Curve
{
    vec4 p0;
    vec4 p1; // control 
    vec4 p2;
};

layout(std430, binding = 1) buffer curve_buffer{
    Curve curves[];
};
layout(std430, binding = 2) buffer h_bands{
    int horizontal_bands[];
};
layout(std430, binding = 3) buffer v_bands{
    int vertical_bands[];
};

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

layout (location = 0) in vec3 position;

// instanced
layout (location = 1) in vec2 pen_offset; // glyph: em offset; box: top-left in pixels
layout (location = 2) in vec2 curve_indicies; // glyph: curve range; box: dimensions in pixels
layout (location = 3) in vec4 text_color; // rgb, font size in pixels (0 means box)
layout (location = 4) in vec4 bands_location; // x,y -> horizontal band_loc range, z, w -> vertical_band_loc_range
layout (location = 5) in mat4 translation_matrix;
layout (location = 9) in vec4 clip_rect; // position and dimensions in physical pixels

flat out vec2 frag_curve_indicies;
flat out vec4 frag_band_locations;
flat out vec2 frag_glyph_min;
flat out vec2 frag_glyph_max;
flat out vec3 frag_color;
flat out float frag_font_px;
flat out vec2 frag_box_half_size;
flat out vec4 frag_clip_rect;


out vec2 frag_pos;
out vec2 frag_screen_pos;

void main()
{
    frag_color = text_color.rgb;
    float font_px = text_color.a;
    frag_font_px = font_px;
    frag_box_half_size = vec2(0.0);
    frag_clip_rect = clip_rect;

    if (font_px == 0.0)
    {
        frag_box_half_size = max(curve_indicies, vec2(0.0)) * 0.5;
        // Centered box coordinates in pixels; expand the quad for edge antialiasing.
        frag_pos = position.xy * (frag_box_half_size * 2.0 + vec2(1.0));
        vec2 pixel_xy = pen_offset + frag_box_half_size + frag_pos;
        frag_screen_pos = pixel_xy;
        gl_Position = projection * view * model * vec4(pixel_xy, 0.0, 1.0);
        return;
    }

    // glyph space, in em: same units as the curves. Must not include pen_offset
    vec4 glyph_pos = (model * translation_matrix) * vec4(position, 1.0);

    // dilate the quad by half a pixel so edge pixels are shaded (the paper's bounding-box expansion)
    glyph_pos.xy += sign(position.xy) * (0.5 / font_px);
    frag_pos = glyph_pos.xy;
    frag_curve_indicies = curve_indicies;
    frag_band_locations = bands_location;

    // translation_matrix = translate(center) * scale(half_size * 2); recover the glyph's em-space bbox
    // from it directly (model is identity in this renderer, so skipping it here is safe)
    vec2 glyph_center    = translation_matrix[3].xy;
    vec2 glyph_half_size = vec2(translation_matrix[0].x, translation_matrix[1].y) * 0.5;
    frag_glyph_min = glyph_center - glyph_half_size;
    frag_glyph_max = glyph_center + glyph_half_size;

    // em -> pixels, for placing the vertex on screen only. The screen is top-left origin (y down) but font
    // outlines are y up, so the glyph's y is flipped here, not in the projection, to keep the UI convention
    vec2 pixel_xy = vec2(glyph_pos.x + pen_offset.x, pen_offset.y - glyph_pos.y) * font_px;
    frag_screen_pos = pixel_xy;
    vec4 pixel_pos = vec4(pixel_xy, 0.0, 1.0);
    gl_Position    = projection * view * pixel_pos;
}
