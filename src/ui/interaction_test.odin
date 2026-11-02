package ui

import pl "../platform"
import "core:testing"

// These tests run without a window or renderer. The UI currently has global
// state, so the scenarios are deliberately kept in one serial test.
Interaction_Result :: struct {
    under_clicked, item_clicked: bool,
    title, menu, under, item:    ^Box,
}

interaction_frame :: proc(open: ^bool, menu_first: bool, events: pl.Event_List = {}) -> Interaction_Result {
    result: Interaction_Result
    fixed := Box_Desc {
        h_size = {type = .FIXED, value = 40},
        v_size = {type = .FIXED, value = 20},
    }
    if build(events) {
        if !menu_first {
            result.under_clicked = button("Under", fixed)
        }
        if dropdown("Menu", open, fixed) {
            result.item_clicked = button("Item", fixed)
        }
        if menu_first {
            result.under_clicked = button("Under", fixed)
        }
        root_key := state.root.key
        result.title = state.tree[hash_key("Menu", root_key)]
        result.under = state.tree[hash_key("Under", root_key)]
        if result.title != nil {
            result.menu = state.tree[hash_key("dropdown__Menu", result.title.key)]
        }
        if result.menu != nil {
            result.item = state.tree[hash_key("Item", result.menu.key)]
        }
    }
    return result
}

seed_overlap :: proc(result: Interaction_Result, item_overlaps := true) -> bool {
    if result.title == nil || result.under == nil || result.menu == nil || result.item == nil {
        return false
    }
    result.title.pos, result.title.dimensions = {10, 0}, {40, 20}
    result.under.pos, result.under.dimensions = {10, 30}, {40, 20}
    result.menu.pos, result.menu.dimensions = {10, 30}, {50, 50}
    result.item.pos, result.item.dimensions = {10, 30}, {40, 20}
    if !item_overlaps {
        result.item.pos = {10, 55}
    }
    return true
}

