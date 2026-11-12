package ui

import "core:sync"
import "core:testing"

@(test)
pressing_visible_part_of_widget_updates_interaction_state :: proc(t: ^testing.T) {
    // @test: The Linux platform leaves cursor updates as no-ops before startup.
    when ODIN_OS == .Linux {
        sync.mutex_lock(&clipping_test_mutex)
        defer sync.mutex_unlock(&clipping_test_mutex)
        state = {}
        defer { state = {} }

        parent := Box{pos = {0, 0}, dimensions = {100, 100}, flags = {.CLIP}}
        button := Box{key = 123, parent = &parent, pos = {80, 10}, dimensions = {40, 20}, flags = {.PRESSABLE}}
        state.mouse_pos = {90, 20}
        state.mouse_btn_press = .BTN_LEFT
        state.mouse_btn_held = .BTN_LEFT
        check_action(&button)

        testing.expect(t, button.hovered && button.clicked, "a press inside the visible area should interact")
        testing.expect_value(t, state.hot_widget_key, button.key)
        testing.expect_value(t, state.active_widget_key, button.key)

        state.mouse_btn_press = .NONE
        state.mouse_btn_held = .NONE
        check_action(&button)
        testing.expect_value(t, state.active_widget_key, u64(0))
    }
}

@(test)
pressing_clipped_part_of_widget_does_not_activate_it :: proc(t: ^testing.T) {
    sync.mutex_lock(&clipping_test_mutex)
    defer sync.mutex_unlock(&clipping_test_mutex)
    state = {}
    defer { state = {} }

    parent := Box{pos = {0, 0}, dimensions = {100, 100}, flags = {.CLIP}}
    button := Box{key = 123, parent = &parent, pos = {80, 10}, dimensions = {40, 20}, flags = {.PRESSABLE}}
    state.mouse_pos = {110, 20}
    state.mouse_btn_press = .BTN_LEFT
    state.mouse_btn_held = .BTN_LEFT
    check_action(&button)

    testing.expect(t, !button.hovered && !button.clicked)
    testing.expect_value(t, state.hot_widget_key, u64(0))
    testing.expect_value(t, state.active_widget_key, u64(0))
}
