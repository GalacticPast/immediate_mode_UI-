package ui

import "core:testing"

fake_measure :: proc(text: string, size: f32) -> Vec2 { return {f32(len(text))*size*0.5, size} }

@(test)
layout_span_and_fill :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {500, 120}, nil, 0.016)
    begin_container(&s, "row", .X, fill(), fill(), {}, 10)
    column := begin_container(&s, "column", .Y, fill(), fill(), {}, 5)
    for _ in 0 ..< 3 {
        b := box(&s, "", {})
        b.style.height = px(30)
    }
    end_container(&s)
    preview := color_preview(&s, "preview", {1, 0, 0}, px(100), fill())
    end_container(&s)
    end_build(&s)
    testing.expect_value(t, column.rect.size, Vec2{390, 120})
    testing.expect_value(t, preview.rect, Rect{{400, 0}, {100, 120}})
    testing.expect_value(t, column.last.rect.pos.y, f32(70))
}

@(test)
weighted_fill_and_children_measure :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {400, 200}, nil, 0.016)
    row := begin_container(&s, "row", .X, fill(), children(), {10, 5}, 10)
    a := color_preview(&s, "a", {}, fill(1), px(40))
    b := color_preview(&s, "b", {}, fill(2), px(30))
    c := color_preview(&s, "c", {}, fill(1), px(20))
    end_container(&s)
    end_build(&s)
    testing.expect_value(t, row.rect.size.y, f32(50))
    testing.expect_value(t, a.rect.size.x, f32(90))
    testing.expect_value(t, b.rect.size.x, f32(180))
    testing.expect_value(t, c.rect.pos.x, f32(300))
}

@(test)
key_identity_pruning_and_owned_text :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {200, 100}, nil, 0.016)
    text_bytes := [3]u8{'O', 'n', 'e'}
    b := box(&s, "One###stable", {.Text})
    set_text(&s, b, string(text_bytes[:]))
    text_bytes[0] = 'X'
    key := b.key
    end_build(&s)
    testing.expect_value(t, b.text, "One")
    begin_build(&s, {200, 100}, nil, 0.016)
    again := box(&s, "Two###stable", {.Text})
    testing.expect_value(t, again, b)
    testing.expect_value(t, again.key, key)
    testing.expect_value(t, again.text, "Two")
    end_build(&s)
    s.active, s.focus = key, key
    begin_build(&s, {200, 100}, nil, 0.016)
    end_build(&s)
    testing.expect(t, s.cache[key] == nil)
    testing.expect_value(t, s.active, Key(0))
    testing.expect_value(t, s.focus, Key(0))
    testing.expect_value(t, len(s.boxes), 1) // root only
}

build_button_fixture :: proc(s: ^State) -> ^Box {
    b := box(s, "button", {.Clickable, .Text})
    b.style.width, b.style.height = px(100), px(30)
    return b
}

@(test)
click_batch_capture_and_focus :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {200, 100}, nil, 0.016)
    build_button_fixture(&s)
    end_build(&s)
    events := []Event{{kind = .Press, pos = {10, 10}}, {kind = .Release, pos = {10, 10}}}
    begin_build(&s, {200, 100}, events, 0.016)
    b := build_button_fixture(&s)
    testing.expect(t, b.signal.pressed && b.signal.released && b.signal.clicked)
    testing.expect_value(t, s.focus, b.key)
    end_build(&s)
    events = []Event{{kind = .Press, pos = {10, 10}}, {kind = .Move, pos = {190, 80}}, {kind = .Release, pos = {190, 80}}}
    begin_build(&s, {200, 100}, events, 0.016)
    b = build_button_fixture(&s)
    testing.expect(t, b.signal.released && !b.signal.clicked)
    testing.expect_value(t, b.signal.drag_pos, Vec2{190, 80})
    end_build(&s)
    events = []Event{{kind = .Key_Press, key = .Enter}}
    begin_build(&s, {200, 100}, events, 0.016)
    b = build_button_fixture(&s)
    testing.expect(t, b.signal.clicked)
    end_build(&s)
}

@(test)
slider_mouse_keyboard_and_disabled :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    value: f32
    begin_build(&s, {200, 100}, nil, 0.016)
    slider(&s, "gain", &value, 0, 1)
    end_build(&s)
    events := []Event{{kind = .Press, pos = {100, 10}}, {kind = .Release, pos = {100, 10}}}
    begin_build(&s, {200, 100}, events, 0.016)
    slider(&s, "gain", &value, 0, 1)
    end_build(&s)
    testing.expect_value(t, value, f32(0.5))
    events = []Event{{kind = .Key_Press, key = .End}}
    begin_build(&s, {200, 100}, events, 0.016)
    slider(&s, "gain", &value, 0, 1)
    end_build(&s)
    testing.expect_value(t, value, f32(1))
    events = []Event{{kind = .Key_Press, key = .Enter}}
    begin_build(&s, {200, 100}, events, 0.016)
    sig := button(&s, "gain", true)
    testing.expect(t, !sig.clicked)
    end_build(&s)
    testing.expect_value(t, s.focus, Key(0))
}

build_scroll_fixture :: proc(s: ^State, overlay: bool) -> ^Box {
    panel := begin_container(s, "scroll", .Y, fill(), fill(), {}, 0, {.Scroll, .Clip})
    for _ in 0 ..< 10 {
        b := box(s, "", {.Background})
        b.style.height = px(30)
    }
    end_container(s)
    if overlay {
        b := box(s, "overlay", {.Floating, .Clickable, .Background})
        b.style.width, b.style.height = px(200), px(100)
    }
    return panel
}

@(test)
scroll_clipping_and_overlay_occlusion :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {200, 100}, nil, 0.016)
    build_scroll_fixture(&s, false)
    end_build(&s)
    events := []Event{{kind = .Scroll, pos = {20, 20}, scroll = 60}}
    begin_build(&s, {200, 100}, events, 0.016)
    panel := build_scroll_fixture(&s, true)
    end_build(&s)
    testing.expect_value(t, panel.scroll_y, f32(60))
    testing.expect_value(t, panel.first.rect.pos.y, f32(-60))
    testing.expect_value(t, panel.first.clip.size.y, f32(0))
    begin_build(&s, {200, 100}, events, 0.016)
    panel = build_scroll_fixture(&s, true)
    end_build(&s)
    testing.expect_value(t, panel.scroll_y, f32(60))
}

@(test)
shrinking_obeys_strictness :: proc(t: ^testing.T) {
    s: State
    init(&s, fake_measure)
    defer deinit(&s)
    begin_build(&s, {100, 50}, nil, 0.016)
    begin_container(&s, "row", .X, fill(), fill(), {}, 0)
    a := color_preview(&s, "a", {}, px(80, 1), fill())
    b := color_preview(&s, "b", {}, px(80, 0), fill())
    end_container(&s)
    end_build(&s)
    testing.expect_value(t, a.rect.size.x, f32(80))
    testing.expect_value(t, b.rect.size.x, f32(20))
}
