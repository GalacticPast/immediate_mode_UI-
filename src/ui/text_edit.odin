package ui

import "core:unicode/utf8"

// What one input event does to a single-line text field (RAD: UI_TxtOp).
// Pure data, so it's testable without a UI: the caller applies it with text_op_apply.
Text_Op :: struct {
    replace_start, replace_end: int, // byte range that gets replaced
    insert_rune:                rune, // typed character to insert, 0 for none
    paste:                      bool, // insert the clipboard
    copy:                       bool, // put [replace_start, replace_end) on the clipboard
    edits:                      bool, // the text changes
    cursor, mark:               int, // after the edit (for insertions, before the inserted text)
}

@(private)
prev_boundary :: proc(text: string, i: int) -> int {
    if i <= 0 do return 0
    _, size := utf8.decode_last_rune_in_string(text[:i])
    return i - max(size, 1)
}
@(private)
next_boundary :: proc(text: string, i: int) -> int {
    if i >= len(text) do return len(text)
    _, size := utf8.decode_rune_in_string(text[i:])
    return i + max(size, 1)
}
@(private)
is_word_byte :: proc(c: u8) -> bool {
    return c >= '0' && c <= '9' || c >= 'a' && c <= 'z' || c >= 'A' && c <= 'Z' || c == '_' || c >= 0x80
}
word_start :: proc(text: string, i: int) -> int {
    i := i
    for i > 0 && !is_word_byte(text[i - 1]) do i -= 1
    for i > 0 && is_word_byte(text[i - 1]) do i -= 1
    return i
}
word_end :: proc(text: string, i: int) -> int {
    i := i
    for i < len(text) && !is_word_byte(text[i]) do i += 1
    for i < len(text) && is_word_byte(text[i]) do i += 1
    return i
}

text_op_from_event :: proc(text: string, cursor, mark: int, e: Event) -> (op: Text_Op, handled: bool) {
    lo, hi := min(cursor, mark), max(cursor, mark)
    has_selection := lo != hi
    ctrl := .Ctrl in e.mods
    shift := .Shift in e.mods
    op = {cursor = cursor, mark = mark}

    move :: proc(op: ^Text_Op, to: int, shift: bool) {
        op.cursor = to
        if !shift do op.mark = to
    }
    remove :: proc(op: ^Text_Op, start, end: int) {
        op.replace_start, op.replace_end = start, end
        op.cursor, op.mark = start, start
        op.edits = true
    }

    if e.kind == .Text {
        if e.text < 32 || e.text == 127 do return op, false
        remove(&op, lo, hi)
        op.insert_rune = e.text
        return op, true
    }
    if e.kind != .Key_Press do return op, false

    #partial switch e.key {
        case .Left:
            switch {
                case has_selection && !shift && !ctrl: move(&op, lo, false)
                case ctrl: move(&op, word_start(text, cursor), shift)
                case: move(&op, prev_boundary(text, cursor), shift)
            }
        case .Right:
            switch {
                case has_selection && !shift && !ctrl: move(&op, hi, false)
                case ctrl: move(&op, word_end(text, cursor), shift)
                case: move(&op, next_boundary(text, cursor), shift)
            }
        case .Home, .Up:
            move(&op, 0, shift)
        case .End, .Down:
            move(&op, len(text), shift)
        case .Backspace:
            if has_selection {
                remove(&op, lo, hi)
            } else if cursor > 0 {
                remove(&op, ctrl ? word_start(text, cursor) : prev_boundary(text, cursor), cursor)
            }
        case .Delete:
            if has_selection {
                remove(&op, lo, hi)
            } else if cursor < len(text) {
                remove(&op, cursor, ctrl ? word_end(text, cursor) : next_boundary(text, cursor))
            }
        case .A:
            if !ctrl do return op, false
            op.mark, op.cursor = 0, len(text)
        case .C:
            if !ctrl do return op, false
            op.copy = has_selection
            op.replace_start, op.replace_end = lo, hi
        case .X:
            if !ctrl do return op, false
            if has_selection {
                remove(&op, lo, hi)
                op.copy = true
            }
        case .V:
            if !ctrl do return op, false
            remove(&op, lo, hi)
            op.paste = true
        case:
            return op, false
    }
    return op, true
}

// Replaces op's range in buffer[:length^] with insert, dropping whatever doesn't fit.
// Returns the cursor after the inserted text.
text_op_apply :: proc(op: Text_Op, insert: string, buffer: []u8, length: ^int) -> int {
    if !op.edits do return op.cursor
    start := clamp(op.replace_start, 0, length^)
    end := clamp(op.replace_end, start, length^)
    insert := insert
    room := len(buffer) - (length^ - (end - start))
    if len(insert) > room {
        n := max(room, 0)
        // never cut a utf-8 sequence in half
        for n > 0 && insert[n] & 0xC0 == 0x80 do n -= 1
        insert = insert[:n]
    }
    tail := length^ - end
    // copy is a memmove, so shifting the tail within the buffer is safe
    copy(buffer[start + len(insert):], buffer[end:length^])
    copy(buffer[start:], insert)
    length^ = start + len(insert) + tail
    return start + len(insert)
}
