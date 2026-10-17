package platform

import "base:runtime"
import "core:fmt"

event_types :: enum {
    NONE = 0,
    // window events
    WINDOW_CLOSE,
    WINDOW_RESIZE,
    // input events
    KEY_PRESS,
    KEY_RELEASE,
    KEY_REPEAT,
    MOUSE_MOVE,
    MOUSE_SCROLL,
}

Vector2 :: [2]i32

key_type :: enum {
    NONE             = 0x00,
    KEY_BACKSPACE    = 0x08,
    KEY_ENTER        = 0x0D,
    KEY_TAB          = 0x09,
    KEY_SHIFT        = 0x10,
    KEY_CONTROL      = 0x11,
    KEY_PAUSE        = 0x13,
    KEY_CAPITAL      = 0x14,
    KEY_ESCAPE       = 0x1B,
    KEY_CONVERT      = 0x1C,
    KEY_NONCONVERT   = 0x1D,
    KEY_ACCEPT       = 0x1E,
    KEY_MODECHANGE   = 0x1F,
    KEY_SPACE        = 0x20,
    KEY_PRIOR        = 0x21,
    KEY_NEXT         = 0x22,
    KEY_END          = 0x23,
    KEY_HOME         = 0x24,
    KEY_LEFT         = 0x25,
    KEY_UP           = 0x26,
    KEY_RIGHT        = 0x27,
    KEY_DOWN         = 0x28,
    KEY_SELECT       = 0x29,
    KEY_PRINT        = 0x2A,
    KEY_SNAPSHOT     = 0x2C,
    KEY_INSERT       = 0x2D,
    KEY_DELETE       = 0x2E,
    KEY_HELP         = 0x2F,
    KEY_A            = 0x41,
    KEY_B            = 0x42,
    KEY_C            = 0x43,
    KEY_D            = 0x44,
    KEY_E            = 0x45,
    KEY_F            = 0x46,
    KEY_G            = 0x47,
    KEY_H            = 0x48,
    KEY_I            = 0x49,
    KEY_J            = 0x4A,
    KEY_K            = 0x4B,
    KEY_L            = 0x4C,
    KEY_M            = 0x4D,
    KEY_N            = 0x4E,
    KEY_O            = 0x4F,
    KEY_P            = 0x50,
    KEY_Q            = 0x51,
    KEY_R            = 0x52,
    KEY_S            = 0x53,
    KEY_T            = 0x54,
    KEY_U            = 0x55,
    KEY_V            = 0x56,
    KEY_W            = 0x57,
    KEY_X            = 0x58,
    KEY_Y            = 0x59,
    KEY_Z            = 0x5A,
    KEY_LWIN         = 0x5B,
    KEY_RWIN         = 0x5C,
    KEY_APPS         = 0x5D,
    KEY_SLEEP        = 0x5F,
    KEY_NUMPAD0      = 0x60,
    KEY_NUMPAD1      = 0x61,
    KEY_NUMPAD2      = 0x62,
    KEY_NUMPAD3      = 0x63,
    KEY_NUMPAD4      = 0x64,
    KEY_NUMPAD5      = 0x65,
    KEY_NUMPAD6      = 0x66,
    KEY_NUMPAD7      = 0x67,
    KEY_NUMPAD8      = 0x68,
    KEY_NUMPAD9      = 0x69,
    KEY_MULTIPLY     = 0x6A,
    KEY_ADD          = 0x6B,
    KEY_SEPARATOR    = 0x6C,
    KEY_SUBTRACT     = 0x6D,
    KEY_DECIMAL      = 0x6E,
    KEY_DIVIDE       = 0x6F,
    KEY_F1           = 0x70,
    KEY_F2           = 0x71,
    KEY_F3           = 0x72,
    KEY_F4           = 0x73,
    KEY_F5           = 0x74,
    KEY_F6           = 0x75,
    KEY_F7           = 0x76,
    KEY_F8           = 0x77,
    KEY_F9           = 0x78,
    KEY_F10          = 0x79,
    KEY_F11          = 0x7A,
    KEY_F12          = 0x7B,
    KEY_F13          = 0x7C,
    KEY_F14          = 0x7D,
    KEY_F15          = 0x7E,
    KEY_F16          = 0x7F,
    KEY_F17          = 0x80,
    KEY_F18          = 0x81,
    KEY_F19          = 0x82,
    KEY_F20          = 0x83,
    KEY_F21          = 0x84,
    KEY_F22          = 0x85,
    KEY_F23          = 0x86,
    KEY_F24          = 0x87,
    KEY_NUMLOCK      = 0x90,
    KEY_SCROLL       = 0x91,
    KEY_NUMPAD_EQUAL = 0x92,
    KEY_LSHIFT       = 0xA0,
    KEY_RSHIFT       = 0xA1,
    KEY_LCONTROL     = 0xA2,
    KEY_RCONTROL     = 0xA3,
    KEY_LALT         = 0xA4,
    KEY_RALT         = 0xA5,
    KEY_SEMICOLON    = 0xBA,
    KEY_PLUS         = 0xBB,
    KEY_COMMA        = 0xBC,
    KEY_MINUS        = 0xBD,
    KEY_PERIOD       = 0xBE,
    KEY_SLASH        = 0xBF,
    KEY_GRAVE        = 0xC0,
    KEY_MAX_KEYS     = 0xfffff,
}

event :: struct {
    next: ^event,
    prev: ^event,
    type: event_types,
    key:  key_type,
    pos:  Vector2,
}

event_list :: struct {
    head:   ^event,
    tail:   ^event,
    length: u32,
}

platform_state :: struct {
    list:      event_list,
    // has the allocator been set or not
    // this has to be set for every time the calles calls get_events
    // and needs to be unset
    t_context: ^runtime.Context,
}

p_state: platform_state

get_events :: proc() -> event_list {

    ctx := context
    ctx.allocator = ctx.temp_allocator
    p_state.t_context = &ctx
    defer { p_state.t_context = nil }

    // reset the list
    p_state.list = {}

    // do the dispatch
    result: bool = dispatch()
    if !result {
        fmt.eprintln("lol")
    }
    //
    return p_state.list
}

// do we need to make it contextless?
insert_ll :: proc(list: ^event_list, node: ^event) {
    defer { list.length += 1 }
    if list.head == nil && list.tail == nil {
        list.head = node
        list.tail = list.head
        return
    }
    if (list.tail == list.head) {
        list.head.next = node
        node.prev = list.head
        list.tail = node
    } else {
        list.tail.prev.next = node
        node.prev = list.tail.prev
        node.next = nil
    }
    list.tail = node
}


eat_event :: proc(list: ^event_list, node: ^event) {
    if node == nil {
        fmt.eprintln("head ptr is nil")
        return
    }
    if list.head == node {
        list.head.next = nil
        list.head.prev = nil
        list.head = node.next
        node.prev = nil
        node.next = nil
    } else if list.tail == node {
        list.tail.prev.next = nil
        list.tail = list.tail.prev
        node.prev = nil
        node.next = nil
    } else {
        node.prev.next = node.next
        node.next.prev = node.prev
        node.next = nil
        node.prev = nil
    }
    list.length -= 1
}

push_event :: proc(e: ^event) {
    insert_ll(&p_state.list, e)
}
