package ui

import pl "../platform"
import "../text"
import "core:slice"
import "core:unicode/utf8"

@(private)
Edit_Hit_Region :: struct {
    clip: Rect,
    key:  u64,
}

@(private)
Edit_Event :: struct {
    target:  u64,
    event:   ^pl.Event,
    mouse_x: i32,
}

// Resolve focus in event order against the last frame the user actually saw.
@(private)
editor_at :: proc(pos: [2]i32) -> u64 {
    #reverse for region in state.hit_regions {
        if mouse_collision(pos, region.clip) do return region.key
    }
    return 0
}

EDIT_PADDING :: 5

// id is stable across edits. The caller owns the single-line UTF-8 buffer.
// Returns true on frames when user input changes the buffer.
text_edit :: proc(id: string, value: ^[dynamic]u8, description := Box_Desc{}) -> bool {
    assert(len(id) > 0 && value != nil)
    flags := description.flags.? or_else Widget_Flags{.DRAW_RECT}
    field := create_box(
        id,
        description.h_size.? or_else {type = .FIXED, value = 240, strictness = 1},
        description.v_size.? or_else {type = .FIXED, value = 28, strictness = 1},
        description.pos.? or_else {-1, -1},
        (flags - {.DRAW_TEXT}) + {.DRAW_CUSTOM, .TEXT_EDIT},
        .LEFT, .HORIZONTAL,
        description.color.? or_else {0.12, 0.14, 0.17},
    )
    changed := false
    for input in state.edit_events {
        if input.target != field.key do continue
        if input.event.type == .MOUSE_BTN_PRESSED {
            line := text.shape_line(string(value^[:]))
            x := (f32(input.mouse_x) - field.pos.x - EDIT_PADDING + field.edit_scroll) / state.font_size
            nearest := 0
            for stop_x, i in line.x {
                if abs(stop_x - x) < abs(line.x[nearest] - x) do nearest = i
            }
            field.cursor_byte = line.stops[nearest]
        } else if edit_input(value, &field.cursor_byte, input.event) {
            changed = true
        }
    }

    line := new(text.Shaped_Line, state.frame_allocator)
    line^ = text.shape_line(string(value^[:]))
    field.custom_data = line
    field.custom_draw = draw_editor
    return changed
}

@(private)
edit_input :: proc(value: ^[dynamic]u8, cursor: ^int, event: ^pl.Event) -> bool {
    stops := text.grapheme_stops(string(value^[:]))
    index, _ := slice.binary_search(stops, clamp(cursor^, 0, len(value^)))
    cursor^ = stops[index]
    if event.type == .TEXT_INPUT {
        ch := event.payload.(rune)
        if !pl.printable_input(ch) do return false
        bytes, count := utf8.encode_rune(ch)
        ok, _ := inject_at(value, cursor^, ..bytes[:count])
        if ok do cursor^ += count
        return ok
    }
    if event.type != .KEY_PRESS && event.type != .KEY_REPEAT do return false
    previous := stops[max(0, index - 1)]
    next := stops[min(len(stops) - 1, index + 1)]
    #partial switch event.payload.(pl.Key_Type) {
        case .LEFT:  cursor^ = previous
        case .RIGHT: cursor^ = next
        case .HOME:  cursor^ = 0
        case .END:   cursor^ = len(value^)
        case .BACKSPACE:
            if previous == cursor^ do return false
            remove_range(value, previous, cursor^)
            cursor^ = previous
            return true
        case .DELETE:
            if next == cursor^ do return false
            remove_range(value, cursor^, next)
            return true
    }
    return false
}

@(private)
draw_editor :: proc(field: ^Box, data: rawptr) {
    line := (^text.Shaped_Line)(data)
    index, _ := slice.binary_search(line.stops, clamp(field.cursor_byte, 0, line.stops[len(line.stops) - 1]))
    field.cursor_byte = line.stops[index]
    caret := line.x[index] * state.font_size
    width := max(0, field.dimensions.x - 2 * EDIT_PADDING - 1)
    field.edit_scroll = clamp(field.edit_scroll, max(0, caret - width), caret)
    field.edit_scroll = min(field.edit_scroll, max(0, line.width * state.font_size - width))
    height := line.height * state.font_size
    origin := field.pos + [2]f32{EDIT_PADDING - field.edit_scroll, (field.dimensions.y - height) / 2}
    append(&state.draw_commands, Draw_Command{
        type = .SHAPED_LINE, line = line^, font_size = state.font_size,
        rect = {origin, {}}, color = {1, 1, 1},
    })
    if state.focus_key == field.key {
        append(&state.draw_commands, Draw_Command{
            type = .RECTANGLE, rect = {origin + [2]f32{caret, 0}, {1, height}}, color = {1, 1, 1},
        })
    }
}
