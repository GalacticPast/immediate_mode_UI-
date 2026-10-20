package text

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:os"
import stbtt "vendor:stb/truetype"

import pl "../platform"

curve :: struct {
    p0: [4]f32,
    p1: [4]f32, // control
    p2: [4]f32,
}

aabb2 :: struct {
    center:    [2]f32,
    half_size: [2]f32,
}

NUMBER_OF_BANDS :: 8
// glyph table is indexed directly by ASCII code. Control codes (0-31, 127) stay empty on purpose
TEXT_GLYPH_COUNT :: 128
// a tab advances to the next multiple of this many spaces
TEXT_TAB_WIDTH :: 4

glyph_data :: struct {
    translation_matrix: matrix[4, 4]f32,
    // [start, end) into glyphs.curves
    curves_indicies:    [2]i32,
    aabb:               aabb2,
    advance:            f32, // em
    // first 8 is the start and end for the horizontal
    bands_loc:          [NUMBER_OF_BANDS * 2][2]i32,
}

glyphs :: struct {
    funit_to_em:      f32, // usually 2048
    ascent:           f32,
    descent:          f32,
    line_gap:         f32,
    curves:           [dynamic]curve,
    horizontal_bands: [dynamic]i32,
    vertical_bands:   [dynamic]i32,
    data:             [TEXT_GLYPH_COUNT]glyph_data, // all of ascii
    font_name:        string,
}


text_state :: struct {
    glyphs:    glyphs, // for now there's only one
    allocator: mem.Allocator,
}

t_state: ^text_state

init :: proc(allocator := context.allocator) {
    t_state = new(text_state, allocator)
    assert(t_state != nil)
    t_state.allocator = allocator
    t_state.instances = make([dynamic]r.glyph_instance, allocator)
}

deinit :: proc() {
    delete_glyphs(&t_state.glyphs)
    delete(t_state.instances)
    free(t_state, t_state.allocator)
    t_state = nil
}

@(private)
delete_glyphs :: proc(g: ^glyphs) {
    delete(g.curves)
    delete(g.horizontal_bands)
    delete(g.vertical_bands)
}

load_font :: proc(file_path: string) -> ^glyphs {
    assert(t_state != nil)
    allocator := t_state.allocator

    font_content, err := os.read_entire_file(file_path, allocator)
    fmt.assertf(err == nil && len(font_content) > 0, "couldnt read the font: %v", err)
    // only stbtt reads it, and only inside this proc
    defer delete(font_content, allocator)

    font_info: stbtt.fontinfo
    res := stbtt.InitFont(&font_info, raw_data(font_content), 0)
    assert(bool(res), "font loading failed")

    g: glyphs
    g.curves = make([dynamic]curve, allocator)
    g.horizontal_bands = make([dynamic]i32, allocator)
    g.vertical_bands = make([dynamic]i32, allocator)
    g.funit_to_em = stbtt.ScaleForMappingEmToPixels(&font_info, 1.0)

    ascent, descent, line_gap: i32
    stbtt.GetFontVMetrics(&font_info, &ascent, &descent, &line_gap)
    g.ascent = f32(ascent) * g.funit_to_em
    g.descent = f32(descent) * g.funit_to_em
    g.line_gap = f32(line_gap) * g.funit_to_em

    for i in 0 ..< TEXT_GLYPH_COUNT {
        // control codes map to .notdef (a box) in most fonts; leave them empty instead
        if i < ' ' || i == 127 do continue

        glyph_index := stbtt.FindGlyphIndex(&font_info, rune(i))
        g_data := &g.data[i]

        // the advance is needed even when there is no outline (space)
        advance_funits, left_side_bearing: i32
        stbtt.GetGlyphHMetrics(&font_info, glyph_index, &advance_funits, &left_side_bearing)
        g_data.advance = f32(advance_funits) * g.funit_to_em

        vertices: [^]stbtt.vertex
        vertices_size := stbtt.GetGlyphShape(&font_info, glyph_index, &vertices)
        defer stbtt.FreeShape(&font_info, vertices)

        g_data.curves_indicies.x = i32(len(g.curves))
        curr_point: [4]f32

        for v in vertices[:vertices_size] {
            #partial switch stbtt.vmove(v.type) {
                case .vmove:
                    curr_point.xy = {f32(v.x), f32(v.y)}
                case .vline:
                    p_2 := [4]f32{f32(v.x), f32(v.y), 0, 0}
                    control_p := (p_2 + curr_point) * 0.5
                    append(&g.curves, curve{p0 = curr_point, p1 = control_p, p2 = p_2})
                    curr_point = p_2
                case .vcurve:
                    p_2 := [4]f32{f32(v.x), f32(v.y), 0, 0}
                    control_p := [4]f32{f32(v.cx), f32(v.cy), 0, 0}
                    append(&g.curves, curve{p0 = curr_point, p1 = control_p, p2 = p_2})
                    curr_point = p_2
                case .vcubic:
                // TrueType outlines are quadratic only
            }
        }
        g_data.curves_indicies.y = i32(len(g.curves))
    }

    // transform to em
    for &c in g.curves {
        c.p0 *= g.funit_to_em
        c.p1 *= g.funit_to_em
        c.p2 *= g.funit_to_em
    }

    compute_glyph_bbox(&g)
    // @warn:
    // if there is a previous font that was loaded.
    // But this would destroy the old one so
    delete_glyphs(&t_state.glyphs)
    t_state.glyphs = g

    return &t_state.glyphs
}

