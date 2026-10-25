package platform

import "base:runtime"
import "core:fmt"
import "core:time"

Event_Type :: enum {
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

Key_Type :: enum {
    NONE         = 0x00,
    BACKSPACE    = 0x08,
    ENTER        = 0x0D,
    TAB          = 0x09,
    SHIFT        = 0x10,
    CONTROL      = 0x11,
    PAUSE        = 0x13,
    CAPITAL      = 0x14,
    ESCAPE       = 0x1B,
    CONVERT      = 0x1C,
    NONCONVERT   = 0x1D,
    ACCEPT       = 0x1E,
    MODECHANGE   = 0x1F,
    SPACE        = 0x20,
    PRIOR        = 0x21,
    NEXT         = 0x22,
    END          = 0x23,
    HOME         = 0x24,
    LEFT         = 0x25,
    UP           = 0x26,
    RIGHT        = 0x27,
    DOWN         = 0x28,
    SELECT       = 0x29,
    PRINT        = 0x2A,
    SNAPSHOT     = 0x2C,
    INSERT       = 0x2D,
    DELETE       = 0x2E,
    HELP         = 0x2F,
    A            = 0x41,
    B            = 0x42,
    C            = 0x43,
    D            = 0x44,
    E            = 0x45,
    F            = 0x46,
    G            = 0x47,
    H            = 0x48,
    I            = 0x49,
    J            = 0x4A,
    K            = 0x4B,
    L            = 0x4C,
    M            = 0x4D,
    N            = 0x4E,
    O            = 0x4F,
    P            = 0x50,
    Q            = 0x51,
    R            = 0x52,
    S            = 0x53,
    T            = 0x54,
    U            = 0x55,
    V            = 0x56,
    W            = 0x57,
    X            = 0x58,
    Y            = 0x59,
    Z            = 0x5A,
    LWIN         = 0x5B,
    RWIN         = 0x5C,
    APPS         = 0x5D,
    SLEEP        = 0x5F,
    NUMPAD0      = 0x60,
    NUMPAD1      = 0x61,
    NUMPAD2      = 0x62,
    NUMPAD3      = 0x63,
    NUMPAD4      = 0x64,
    NUMPAD5      = 0x65,
    NUMPAD6      = 0x66,
    NUMPAD7      = 0x67,
    NUMPAD8      = 0x68,
    NUMPAD9      = 0x69,
    MULTIPLY     = 0x6A,
    ADD          = 0x6B,
    SEPARATOR    = 0x6C,
    SUBTRACT     = 0x6D,
    DECIMAL      = 0x6E,
    DIVIDE       = 0x6F,
    F1           = 0x70,
    F2           = 0x71,
    F3           = 0x72,
    F4           = 0x73,
    F5           = 0x74,
    F6           = 0x75,
    F7           = 0x76,
    F8           = 0x77,
    F9           = 0x78,
    F10          = 0x79,
    F11          = 0x7A,
    F12          = 0x7B,
    F13          = 0x7C,
    F14          = 0x7D,
    F15          = 0x7E,
    F16          = 0x7F,
    F17          = 0x80,
    F18          = 0x81,
    F19          = 0x82,
    F20          = 0x83,
    F21          = 0x84,
    F22          = 0x85,
    F23          = 0x86,
    F24          = 0x87,
    NUMLOCK      = 0x90,
    SCROLL       = 0x91,
    NUMPAD_EQUAL = 0x92,
    LSHIFT       = 0xA0,
    RSHIFT       = 0xA1,
    LCONTROL     = 0xA2,
    RCONTROL     = 0xA3,
    LALT         = 0xA4,
    RALT         = 0xA5,
    SEMICOLON    = 0xBA,
    PLUS         = 0xBB,
    COMMA        = 0xBC,
    MINUS        = 0xBD,
    PERIOD       = 0xBE,
    SLASH        = 0xBF,
    GRAVE        = 0xC0,
    MAX_KEYS     = 0xfffff,
}

Event :: struct {
    next: ^Event,
    prev: ^Event,
    type: Event_Type,
    key:  Key_Type,
    pos:  Vector2,
}

Event_List :: struct {
    head:   ^Event,
    tail:   ^Event,
    length: u32,
}

Platform_State :: struct {
    list:      Event_List,
    // has the allocator been set or not
    // this has to be set for every time the calles calls get_events
    // and needs to be unset
    t_context: ^runtime.Context,
}

p_state: Platform_State

get_events :: proc() -> Event_List {

    ctx := context
    ctx.allocator = ctx.temp_allocator
    p_state.t_context = &ctx
    defer { p_state.t_context = nil }

    // reset the list
    p_state.list = {}

    // do the dispatch
    result := dispatch()
    if !result {
        fmt.eprintln("lol")
    }
    //
    return p_state.list
}

// do we need to make it contextless?
// expects fresh, unlinked node
@(private)
insert_ll :: proc(list: ^Event_List, node: ^Event) {
    if node == nil do return

    if list.tail != nil {
        list.tail.next = node
        node.prev = list.tail
    }
    if list.head == nil {
        list.head = node
    }
    list.tail = node
    list.length += 1
}


eat_event :: proc(list: ^Event_List, node: ^Event) {
    if node == nil do return

    if node.next != nil {
        node.next.prev = node.prev
    }
    if node.prev != nil {
        node.prev.next = node.next
    }
    if list.head == node {
        list.head = node.next
    }
    if list.tail == node {
        list.tail = node.prev
    }
    list.length -= 1
}

push_event :: proc(e: ^Event) {
    insert_ll(&p_state.list, e)
}

// -1 = no deadline, sleep until an event. 0 = deadline already passed, don't sleep.
poll_timeout_ms :: proc(deadline: time.Tick) -> i32 {
    if deadline == {} {
        return -1
    }

    remaining: time.Duration = time.tick_diff(time.tick_now(), deadline)
    if remaining <= 0 {
        return 0
    }

    // round up, otherwise a deadline 0.4 ms away becomes poll(0) and the loop spins
    ms: i64 = cast(i64)((remaining + time.Millisecond - 1) / time.Millisecond)
    // cap it so the cast can't overflow, we recompute every wake anyway
    return cast(i32)min(ms, 60_000)
}
