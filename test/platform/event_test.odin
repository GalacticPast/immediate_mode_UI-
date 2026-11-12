package platform

import "core:testing"

@(test)
event_list_remove_middle_head_and_tail :: proc(t: ^testing.T) {
    list: Event_List
    first := Event{type = .MOUSE_MOVE}
    middle := Event{type = .MOUSE_BTN_PRESSED}
    last := Event{type = .MOUSE_BTN_RELEASED}
    insert_ll(&list, &first)
    insert_ll(&list, &middle)
    insert_ll(&list, &last)

    testing.expect_value(t, list.length, u32(3))
    testing.expect(t, list.head == &first && list.tail == &last)
    eat_event(&list, &middle)
    testing.expect_value(t, list.length, u32(2))
    testing.expect(t, first.next == &last && last.prev == &first, "remaining events should stay linked")
    eat_event(&list, &first)
    testing.expect(t, list.head == &last && list.tail == &last && last.prev == nil)
    eat_event(&list, &last)
    testing.expect_value(t, list.length, u32(0))
    testing.expect(t, list.head == nil && list.tail == nil)
}

@(test)
event_list_handles_nil_nodes :: proc(t: ^testing.T) {
    list: Event_List
    insert_ll(&list, nil)
    eat_event(&list, nil)
    testing.expect_value(t, list.length, u32(0))
    testing.expect(t, list.head == nil && list.tail == nil)
}