@(private)
line_height :: proc() -> f32 {
    g := &t_state.glyphs
    return g.ascent - g.descent + g.line_gap
}

// bytes outside ASCII (e.g. UTF-8 lead bytes) fall back to '?'
@(private)
get_glyph :: proc(c: u8) -> ^glyph_data {
    code := c
    if code >= TEXT_GLYPH_COUNT do code = '?'
    return &t_state.glyphs.data[code]
}

@(private)
next_tab_stop :: proc(pen_x: f32, font_size: f32) -> f32 {
    tab := TEXT_TAB_WIDTH * t_state.glyphs.data[' '].advance * font_size
    return (math.floor(pen_x / tab) + 1.0) * tab
}

// no wrapping: only '\n' starts a new line
calculate_size :: proc(str: string, font_size: f32) -> [2]f32 {
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


@(private)
solve_bezier :: proc(a, b, c, t: f32) -> f32 {
    // (1 - t)^2 a, + 2 * t * ( 1 - t) * b + t * t * c
    return (1 - t) * (1 - t) * a + 2 * t * (1 - t) * b + t * t * c
}

@(private)
compute_glyph_bbox :: proc(g: ^glyphs) {
    for &data in g.data {
        start := data.curves_indicies.x
        end := data.curves_indicies.y

        if start == end do continue

        glyph_curves := g.curves[start:end]

        min_p := [2]f32{math.F32_MAX, math.F32_MAX}
        max_p := [2]f32{-math.F32_MAX, -math.F32_MAX}

        for c in glyph_curves {
            // p1 is the control point
            min_p = linalg.min(min_p, c.p0.xy, c.p2.xy)
            max_p = linalg.max(max_p, c.p0.xy, c.p2.xy)

            // find the internal extremum on each axis
            for axis in 0 ..< 2 {
                denom := c.p0[axis] - 2 * c.p1[axis] + c.p2[axis]
                if denom == 0.0 do continue

                t := (c.p0[axis] - c.p1[axis]) / denom
                if t > 0.0 && t < 1.0 {
                    extremum := solve_bezier(c.p0[axis], c.p1[axis], c.p2[axis], t)
                    min_p[axis] = min(extremum, min_p[axis])
                    max_p[axis] = max(extremum, max_p[axis])
                }
            }
        }

        center := (min_p + max_p) * 0.5
        half_size := (max_p - min_p) * 0.5
        data.aabb = {center, half_size}

        scale_matrix := linalg.matrix4_scale_f32({half_size.x * 2.0, half_size.y * 2.0, 1.0})
        translate_matrix := linalg.matrix4_translate_f32({center.x, center.y, 0.0})
        data.translation_matrix = translate_matrix * scale_matrix

        eps: f32 = 1.0 / 1024.0

        // horizontal banding
        h_band_height := (max_p.y - min_p.y) / NUMBER_OF_BANDS
        for b in 0 ..< NUMBER_OF_BANDS {
            band_min_y := min_p.y + f32(b) * h_band_height - eps
            band_max_y := min_p.y + f32(b + 1) * h_band_height + eps

            data.bands_loc[b].x = i32(len(g.horizontal_bands))
            for c, j in glyph_curves {
                // check if it is horizontal
                if abs(c.p0.y - c.p2.y) < 1e-6 && abs(c.p1.y - (c.p0.y + c.p2.y) * 0.5) < 1e-6 do continue

                // check if the curve overlaps the band
                if min(c.p0.y, c.p1.y, c.p2.y) <= band_max_y && max(c.p0.y, c.p1.y, c.p2.y) >= band_min_y {
                    append(&g.horizontal_bands, start + i32(j))
                }
            }
            data.bands_loc[b].y = i32(len(g.horizontal_bands))
        }

        // vertical banding
        v_band_width := (max_p.x - min_p.x) / NUMBER_OF_BANDS
        for b in 0 ..< NUMBER_OF_BANDS {
            band_min_x := min_p.x + f32(b) * v_band_width - eps
            band_max_x := min_p.x + f32(b + 1) * v_band_width + eps

            data.bands_loc[b + NUMBER_OF_BANDS].x = i32(len(g.vertical_bands))
            for c, j in glyph_curves {
                // check if it is vertical
                if abs(c.p0.x - c.p2.x) < 1e-5 && abs(c.p1.x - (c.p0.x + c.p2.x) * 0.5) < 1e-5 do continue

                // check if the curve overlaps the band
                if min(c.p0.x, c.p1.x, c.p2.x) <= band_max_x && max(c.p0.x, c.p1.x, c.p2.x) >= band_min_x {
                    append(&g.vertical_bands, start + i32(j))
                }
            }
            data.bands_loc[b + NUMBER_OF_BANDS].y = i32(len(g.vertical_bands))
        }
    }
}
