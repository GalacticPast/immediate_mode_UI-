package wayland

// Bindings for libwayland-client and libwayland-egl.
//
// The C headers implement every request (compositor_create_surface, xdg_surface_get_toplevel, ...)
// as a static inline wrapper around proxy_marshal_flags, so those names don't exist in the library.
// The wrappers below are hand translations of those inline functions.

import "core:c"

foreign import wayland_client "system:wayland-client"
foreign import wayland_egl "system:wayland-egl"

// Opaque handle types. At runtime every one of these points to a proxy inside libwayland;
// the distinct types only stop us from mixing them up.
proxy :: struct {}
display :: struct {}
registry :: struct {}
compositor :: struct {}
surface :: struct {}
seat :: struct {}
keyboard :: struct {}
pointer :: struct {}
callback :: struct {}
output :: struct {}

xdg_wm_base :: struct {}
xdg_surface :: struct {}
xdg_toplevel :: struct {}
egl_window :: struct {}

// 24.8 signed fixed point, used for pointer coordinates and scroll amounts
fixed :: i32

fixed_to_f32 :: #force_inline proc "contextless" (value: fixed) -> f32 {
    return f32(value) / 256
}

array :: struct {
    size:  c.size_t,
    alloc: c.size_t,
    data:  rawptr,
}

// wayland-util.h
message :: struct {
    name:      cstring,
    signature: cstring,
    types:     [^]^interface,
}

interface :: struct {
    name:         cstring,
    version:      c.int,
    method_count: c.int,
    methods:      [^]message,
    event_count:  c.int,
    events:       [^]message,
}

MARSHAL_FLAG_DESTROY :: 1

SEAT_CAPABILITY_POINTER :: 1
SEAT_CAPABILITY_KEYBOARD :: 2
SEAT_CAPABILITY_TOUCH :: 4

KEYBOARD_KEYMAP_FORMAT_XKB_V1 :: 1
KEYBOARD_KEY_STATE_RELEASED :: 0

POINTER_BUTTON_STATE_RELEASED :: 0
POINTER_AXIS_VERTICAL_SCROLL :: 0
POINTER_AXIS_HORIZONTAL_SCROLL :: 1

// Linux evdev button codes (linux/input-event-codes.h)
BTN_LEFT :: 0x110
BTN_RIGHT :: 0x111
BTN_MIDDLE :: 0x112
BTN_SIDE :: 0x113
BTN_EXTRA :: 0x114

