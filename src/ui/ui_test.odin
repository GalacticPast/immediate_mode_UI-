package ui

import "core:testing"

// Every character is half the font size wide, one font size tall.
fake_measure :: proc(text: string, size: f32) -> Vec2 { return {f32(len(text)) * size * 0.5, size} }

DT :: 1.0 / 60.0

click_events :: proc(p: Vec2, button := Mouse_Button.Left) -> [3]Event {
    return {{kind = .Move, pos = p}, {kind = .Press, pos = p, button = button}, {kind = .Release, pos = p, button = button}}
}
center :: proc(b: ^Box) -> Vec2 { return b.rect.pos + b.rect.size * 0.5 }

@(test)
fill_shares_leftover_and_strict_sizes_survive :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {500, 100}, nil, DT)
    row_begin(&s, fill(), px(40), "row")
    set_next_pref_width(&s, px(100))
    fixed := build_box(&s, {}, "fixed")
    a := build_box(&s, {}, "a")
    b := build_box(&s, {}, "b")
    row_end(&s)
    end_build(&s)
    testing.expect_value(t, fixed.rect.size.x, f32(100))
    testing.expect_value(t, a.rect.size.x, f32(200))
    testing.expect_value(t, b.rect, Rect{{300, 0}, {200, 26}})
}

@(test)
children_sum_and_text_sizes :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {400, 400}, nil, DT)
    col := column_begin(&s, children_sum(), children_sum(), "col")
    for name in ([]string{"x", "yy", "zzz"}) {
        set_next_pref_size(&s, text_dim(), px(30))
        build_box(&s, {.Draw_Text}, name)
    }
    column_end(&s)
    end_build(&s)
    // widest text: 3 chars * 7 px + 2 * 6 px text padding
    testing.expect_value(t, col.rect.size, Vec2{33, 90})
    testing.expect_value(t, col.last.rect.pos.y, f32(60))
}

@(test)
set_next_applies_to_one_box :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {300, 300}, nil, DT)
    set_next_pref_height(&s, px(50))
    set_next_palette(&s, s.theme.tooltip)
    first := build_box(&s, {}, "first")
    second := build_box(&s, {}, "second")
    end_build(&s)
    testing.expect_value(t, first.rect.size.y, f32(50))
    testing.expect_value(t, second.rect.size.y, s.theme.row_height)
    testing.expect_value(t, first.palette, s.theme.tooltip)
    testing.expect_value(t, second.palette, s.theme.base)
}

@(test)
keys_survive_relabeling_and_duplicates_turn_transient :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {200, 100}, nil, DT)
    one := build_box(&s, {.Draw_Text}, "One###stable")
    dup := build_box(&s, {}, "Two###stable")
    end_build(&s)
    testing.expect_value(t, one.text, "One")
    testing.expect(t, one.key != 0)
    testing.expect_value(t, dup.key, Key(0))

    begin_build(&s, {200, 100}, nil, DT)
    again := build_box(&s, {.Draw_Text}, "Three###stable")
    end_build(&s)
    testing.expect(t, again == one, "the same key reuses the same box")
    testing.expect_value(t, again.text, "Three")
}

@(test)
click_routes_through_the_previous_layout :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {300, 200}, nil, DT)
    b := button(&s, "go").box
    end_build(&s)

    events := click_events(center(b))
    begin_build(&s, {300, 200}, events[:], DT)
    sig := button(&s, "go")
    end_build(&s)
    testing.expect(t, clicked(sig))
    testing.expect(t, .Left_Pressed in sig.flags && .Left_Released in sig.flags)

    // pressing then releasing elsewhere is not a click
    begin_build(&s, {300, 200}, []Event{{kind = .Press, pos = center(b)}, {kind = .Release, pos = {299, 199}}}, DT)
    sig = button(&s, "go")
    end_build(&s)
    testing.expect(t, released(sig) && !clicked(sig))
}

@(test)
windows_occlude_the_main_ui :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    build :: proc(s: ^State, events: []Event) -> (under, over: Signal) {
        begin_build(s, {400, 300}, events, DT)
        under = button(s, "under")
        if window(s, "win", {position = {0, 0}, size = {200, 200}, options = {.No_Title_Bar}}) {
            over = button(s, "over")
        }
        end_build(s)
        return
    }
    _, over := build(&s, nil)
    events := click_events(center(over.box))
    under, over2 := build(&s, events[:])
    testing.expect(t, clicked(over2), "the button in the window gets the click")
    testing.expect(t, !clicked(under), "the button beneath the window does not")
}

@(test)
scrolling_is_clamped_to_the_content :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    build :: proc(s: ^State, events: []Event) {
        begin_build(s, {200, 100}, events, DT)
        if scroll_region(s, "list") {
            for i in 0 ..< 10 {
                set_next_pref_height(s, px(30))
                build_box(s, {.Draw_Background}, fmt_index(i))
            }
        }
        end_build(s)
    }
    build(&s, nil)
    build(&s, nil)
    view := box_from_key(&s, key_from_string(key_from_string(key_from_string(key_from_string(0, "###root"), "list"), "###row"), "###view"))
    testing.expect(t, view != nil)
    if view == nil do return
    testing.expect_value(t, view.view_bounds.y, f32(300))
    build(&s, []Event{{kind = .Scroll, pos = {50, 50}, scroll = {0, 1000}}})
    testing.expect_value(t, view.view_off_target.y, f32(200))
}

