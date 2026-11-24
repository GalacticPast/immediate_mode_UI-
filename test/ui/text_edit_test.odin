package ui

import pl "../platform"
import "../text"
import "core:sync"
import "core:testing"

@(test)
editor_uses_grapheme_boundaries_for_insertion_and_deletion :: proc(t: ^testing.T) {
    value := make([dynamic]u8)
    defer delete(value)
    append(&value, "Ae\u0301👩‍💻Z")
    cursor := len(value)
    left := pl.Event{type = .KEY_PRESS, payload = pl.Key_Type.LEFT}
    back := pl.Event{type = .KEY_PRESS, payload = pl.Key_Type.BACKSPACE}
    edit_input(&value, &cursor, &left)
    testing.expect(t, edit_input(&value, &cursor, &back))
    testing.expect_value(t, string(value[:]), "Ae\u0301Z")
    edit_input(&value, &cursor, &left)
    testing.expect_value(t, cursor, 1)
    del := pl.Event{type = .KEY_PRESS, payload = pl.Key_Type.DELETE}
    edit_input(&value, &cursor, &del)
    insert := pl.Event{type = .TEXT_INPUT, payload = rune('ñ')}
    edit_input(&value, &cursor, &insert)
    testing.expect_value(t, string(value[:]), "AñZ")
    testing.expect_value(t, cursor, len("Añ"))
    newline := pl.Event{type = .TEXT_INPUT, payload = rune('\n')}
    testing.expect(t, !edit_input(&value, &cursor, &newline))
}

@(test)
editor_clicks_and_text_follow_event_order_and_draw_the_caret :: proc(t: ^testing.T) {
    sync.mutex_lock(&clipping_test_mutex)
    defer sync.mutex_unlock(&clipping_test_mutex)
    state = {}
    init()
    defer {
        deinit()
        state = {}
    }
    text.init()
    defer text.deinit()
    font := text.load_font(#config(IMUI_TEST_FONT, "assets/font/Archivo-Regular.ttf"))

    a, b: [dynamic]u8
    defer delete(a)
    defer delete(b)

    frame :: proc(events: []pl.Event, a, b: ^[dynamic]u8) -> []Draw_Command {
        list: pl.Event_List
        for &e, i in events {
            if i == 0 do list.head = &e
            e.prev = list.tail
            if list.tail != nil do list.tail.next = &e
            list.tail = &e
            list.length += 1
        }
        if build(list) {
            // The headless platform has no window. Give layout the demo dimensions.
            state.root.h_size.value = 600
            state.root.v_size.value = 100
            text_edit("first", a)
            text_edit("second", b)
        }
        return build_draw_commands()
    }

    frame(nil, &a, &b)
    events := []pl.Event{
        {type = .MOUSE_MOVE, pos = {10, 10}},
        {type = .MOUSE_BTN_PRESSED, payload = pl.Key_Type.BTN_LEFT},
        {type = .MOUSE_BTN_RELEASED, payload = pl.Key_Type.BTN_LEFT},
        {type = .KEY_PRESS, payload = pl.Key_Type.D},
        {type = .TEXT_INPUT, payload = rune('d')},
        {type = .MOUSE_MOVE, pos = {260, 10}},
        {type = .MOUSE_BTN_PRESSED, payload = pl.Key_Type.BTN_LEFT},
        {type = .MOUSE_BTN_RELEASED, payload = pl.Key_Type.BTN_LEFT},
        {type = .TEXT_INPUT, payload = rune('é')},
    }
    commands := frame(events, &a, &b)
    testing.expect_value(t, string(a[:]), "d")
    testing.expect_value(t, string(b[:]), "é")
    testing.expect(t, !state.debug)
    if testing.expect_value(t, len(commands), 5) {
        line := commands[3].line
        if testing.expect_value(t, len(line.glyphs), 1) {
            glyph := font.data[line.glyphs[0].id]
            testing.expect(t, glyph.curves_indicies.y > glyph.curves_indicies.x)
            testing.expect_value(t, line.x[1], glyph.advance)
        }
        caret := commands[4]
        testing.expect_value(t, caret.rect.pos.x, commands[3].rect.pos.x + line.width * state.font_size)
        testing.expect(t, mouse_collision({i32(caret.rect.pos.x), 10}, caret.clip))
    }
    frame([]pl.Event{
        {type = .KEY_PRESS, payload = pl.Key_Type.HOME},
        {type = .TEXT_INPUT, payload = rune('!')},
        {type = .KEY_PRESS, payload = pl.Key_Type.ENTER},
        {type = .TEXT_INPUT, payload = rune('x')},
    }, &a, &b)
    testing.expect_value(t, string(b[:]), "!é")
    testing.expect_value(t, state.focus_key, u64(0))

    // Re-enter the populated field at its right edge, then cross the viewport.
    append(&b, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
    commands = frame([]pl.Event{
        {type = .MOUSE_MOVE, pos = {480, 10}},
        {type = .MOUSE_BTN_PRESSED, payload = pl.Key_Type.BTN_LEFT},
        {type = .MOUSE_BTN_RELEASED, payload = pl.Key_Type.BTN_LEFT},
        {type = .KEY_PRESS, payload = pl.Key_Type.END},
        {type = .KEY_REPEAT, payload = pl.Key_Type.BACKSPACE},
    }, &a, &b)
    testing.expect_value(t, b[len(b) - 1], u8('Y'))
    if testing.expect_value(t, len(commands), 5) {
        testing.expect(t, commands[3].rect.pos.x < commands[3].clip.pos.x, "long text scrolls left")
        caret := commands[4]
        testing.expect(t, mouse_collision({i32(caret.rect.pos.x), 10}, caret.clip))
    }
    frame([]pl.Event{
        {type = .MOUSE_MOVE, pos = {550, 70}},
        {type = .MOUSE_BTN_PRESSED, payload = pl.Key_Type.BTN_LEFT},
        {type = .TEXT_INPUT, payload = rune('x')},
    }, &a, &b)
    testing.expect_value(t, b[len(b) - 1], u8('Y'))
    testing.expect_value(t, state.focus_key, u64(0))
}