@(default_calling_convention = "c", link_prefix = "wl_")
foreign wayland_client {
    // Interface descriptions for the core protocol, exported as data by the library
    registry_interface: interface
    compositor_interface: interface
    surface_interface: interface
    seat_interface: interface
    keyboard_interface: interface
    pointer_interface: interface
    callback_interface: interface

    display_connect :: proc(name: cstring) -> ^display ---
    display_disconnect :: proc(display: ^display) ---
    display_get_fd :: proc(display: ^display) -> c.int ---
    display_dispatch :: proc(display: ^display) -> c.int ---
    display_dispatch_pending :: proc(display: ^display) -> c.int ---
    display_roundtrip :: proc(display: ^display) -> c.int ---
    display_flush :: proc(display: ^display) -> c.int ---
    display_prepare_read :: proc(display: ^display) -> c.int ---
    display_read_events :: proc(display: ^display) -> c.int ---
    display_cancel_read :: proc(display: ^display) ---

    proxy_marshal_flags :: proc(p: ^proxy, opcode: u32, interface: ^interface, version: u32, flags: u32, #c_vararg args: ..any) -> ^proxy ---
    proxy_add_listener :: proc(p: ^proxy, implementation: rawptr, data: rawptr) -> c.int ---
    proxy_get_version :: proc(p: ^proxy) -> u32 ---
    proxy_destroy :: proc(p: ^proxy) ---
}

@(default_calling_convention = "c", link_prefix = "wl_")
foreign wayland_egl {
    egl_window_create :: proc(surface: ^surface, width, height: c.int) -> ^egl_window ---
    egl_window_destroy :: proc(window: ^egl_window) ---
    egl_window_resize :: proc(window: ^egl_window, width, height, dx, dy: c.int) ---
}

// Listeners: one callback per event, in the order the protocol XML defines them.

registry_listener :: struct {
    global:        proc "c" (data: rawptr, registry: ^registry, name: u32, interface: cstring, version: u32),
    global_remove: proc "c" (data: rawptr, registry: ^registry, name: u32),
}

seat_listener :: struct {
    capabilities: proc "c" (data: rawptr, seat: ^seat, capabilities: u32),
    name:         proc "c" (data: rawptr, seat: ^seat, name: cstring),
}

keyboard_listener :: struct {
    keymap:      proc "c" (data: rawptr, keyboard: ^keyboard, format: u32, fd: i32, size: u32),
    enter:       proc "c" (data: rawptr, keyboard: ^keyboard, serial: u32, surface: ^surface, keys: ^array),
    leave:       proc "c" (data: rawptr, keyboard: ^keyboard, serial: u32, surface: ^surface),
    key:         proc "c" (data: rawptr, keyboard: ^keyboard, serial, time, key, state: u32),
    modifiers:   proc "c" (data: rawptr, keyboard: ^keyboard, serial, depressed, latched, locked, group: u32),
    repeat_info: proc "c" (data: rawptr, keyboard: ^keyboard, rate, delay: i32),
}

// Events up to version 10. Which ones arrive depends on the seat version we bind.
pointer_listener :: struct {
    enter:                   proc "c" (data: rawptr, pointer: ^pointer, serial: u32, surface: ^surface, x, y: fixed),
    leave:                   proc "c" (data: rawptr, pointer: ^pointer, serial: u32, surface: ^surface),
    motion:                  proc "c" (data: rawptr, pointer: ^pointer, time: u32, x, y: fixed),
    button:                  proc "c" (data: rawptr, pointer: ^pointer, serial, time, button, state: u32),
    axis:                    proc "c" (data: rawptr, pointer: ^pointer, time, axis: u32, value: fixed),
    frame:                   proc "c" (data: rawptr, pointer: ^pointer),                           // v5
    axis_source:             proc "c" (data: rawptr, pointer: ^pointer, axis_source: u32),         // v5
    axis_stop:               proc "c" (data: rawptr, pointer: ^pointer, time, axis: u32),          // v5
    axis_discrete:           proc "c" (data: rawptr, pointer: ^pointer, axis: u32, discrete: i32), // v5-7
    axis_value120:           proc "c" (data: rawptr, pointer: ^pointer, axis: u32, value120: i32), // v8
    axis_relative_direction: proc "c" (data: rawptr, pointer: ^pointer, axis, direction: u32),     // v9
    warp:                    proc "c" (data: rawptr, pointer: ^pointer, x, y: fixed),              // v10
}

// Events up to version 6.
surface_listener :: struct {
    enter:                      proc "c" (data: rawptr, surface: ^surface, output: ^output),
    leave:                      proc "c" (data: rawptr, surface: ^surface, output: ^output),
    preferred_buffer_scale:     proc "c" (data: rawptr, surface: ^surface, factor: i32),    // v6
    preferred_buffer_transform: proc "c" (data: rawptr, surface: ^surface, transform: u32), // v6
}

callback_listener :: struct {
    done: proc "c" (data: rawptr, callback: ^callback, callback_data: u32),
}

xdg_wm_base_listener :: struct {
    ping: proc "c" (data: rawptr, wm_base: ^xdg_wm_base, serial: u32),
}

xdg_surface_listener :: struct {
    configure: proc "c" (data: rawptr, surface: ^xdg_surface, serial: u32),
}

xdg_toplevel_listener :: struct {
    configure:        proc "c" (data: rawptr, toplevel: ^xdg_toplevel, width, height: i32, states: ^array),
    close:            proc "c" (data: rawptr, toplevel: ^xdg_toplevel),
    configure_bounds: proc "c" (data: rawptr, toplevel: ^xdg_toplevel, width, height: i32),
    wm_capabilities:  proc "c" (data: rawptr, toplevel: ^xdg_toplevel, capabilities: ^array),
}

// Requests. Opcodes are the request's index in the protocol XML (the #defines in the generated headers).

version_of :: proc "contextless" (object: rawptr) -> u32 {
    return proxy_get_version((^proxy)(object))
}

add_listener :: proc "contextless" (object: rawptr, listener: rawptr, data: rawptr) -> c.int {
    return proxy_add_listener((^proxy)(object), listener, data)
}

display_get_registry :: proc "contextless" (display: ^display) -> ^registry {
    DISPLAY_GET_REGISTRY :: 1
    return (^registry)(
        proxy_marshal_flags(
            (^proxy)(display),
            DISPLAY_GET_REGISTRY,
            &registry_interface,
            version_of(display),
            0,
            rawptr(nil),
        ),
    )
}

// registry.bind has signature "usun": the new_id has no fixed type, so the interface name and
// version are sent explicitly before it.
registry_bind :: proc "contextless" (registry: ^registry, name: u32, interface: ^interface, version: u32) -> rawptr {
    REGISTRY_BIND :: 0
    return proxy_marshal_flags(
        (^proxy)(registry),
        REGISTRY_BIND,
        interface,
        version,
        0,
        name,
        interface.name,
        version,
        rawptr(nil),
    )
}

compositor_create_surface :: proc "contextless" (compositor: ^compositor) -> ^surface {
    COMPOSITOR_CREATE_SURFACE :: 0
    return (^surface)(
        proxy_marshal_flags(
            (^proxy)(compositor),
            COMPOSITOR_CREATE_SURFACE,
            &surface_interface,
            version_of(compositor),
            0,
            rawptr(nil),
        ),
    )
}

surface_destroy :: proc "contextless" (surface: ^surface) {
    SURFACE_DESTROY :: 0
    proxy_marshal_flags((^proxy)(surface), SURFACE_DESTROY, nil, version_of(surface), MARSHAL_FLAG_DESTROY)
}

surface_commit :: proc "contextless" (surface: ^surface) {
    SURFACE_COMMIT :: 6
    proxy_marshal_flags((^proxy)(surface), SURFACE_COMMIT, nil, version_of(surface), 0)
}

// Asks for a "done" event when it is a good time to draw the next frame. Applies on the next commit.
surface_frame :: proc "contextless" (surface: ^surface) -> ^callback {
    SURFACE_FRAME :: 3
    return (^callback)(
        proxy_marshal_flags(
            (^proxy)(surface),
            SURFACE_FRAME,
            &callback_interface,
            version_of(surface),
            0,
            rawptr(nil),
        ),
    )
}

// Since version 3. Applies on the next commit, so it must go together with a buffer of matching size.
surface_set_buffer_scale :: proc "contextless" (surface: ^surface, scale: i32) {
    SURFACE_SET_BUFFER_SCALE :: 8
    proxy_marshal_flags((^proxy)(surface), SURFACE_SET_BUFFER_SCALE, nil, version_of(surface), 0, scale)
}

seat_get_pointer :: proc "contextless" (seat: ^seat) -> ^pointer {
    SEAT_GET_POINTER :: 0
    return (^pointer)(
        proxy_marshal_flags((^proxy)(seat), SEAT_GET_POINTER, &pointer_interface, version_of(seat), 0, rawptr(nil)),
    )
}

// A nil surface hides the cursor. `serial` must be the one from the latest pointer.enter.
pointer_set_cursor :: proc "contextless" (
    pointer: ^pointer,
    serial: u32,
    surface: ^surface,
    hotspot_x, hotspot_y: i32,
) {
    POINTER_SET_CURSOR :: 0
    proxy_marshal_flags(
        (^proxy)(pointer),
        POINTER_SET_CURSOR,
        nil,
        version_of(pointer),
        0,
        serial,
        surface,
        hotspot_x,
        hotspot_y,
    )
}

// pointer.release only exists since version 3.
pointer_release :: proc "contextless" (pointer: ^pointer) {
    POINTER_RELEASE :: 1
    if version_of(pointer) >= 3 {
        proxy_marshal_flags((^proxy)(pointer), POINTER_RELEASE, nil, version_of(pointer), MARSHAL_FLAG_DESTROY)
    } else {
        proxy_destroy((^proxy)(pointer))
    }
}

seat_get_keyboard :: proc "contextless" (seat: ^seat) -> ^keyboard {
    SEAT_GET_KEYBOARD :: 1
    return (^keyboard)(
        proxy_marshal_flags((^proxy)(seat), SEAT_GET_KEYBOARD, &keyboard_interface, version_of(seat), 0, rawptr(nil)),
    )
}

// keyboard.release only exists since version 3; older keyboards can only be destroyed client side.
keyboard_release :: proc "contextless" (keyboard: ^keyboard) {
    KEYBOARD_RELEASE :: 0
    if version_of(keyboard) >= 3 {
        proxy_marshal_flags((^proxy)(keyboard), KEYBOARD_RELEASE, nil, version_of(keyboard), MARSHAL_FLAG_DESTROY)
    } else {
        proxy_destroy((^proxy)(keyboard))
    }
}

xdg_wm_base_destroy :: proc "contextless" (wm_base: ^xdg_wm_base) {
    XDG_WM_BASE_DESTROY :: 0
    proxy_marshal_flags((^proxy)(wm_base), XDG_WM_BASE_DESTROY, nil, version_of(wm_base), MARSHAL_FLAG_DESTROY)
}

xdg_wm_base_get_xdg_surface :: proc "contextless" (wm_base: ^xdg_wm_base, surface: ^surface) -> ^xdg_surface {
    XDG_WM_BASE_GET_XDG_SURFACE :: 2
    return (^xdg_surface)(
        proxy_marshal_flags(
            (^proxy)(wm_base),
            XDG_WM_BASE_GET_XDG_SURFACE,
            &xdg_surface_interface,
            version_of(wm_base),
            0,
            rawptr(nil),
            surface,
        ),
    )
}

xdg_wm_base_pong :: proc "contextless" (wm_base: ^xdg_wm_base, serial: u32) {
    XDG_WM_BASE_PONG :: 3
    proxy_marshal_flags((^proxy)(wm_base), XDG_WM_BASE_PONG, nil, version_of(wm_base), 0, serial)
}

xdg_surface_destroy :: proc "contextless" (surface: ^xdg_surface) {
    XDG_SURFACE_DESTROY :: 0
    proxy_marshal_flags((^proxy)(surface), XDG_SURFACE_DESTROY, nil, version_of(surface), MARSHAL_FLAG_DESTROY)
}

xdg_surface_get_toplevel :: proc "contextless" (surface: ^xdg_surface) -> ^xdg_toplevel {
    XDG_SURFACE_GET_TOPLEVEL :: 1
    return (^xdg_toplevel)(
        proxy_marshal_flags(
            (^proxy)(surface),
            XDG_SURFACE_GET_TOPLEVEL,
            &xdg_toplevel_interface,
            version_of(surface),
            0,
            rawptr(nil),
        ),
    )
}

xdg_surface_ack_configure :: proc "contextless" (surface: ^xdg_surface, serial: u32) {
    XDG_SURFACE_ACK_CONFIGURE :: 4
    proxy_marshal_flags((^proxy)(surface), XDG_SURFACE_ACK_CONFIGURE, nil, version_of(surface), 0, serial)
}

xdg_toplevel_destroy :: proc "contextless" (toplevel: ^xdg_toplevel) {
    XDG_TOPLEVEL_DESTROY :: 0
    proxy_marshal_flags((^proxy)(toplevel), XDG_TOPLEVEL_DESTROY, nil, version_of(toplevel), MARSHAL_FLAG_DESTROY)
}

xdg_toplevel_set_title :: proc "contextless" (toplevel: ^xdg_toplevel, title: cstring) {
    XDG_TOPLEVEL_SET_TITLE :: 2
    proxy_marshal_flags((^proxy)(toplevel), XDG_TOPLEVEL_SET_TITLE, nil, version_of(toplevel), 0, title)
}

xdg_toplevel_set_app_id :: proc "contextless" (toplevel: ^xdg_toplevel, app_id: cstring) {
    XDG_TOPLEVEL_SET_APP_ID :: 3
    proxy_marshal_flags((^proxy)(toplevel), XDG_TOPLEVEL_SET_APP_ID, nil, version_of(toplevel), 0, app_id)
}

xdg_toplevel_set_min_size :: proc "contextless" (toplevel: ^xdg_toplevel, width, height: i32) {
    XDG_TOPLEVEL_SET_MIN_SIZE :: 8
    proxy_marshal_flags((^proxy)(toplevel), XDG_TOPLEVEL_SET_MIN_SIZE, nil, version_of(toplevel), 0, width, height)
}
xdg_toplevel_set_max_size :: proc "contextless" (toplevel: ^xdg_toplevel, width, height: i32) {
    XDG_TOPLEVEL_SET_MAX_SIZE :: 7
    proxy_marshal_flags((^proxy)(toplevel), XDG_TOPLEVEL_SET_MAX_SIZE, nil, version_of(toplevel), 0, width, height)
}