@(private = "file")
fmt_index :: proc(i: int) -> string {
    names := [?]string{"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"}
    return names[i]
}

@(test)
text_ops :: proc(t: ^testing.T) {
    buffer: [8]u8
    length := 0
    type :: proc(text: string, cursor, mark: int, e: Event, buffer: []u8, length: ^int) -> (int, int) {
        op, ok := text_op_from_event(text, cursor, mark, e)
        assert(ok)
        insert := ""
        bytes: [1]u8
        if op.insert_rune != 0 {
            bytes[0] = u8(op.insert_rune)
            insert = string(bytes[:])
        }
        if !op.edits do return op.cursor, op.mark
        end := text_op_apply(op, insert, buffer, length)
        return end, end
    }
    cursor, mark := 0, 0
    for c in "hello wo" {
        cursor, mark = type(string(buffer[:length]), cursor, mark, {kind = .Text, text = c}, buffer[:], &length)
    }
    testing.expect_value(t, string(buffer[:length]), "hello wo")
    // full buffer: the extra character is dropped
    cursor, mark = type(string(buffer[:length]), cursor, mark, {kind = .Text, text = 'r'}, buffer[:], &length)
    testing.expect_value(t, string(buffer[:length]), "hello wo")
    cursor, mark = type(string(buffer[:length]), cursor, mark, {kind = .Key_Press, key = .Backspace, mods = {.Ctrl}}, buffer[:], &length)
    testing.expect_value(t, string(buffer[:length]), "hello ")
    // select everything and type over it
    cursor, mark = type(string(buffer[:length]), cursor, mark, {kind = .Key_Press, key = .A, mods = {.Ctrl}}, buffer[:], &length)
    testing.expect_value(t, [2]int{mark, cursor}, [2]int{0, 6})
    cursor, mark = type(string(buffer[:length]), cursor, mark, {kind = .Text, text = 'X'}, buffer[:], &length)
    testing.expect_value(t, string(buffer[:length]), "X")
    cursor, mark = type(string(buffer[:length]), cursor, mark, {kind = .Key_Press, key = .Home, mods = {.Shift}}, buffer[:], &length)
    testing.expect_value(t, [2]int{cursor, mark}, [2]int{0, 1})
}

@(test)
line_edit_types_and_commits :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    buffer: [32]u8
    length := 0
    begin_build(&s, {300, 100}, nil, DT)
    b := line_edit(&s, "name", buffer[:], &length).box
    end_build(&s)

    events := click_events(center(b))
    begin_build(&s, {300, 100}, events[:], DT)
    line_edit(&s, "name", buffer[:], &length)
    end_build(&s)
    testing.expect_value(t, s.focus_active, b.key)

    typing := []Event{{kind = .Text, text = 'h'}, {kind = .Text, text = 'i'}, {kind = .Key_Press, key = .Enter}}
    begin_build(&s, {300, 100}, typing, DT)
    sig := line_edit(&s, "name", buffer[:], &length)
    end_build(&s)
    testing.expect_value(t, string(buffer[:length]), "hi")
    testing.expect(t, committed(sig))
    testing.expect_value(t, s.focus_active, Key(0))
}

@(test)
ctx_menu_closes_on_outside_press_and_escape :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    key := key_from_string(0, "menu")
    build :: proc(s: ^State, key: Key, events: []Event) -> (item: Signal) {
        begin_build(s, {400, 400}, events, DT)
        if ctx_menu(s, key) do item = menu_item(s, "Copy")
        end_build(s)
        return
    }
    begin_build(&s, {400, 400}, nil, DT)
    ctx_menu_open(&s, key, 0, {10, 10})
    end_build(&s)
    item := build(&s, key, nil)
    testing.expect(t, item.box != nil, "an open menu is built")
    testing.expect(t, item.box.rect.pos.x >= 10)

    build(&s, key, []Event{{kind = .Press, pos = {390, 390}}})
    testing.expect(t, !ctx_menu_is_open(&s, key), "pressing outside closes it")

    ctx_menu_open(&s, key)
    build(&s, key, nil)
    build(&s, key, []Event{{kind = .Key_Press, key = .Escape}})
    testing.expect(t, !ctx_menu_is_open(&s, key), "escape closes it")
}

@(test)
tooltip_waits_for_the_pointer_to_rest :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    build :: proc(s: ^State, events: []Event) -> (shown: bool, b: ^Box) {
        begin_build(s, {300, 300}, events, 0.1)
        sig := button(s, "hover me")
        if tooltip(s, sig) {
            label(s, "tip")
            shown = true
        }
        end_build(s)
        return shown, sig.box
    }
    _, b := build(&s, nil)
    shown: bool
    shown, _ = build(&s, []Event{{kind = .Move, pos = center(b)}})
    testing.expect(t, !shown, "not right away")
    for _ in 0 ..< 6 do shown, _ = build(&s, nil)
    testing.expect(t, shown, "after the delay")
    testing.expect(t, s.tooltip_root.first != nil && s.tooltip_root.first.rect.size.x > 0)
}

@(test)
disabled_scope_blocks_input :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    build :: proc(s: ^State, events: []Event) -> Signal {
        begin_build(s, {300, 100}, events, DT)
        sig: Signal
        if disabled(s) do sig = button(s, "off")
        end_build(s)
        return sig
    }
    sig := build(&s, nil)
    events := click_events(center(sig.box))
    sig = build(&s, events[:])
    testing.expect(t, .Disabled in sig.box.flags)
    testing.expect(t, !clicked(sig))
}
