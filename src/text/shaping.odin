package text

import "core:slice"
import kb "shaping:kb_text_shape"

Positioned_Glyph :: struct {
    id:     u16,
    offset: [2]f32, // em, relative to the baseline in screen coordinates
}

Shaped_Line :: struct {
    glyphs: []Positioned_Glyph,
    stops:  []int, // UTF-8 byte offsets, in logical order
    x:      []f32, // caret position in em at each stop
    width:  f32,
    height: f32,
}

// The returned slices are frame-local.
grapheme_stops :: proc(value: string) -> []int {
    flags := make([]kb.break_flags, len(value) + 1, context.temp_allocator)
    kb.BreakEntireStringUtf8(.DONT_KNOW, .NORMAL, {}, value, nil, nil, flags, nil)
    stops := make([dynamic]int, context.temp_allocator)
    append(&stops, 0)
    for i in 1 ..< len(value) {
        if .GRAPHEME in flags[i] do append(&stops, i)
    }
    if len(value) > 0 do append(&stops, len(value))
    return stops[:]
}

shape_line :: proc(value: string) -> Shaped_Line {
    stops := grapheme_stops(value)
    line := Shaped_Line{stops = stops, x = make([]f32, len(stops), context.temp_allocator)}
    font := get_current_font()
    line.height = font.ascent - font.descent + font.line_gap
    if len(value) == 0 do return line

    kb.ShapeBegin(font.shaper, .KBTS_DIRECTION_LTR, .DONT_KNOW)
    kb.ShapeUtf8(font.shaper, value, .SOURCE_INDEX)
    kb.ShapeEnd(font.shaper)

    Span :: struct {first, last: f32, seen: bool}
    spans := make([]Span, len(stops) - 1, context.temp_allocator)
    glyphs := make([dynamic]Positioned_Glyph, context.temp_allocator)
    for run in kb.ShapeRun(font.shaper) {
        it := run.Glyphs
        for glyph in kb.GlyphIteratorNext(&it) {
            start := line.width
            offset := [2]f32{f32(glyph.OffsetX), -f32(glyph.OffsetY)} * font.funit_to_em
            append(&glyphs, Positioned_Glyph{glyph.Id, {start + offset.x, offset.y}})
            line.width += f32(glyph.AdvanceX) * font.funit_to_em

            cp: kb.shape_codepoint
            if !kb.ShapeGetShapeCodepoint(font.shaper, glyph.UserIdOrCodepointIndex, &cp) do continue
            index, exact := slice.binary_search(stops, int(cp.UserId))
            if !exact do index -= 1
            span := &spans[index]
            if run.Direction == .KBTS_DIRECTION_RTL {
                if !span.seen do span.last = start
                span.first = line.width
            } else {
                if !span.seen do span.first = start
                span.last = line.width
            }
            span.seen = true
        }
    }
    // A ligature can cover several graphemes. Distribute its internal caret stops.
    for i := 0; i < len(spans); {
        end := i + 1
        for end < len(spans) && !spans[end].seen do end += 1
        span := spans[i]
        for j in i ..< end {
            line.x[j] = span.first + (span.last - span.first) * f32(j - i) / f32(end - i)
        }
        line.x[end] = span.last
        i = end
    }
    line.glyphs = glyphs[:]
    return line
}