@(test)
interaction_and_dropdown_regressions :: proc(t: ^testing.T) {
    // A menu must own input over an underlying widget regardless of build order.
    orders := [2]bool{false, true}
    for menu_first in orders {
        init()
        state.mouse_pos = {-100, -100}
        open := true
        previous := interaction_frame(&open, menu_first)
        if !testing.expect(t, seed_overlap(previous), "expected open dropdown fixture boxes") {
            deinit()
            state = {}
            return
        }
        move := pl.Event {
            type = .MOUSE_MOVE,
            pos  = {15, 35},
        }
        press := pl.Event {
            type = .MOUSE_BTN_PRESSED,
            key  = .BTN_LEFT,
            pos  = {15, 35},
        }
        move.next, press.prev = &press, &move
        actual := interaction_frame(&open, menu_first, {head = &move, tail = &press, length = 2})
        testing.expectf(
            t,
            actual.item_clicked && !actual.under_clicked,
            "overlapping click: menu_first=%v, item=%v, underlying=%v",
            menu_first,
            actual.item_clicked,
            actual.under_clicked,
        )
        testing.expect(t, actual.menu == previous.menu, "named menu should be reused between frames")
        deinit()
        state = {}
    }

    // The menu background must block the widget below even between its items.
    init()
    state.mouse_pos = {-100, -100}
    open := true
    previous := interaction_frame(&open, false)
    if !testing.expect(t, seed_overlap(previous, false), "expected open dropdown fixture boxes") {
        deinit()
        state = {}
        return
    }
    move := pl.Event {
        type = .MOUSE_MOVE,
        pos  = {15, 35},
    }
    press := pl.Event {
        type = .MOUSE_BTN_PRESSED,
        key  = .BTN_LEFT,
        pos  = {15, 35},
    }
    move.next, press.prev = &press, &move
    actual := interaction_frame(&open, false, {head = &move, tail = &press, length = 2})
    testing.expect(t, !actual.under_clicked && !actual.item_clicked, "menu background should block clicks below it")
    deinit()
    state = {}

    // A press and release delivered in the same frame should still be seen.
    init()
    state.mouse_pos = {-100, -100}
    open = true
    previous = interaction_frame(&open, true)
    if !testing.expect(t, seed_overlap(previous), "expected open dropdown fixture boxes") {
        deinit()
        state = {}
        return
    }
    move = {
        type = .MOUSE_MOVE,
        pos  = {15, 35},
    }
    press = {
        type = .MOUSE_BTN_PRESSED,
        key  = .BTN_LEFT,
        pos  = {15, 35},
    }
    release := pl.Event {
        type = .MOUSE_BTN_RELEASED,
        key  = .BTN_LEFT,
        pos  = {15, 35},
    }
    move.next, press.prev, press.next, release.prev = &press, &move, &release, &press
    actual = interaction_frame(&open, true, {head = &move, tail = &release, length = 3})
    testing.expect(t, actual.item_clicked, "a press and release in one frame should activate the item")
    deinit()
    state = {}

    // Opening, holding, releasing, and closing the title across frames.
    init()
    state.mouse_pos = {-100, -100}
    open = false
    previous = interaction_frame(&open, true)
    if !testing.expect(t, previous.title != nil, "expected dropdown title") {
        deinit()
        state = {}
        return
    }
    previous.title.pos, previous.title.dimensions = {10, 10}, {40, 20}
    move = {
        type = .MOUSE_MOVE,
        pos  = {15, 15},
    }
    press = {
        type = .MOUSE_BTN_PRESSED,
        key  = .BTN_LEFT,
        pos  = {15, 15},
    }
    move.next, press.prev = &press, &move
    actual = interaction_frame(&open, true, {head = &move, tail = &press, length = 2})
    if !testing.expect(t, open && actual.menu != nil, "pressing the title should open the menu") {
        deinit()
        state = {}
        return
    }
    menu_key := actual.menu.key
    held := interaction_frame(&open, true)
    testing.expect(t, open && held.menu == actual.menu, "holding the button should not toggle the title again")
    release = {
        type = .MOUSE_BTN_RELEASED,
        key  = .BTN_LEFT,
        pos  = {15, 15},
    }
    interaction_frame(&open, true, {head = &release, tail = &release, length = 1})
    press = {
        type = .MOUSE_BTN_PRESSED,
        key  = .BTN_LEFT,
        pos  = {15, 15},
    }
    interaction_frame(&open, true, {head = &press, tail = &press, length = 1})
    testing.expect(t, !open, "a second click on the title should close the menu")
    release = {
        type = .MOUSE_BTN_RELEASED,
        key  = .BTN_LEFT,
        pos  = {15, 15},
    }
    interaction_frame(&open, true, {head = &release, tail = &release, length = 1})
    press = {
        type = .MOUSE_BTN_PRESSED,
        key  = .BTN_LEFT,
        pos  = {15, 15},
    }
    actual = interaction_frame(&open, true, {head = &press, tail = &press, length = 1})
    testing.expect(
        t,
        open && actual.menu != nil && actual.menu.key == menu_key,
        "reopening should reuse the same menu identity",
    )
    deinit()
    state = {}

    // Right clicks must not activate a left-click button.
    init()
    state.mouse_pos = {-100, -100}
    open = true
    previous = interaction_frame(&open, true)
    if !testing.expect(t, seed_overlap(previous), "expected open dropdown fixture boxes") {
        deinit()
        state = {}
        return
    }
    move = {
        type = .MOUSE_MOVE,
        pos  = {15, 35},
    }
    press = {
        type = .MOUSE_BTN_PRESSED,
        key  = .BTN_RIGHT,
        pos  = {15, 35},
    }
    move.next, press.prev = &press, &move
    actual = interaction_frame(&open, true, {head = &move, tail = &press, length = 2})
    testing.expect(t, !actual.item_clicked && !actual.under_clicked, "right click should not activate a button")
    deinit()
    state = {}

    // Hovering alone and dragging into an item must not activate it.
    init()
    state.mouse_pos = {-100, -100}
    open = true
    previous = interaction_frame(&open, true)
    if !testing.expect(t, seed_overlap(previous), "expected open dropdown fixture boxes") {
        deinit()
        state = {}
        return
    }
    move = {
        type = .MOUSE_MOVE,
        pos  = {15, 35},
    }
    actual = interaction_frame(&open, true, {head = &move, tail = &move, length = 1})
    testing.expect(
        t,
        actual.item != nil && actual.item.hovered && !actual.item_clicked,
        "hovering should highlight without clicking",
    )
    move = {
        type = .MOUSE_MOVE,
        pos  = {200, 200},
    }
    press = {
        type = .MOUSE_BTN_PRESSED,
        key  = .BTN_LEFT,
        pos  = {200, 200},
    }
    move.next, press.prev = &press, &move
    interaction_frame(&open, true, {head = &move, tail = &press, length = 2})
    move = {
        type = .MOUSE_MOVE,
        pos  = {15, 35},
    }
    actual = interaction_frame(&open, true, {head = &move, tail = &move, length = 1})
    testing.expect(t, !actual.item_clicked, "dragging into an item should not create a click")
    deinit()
    state = {}

    init()
    open = false
    move = {
        type = .MOUSE_MOVE,
        pos  = {100, 100},
    }
    interaction_frame(&open, true, {head = &move, tail = &move, length = 1})
    testing.expect(t, state.events.length == 0, "handled final mouse event should be removed from the event list")
    deinit()
    state = {}

    bounds := Rect {
        pos   = {10, 20},
        dimen = {40, 20},
    }
    testing.expect(t, mouse_collision({10, 20}, bounds), "top-left edge should be inside")
    testing.expect(t, mouse_collision({49, 39}, bounds), "last interior pixel should be inside")
    testing.expect(t, !mouse_collision({50, 30}, bounds), "right edge should be outside")
    testing.expect(t, !mouse_collision({20, 40}, bounds), "bottom edge should be outside")

    // Floating children must be drawn above normal siblings even if the
    // floating branch appears first in the tree.
    init()
    root := Box{}
    floating := Box {
        parent = &root,
        flags  = {.FLOATING},
    }
    overlay := Box {
        parent     = &floating,
        flags      = {.DRAW_RECT},
        color      = {1, 0, 0},
        dimensions = {10, 10},
    }
    background := Box {
        parent     = &root,
        flags      = {.DRAW_RECT},
        color      = {0, 0, 1},
        dimensions = {10, 10},
    }
    root.first, floating.first, floating.next = &floating, &overlay, &background
    pre_order_traversal_first_pass(&root)
    pre_order_traversal_second_pass(&root)
    if testing.expect(t, len(state.draw_commands) == 2, "both background and overlay should be drawn") {
        testing.expect(
            t,
            state.draw_commands[0].color == background.color && state.draw_commands[1].color == overlay.color,
            "floating content should draw over normal content",
        )
    }
    deinit()
    state = {}

    // Check the rectangle actually produced for the floating box, not just
    // the positions of its children.
    parent := Box {
        children_layout_axis = .VERTICAL,
        pos                  = {20, 10},
    }
    title := Box {
        parent               = &parent,
        dimensions           = {40, 20},
        children_layout_axis = .VERTICAL,
    }
    menu := Box {
        parent = &title,
        flags = {.FLOATING},
        children_layout_axis = .VERTICAL,
        h_size = {type = .BASED_ON_CHILDREN_SUM},
        v_size = {type = .BASED_ON_CHILDREN_SUM},
    }
    item := Box {
        parent     = &menu,
        dimensions = {40, 20},
    }
    parent.first, title.first, menu.first = &title, &menu, &item
    calc_size_downwards_dependent(&parent)
    calc_positions(parent.first)
    testing.expect(
        t,
        menu.pos.x == title.pos.x && menu.pos.y == title.pos.y + title.dimensions.y,
        "menu rectangle should start directly below the title",
    )
    testing.expect(
        t,
        item.pos.x >= menu.pos.x &&
        item.pos.y >= menu.pos.y &&
        item.pos.x + item.dimensions.x <= menu.pos.x + menu.dimensions.x &&
        item.pos.y + item.dimensions.y <= menu.pos.y + menu.dimensions.y,
        "menu rectangle should contain its item",
    )
}
