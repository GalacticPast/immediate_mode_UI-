package wayland

// Bindings for libwayland-client and libwayland-egl.
//
// The C headers implement every request (wl_compositor_create_surface, xdg_surface_get_toplevel, ...)
// as a static inline wrapper around wl_proxy_marshal_flags, so those names don't exist in the library.
// The wrappers below are hand translations of those inline functions.

import "core:c"

foreign import wayland_client "system:wayland-client"
foreign import wayland_egl "system:wayland-egl"

// Opaque handle types. At runtime every one of these points to a wl_proxy inside libwayland;
// the distinct types only stop us from mixing them up.
wl_proxy :: struct {}
wl_display :: struct {}
wl_registry :: struct {}
wl_compositor :: struct {}
wl_surface :: struct {}
wl_seat :: struct {}
wl_keyboard :: struct {}
wl_pointer :: struct {}
wl_callback :: struct {}
wl_output :: struct {}
xdg_wm_base :: struct {}
xdg_surface :: struct {}
xdg_toplevel :: struct {}
wl_egl_window :: struct {}

// 24.8 signed fixed point, used for pointer coordinates and scroll amounts
wl_fixed :: i32

wl_fixed_to_f32 :: #force_inline proc "contextless" (value: wl_fixed) -> f32 {
    return f32(value) / 256
}

wl_array :: struct {
    size:  c.size_t,
    alloc: c.size_t,
    data:  rawptr,
}

// wayland-util.h
wl_message :: struct {
    name:      cstring,
    signature: cstring,
    types:     [^]^wl_interface,
}

wl_interface :: struct {
    name:         cstring,
    version:      c.int,
    method_count: c.int,
    methods:      [^]wl_message,
    event_count:  c.int,
    events:       [^]wl_message,
}

WL_MARSHAL_FLAG_DESTROY :: 1

WL_SEAT_CAPABILITY_POINTER :: 1
WL_SEAT_CAPABILITY_KEYBOARD :: 2
WL_SEAT_CAPABILITY_TOUCH :: 4

WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1 :: 1
WL_KEYBOARD_KEY_STATE_RELEASED :: 0

WL_POINTER_BUTTON_STATE_RELEASED :: 0
WL_POINTER_AXIS_VERTICAL_SCROLL :: 0
WL_POINTER_AXIS_HORIZONTAL_SCROLL :: 1

// Linux evdev button codes (linux/input-event-codes.h)
BTN_LEFT :: 0x110
BTN_RIGHT :: 0x111
BTN_MIDDLE :: 0x112
BTN_SIDE :: 0x113
BTN_EXTRA :: 0x114

@(default_calling_convention = "c")
foreign wayland_client {
    // Interface descriptions for the core protocol, exported as data by the library
    wl_registry_interface:       wl_interface
    wl_compositor_interface:     wl_interface
    wl_surface_interface:        wl_interface
    wl_seat_interface:           wl_interface
    wl_keyboard_interface:       wl_interface
    wl_pointer_interface:        wl_interface
    wl_callback_interface:       wl_interface

    wl_display_connect          :: proc(name: cstring) -> ^wl_display ---
    wl_display_disconnect       :: proc(display: ^wl_display) ---
    wl_display_get_fd           :: proc(display: ^wl_display) -> c.int ---
    wl_display_dispatch         :: proc(display: ^wl_display) -> c.int ---
    wl_display_dispatch_pending :: proc(display: ^wl_display) -> c.int ---
    wl_display_roundtrip        :: proc(display: ^wl_display) -> c.int ---
    wl_display_flush            :: proc(display: ^wl_display) -> c.int ---
    wl_display_prepare_read     :: proc(display: ^wl_display) -> c.int ---
    wl_display_read_events      :: proc(display: ^wl_display) -> c.int ---
    wl_display_cancel_read      :: proc(display: ^wl_display) ---

    wl_proxy_marshal_flags :: proc(proxy: ^wl_proxy, opcode: u32, interface: ^wl_interface, version: u32, flags: u32, #c_vararg args: ..any) -> ^wl_proxy ---
    wl_proxy_add_listener  :: proc(proxy: ^wl_proxy, implementation: rawptr, data: rawptr) -> c.int ---
    wl_proxy_get_version   :: proc(proxy: ^wl_proxy) -> u32 ---
    wl_proxy_destroy       :: proc(proxy: ^wl_proxy) ---
}

@(default_calling_convention = "c")
foreign wayland_egl {
    wl_egl_window_create  :: proc(surface: ^wl_surface, width, height: c.int) -> ^wl_egl_window ---
    wl_egl_window_destroy :: proc(window: ^wl_egl_window) ---
    wl_egl_window_resize  :: proc(window: ^wl_egl_window, width, height, dx, dy: c.int) ---
}

// Listeners: one callback per event, in the order the protocol XML defines them.

wl_registry_listener :: struct {
    global:        proc "c" (data: rawptr, registry: ^wl_registry, name: u32, interface: cstring, version: u32),
    global_remove: proc "c" (data: rawptr, registry: ^wl_registry, name: u32),
}

wl_seat_listener :: struct {
    capabilities: proc "c" (data: rawptr, seat: ^wl_seat, capabilities: u32),
    name:         proc "c" (data: rawptr, seat: ^wl_seat, name: cstring),
}

wl_keyboard_listener :: struct {
    keymap:      proc "c" (data: rawptr, keyboard: ^wl_keyboard, format: u32, fd: i32, size: u32),
    enter:       proc "c" (data: rawptr, keyboard: ^wl_keyboard, serial: u32, surface: ^wl_surface, keys: ^wl_array),
    leave:       proc "c" (data: rawptr, keyboard: ^wl_keyboard, serial: u32, surface: ^wl_surface),
    key:         proc "c" (data: rawptr, keyboard: ^wl_keyboard, serial, time, key, state: u32),
    modifiers:   proc "c" (data: rawptr, keyboard: ^wl_keyboard, serial, depressed, latched, locked, group: u32),
    repeat_info: proc "c" (data: rawptr, keyboard: ^wl_keyboard, rate, delay: i32),
}

// Events up to version 10. Which ones arrive depends on the wl_seat version we bind.
wl_pointer_listener :: struct {
    enter:                   proc "c" (data: rawptr, pointer: ^wl_pointer, serial: u32, surface: ^wl_surface, x, y: wl_fixed),
    leave:                   proc "c" (data: rawptr, pointer: ^wl_pointer, serial: u32, surface: ^wl_surface),
    motion:                  proc "c" (data: rawptr, pointer: ^wl_pointer, time: u32, x, y: wl_fixed),
    button:                  proc "c" (data: rawptr, pointer: ^wl_pointer, serial, time, button, state: u32),
    axis:                    proc "c" (data: rawptr, pointer: ^wl_pointer, time, axis: u32, value: wl_fixed),
    frame:                   proc "c" (data: rawptr, pointer: ^wl_pointer), // v5
    axis_source:             proc "c" (data: rawptr, pointer: ^wl_pointer, axis_source: u32), // v5
    axis_stop:               proc "c" (data: rawptr, pointer: ^wl_pointer, time, axis: u32), // v5
    axis_discrete:           proc "c" (data: rawptr, pointer: ^wl_pointer, axis: u32, discrete: i32), // v5-7
    axis_value120:           proc "c" (data: rawptr, pointer: ^wl_pointer, axis: u32, value120: i32), // v8
    axis_relative_direction: proc "c" (data: rawptr, pointer: ^wl_pointer, axis, direction: u32), // v9
    warp:                    proc "c" (data: rawptr, pointer: ^wl_pointer, x, y: wl_fixed), // v10
}

// Events up to version 6.
wl_surface_listener :: struct {
    enter:                      proc "c" (data: rawptr, surface: ^wl_surface, output: ^wl_output),
    leave:                      proc "c" (data: rawptr, surface: ^wl_surface, output: ^wl_output),
    preferred_buffer_scale:     proc "c" (data: rawptr, surface: ^wl_surface, factor: i32), // v6
    preferred_buffer_transform: proc "c" (data: rawptr, surface: ^wl_surface, transform: u32), // v6
}

wl_callback_listener :: struct {
    done: proc "c" (data: rawptr, callback: ^wl_callback, callback_data: u32),
}

xdg_wm_base_listener :: struct {
    ping: proc "c" (data: rawptr, wm_base: ^xdg_wm_base, serial: u32),
}

xdg_surface_listener :: struct {
    configure: proc "c" (data: rawptr, surface: ^xdg_surface, serial: u32),
}

xdg_toplevel_listener :: struct {
    configure:        proc "c" (data: rawptr, toplevel: ^xdg_toplevel, width, height: i32, states: ^wl_array),
    close:            proc "c" (data: rawptr, toplevel: ^xdg_toplevel),
    configure_bounds: proc "c" (data: rawptr, toplevel: ^xdg_toplevel, width, height: i32),
    wm_capabilities:  proc "c" (data: rawptr, toplevel: ^xdg_toplevel, capabilities: ^wl_array),
}

// Requests. Opcodes are the request's index in the protocol XML (the #defines in the generated headers).

version_of :: proc "contextless" (object: rawptr) -> u32 {
    return wl_proxy_get_version((^wl_proxy)(object))
}

wl_add_listener :: proc "contextless" (object: rawptr, listener: rawptr, data: rawptr) -> c.int {
    return wl_proxy_add_listener((^wl_proxy)(object), listener, data)
}

wl_display_get_registry :: proc "contextless" (display: ^wl_display) -> ^wl_registry {
    WL_DISPLAY_GET_REGISTRY :: 1
    return (^wl_registry)(wl_proxy_marshal_flags((^wl_proxy)(display), WL_DISPLAY_GET_REGISTRY, &wl_registry_interface, version_of(display), 0, rawptr(nil)))
}

// wl_registry.bind has signature "usun": the new_id has no fixed type, so the interface name and
// version are sent explicitly before it.
wl_registry_bind :: proc "contextless" (registry: ^wl_registry, name: u32, interface: ^wl_interface, version: u32) -> rawptr {
    WL_REGISTRY_BIND :: 0
    return wl_proxy_marshal_flags((^wl_proxy)(registry), WL_REGISTRY_BIND, interface, version, 0, name, interface.name, version, rawptr(nil))
}

wl_compositor_create_surface :: proc "contextless" (compositor: ^wl_compositor) -> ^wl_surface {
    WL_COMPOSITOR_CREATE_SURFACE :: 0
    return (^wl_surface)(wl_proxy_marshal_flags((^wl_proxy)(compositor), WL_COMPOSITOR_CREATE_SURFACE, &wl_surface_interface, version_of(compositor), 0, rawptr(nil)))
}

wl_surface_destroy :: proc "contextless" (surface: ^wl_surface) {
    WL_SURFACE_DESTROY :: 0
    wl_proxy_marshal_flags((^wl_proxy)(surface), WL_SURFACE_DESTROY, nil, version_of(surface), WL_MARSHAL_FLAG_DESTROY)
}

wl_surface_commit :: proc "contextless" (surface: ^wl_surface) {
    WL_SURFACE_COMMIT :: 6
    wl_proxy_marshal_flags((^wl_proxy)(surface), WL_SURFACE_COMMIT, nil, version_of(surface), 0)
}

// Asks for a "done" event when it is a good time to draw the next frame. Applies on the next commit.
wl_surface_frame :: proc "contextless" (surface: ^wl_surface) -> ^wl_callback {
    WL_SURFACE_FRAME :: 3
    return (^wl_callback)(wl_proxy_marshal_flags((^wl_proxy)(surface), WL_SURFACE_FRAME, &wl_callback_interface, version_of(surface), 0, rawptr(nil)))
}

// Since version 3. Applies on the next commit, so it must go together with a buffer of matching size.
wl_surface_set_buffer_scale :: proc "contextless" (surface: ^wl_surface, scale: i32) {
    WL_SURFACE_SET_BUFFER_SCALE :: 8
    wl_proxy_marshal_flags((^wl_proxy)(surface), WL_SURFACE_SET_BUFFER_SCALE, nil, version_of(surface), 0, scale)
}

wl_seat_get_pointer :: proc "contextless" (seat: ^wl_seat) -> ^wl_pointer {
    WL_SEAT_GET_POINTER :: 0
    return (^wl_pointer)(wl_proxy_marshal_flags((^wl_proxy)(seat), WL_SEAT_GET_POINTER, &wl_pointer_interface, version_of(seat), 0, rawptr(nil)))
}

// A nil surface hides the cursor. `serial` must be the one from the latest wl_pointer.enter.
wl_pointer_set_cursor :: proc "contextless" (pointer: ^wl_pointer, serial: u32, surface: ^wl_surface, hotspot_x, hotspot_y: i32) {
    WL_POINTER_SET_CURSOR :: 0
    wl_proxy_marshal_flags((^wl_proxy)(pointer), WL_POINTER_SET_CURSOR, nil, version_of(pointer), 0, serial, surface, hotspot_x, hotspot_y)
}

// wl_pointer.release only exists since version 3.
wl_pointer_release :: proc "contextless" (pointer: ^wl_pointer) {
    WL_POINTER_RELEASE :: 1
    if version_of(pointer) >= 3 {
        wl_proxy_marshal_flags((^wl_proxy)(pointer), WL_POINTER_RELEASE, nil, version_of(pointer), WL_MARSHAL_FLAG_DESTROY)
    } else {
        wl_proxy_destroy((^wl_proxy)(pointer))
    }
}

wl_seat_get_keyboard :: proc "contextless" (seat: ^wl_seat) -> ^wl_keyboard {
    WL_SEAT_GET_KEYBOARD :: 1
    return (^wl_keyboard)(wl_proxy_marshal_flags((^wl_proxy)(seat), WL_SEAT_GET_KEYBOARD, &wl_keyboard_interface, version_of(seat), 0, rawptr(nil)))
}

// wl_keyboard.release only exists since version 3; older keyboards can only be destroyed client side.
wl_keyboard_release :: proc "contextless" (keyboard: ^wl_keyboard) {
    WL_KEYBOARD_RELEASE :: 0
    if version_of(keyboard) >= 3 {
        wl_proxy_marshal_flags((^wl_proxy)(keyboard), WL_KEYBOARD_RELEASE, nil, version_of(keyboard), WL_MARSHAL_FLAG_DESTROY)
    } else {
        wl_proxy_destroy((^wl_proxy)(keyboard))
    }
}

xdg_wm_base_destroy :: proc "contextless" (wm_base: ^xdg_wm_base) {
    XDG_WM_BASE_DESTROY :: 0
    wl_proxy_marshal_flags((^wl_proxy)(wm_base), XDG_WM_BASE_DESTROY, nil, version_of(wm_base), WL_MARSHAL_FLAG_DESTROY)
}

xdg_wm_base_get_xdg_surface :: proc "contextless" (wm_base: ^xdg_wm_base, surface: ^wl_surface) -> ^xdg_surface {
    XDG_WM_BASE_GET_XDG_SURFACE :: 2
    return (^xdg_surface)(wl_proxy_marshal_flags((^wl_proxy)(wm_base), XDG_WM_BASE_GET_XDG_SURFACE, &xdg_surface_interface, version_of(wm_base), 0, rawptr(nil), surface))
}

xdg_wm_base_pong :: proc "contextless" (wm_base: ^xdg_wm_base, serial: u32) {
    XDG_WM_BASE_PONG :: 3
    wl_proxy_marshal_flags((^wl_proxy)(wm_base), XDG_WM_BASE_PONG, nil, version_of(wm_base), 0, serial)
}

xdg_surface_destroy :: proc "contextless" (surface: ^xdg_surface) {
    XDG_SURFACE_DESTROY :: 0
    wl_proxy_marshal_flags((^wl_proxy)(surface), XDG_SURFACE_DESTROY, nil, version_of(surface), WL_MARSHAL_FLAG_DESTROY)
}

xdg_surface_get_toplevel :: proc "contextless" (surface: ^xdg_surface) -> ^xdg_toplevel {
    XDG_SURFACE_GET_TOPLEVEL :: 1
    return (^xdg_toplevel)(wl_proxy_marshal_flags((^wl_proxy)(surface), XDG_SURFACE_GET_TOPLEVEL, &xdg_toplevel_interface, version_of(surface), 0, rawptr(nil)))
}

xdg_surface_ack_configure :: proc "contextless" (surface: ^xdg_surface, serial: u32) {
    XDG_SURFACE_ACK_CONFIGURE :: 4
    wl_proxy_marshal_flags((^wl_proxy)(surface), XDG_SURFACE_ACK_CONFIGURE, nil, version_of(surface), 0, serial)
}

xdg_toplevel_destroy :: proc "contextless" (toplevel: ^xdg_toplevel) {
    XDG_TOPLEVEL_DESTROY :: 0
    wl_proxy_marshal_flags((^wl_proxy)(toplevel), XDG_TOPLEVEL_DESTROY, nil, version_of(toplevel), WL_MARSHAL_FLAG_DESTROY)
}

xdg_toplevel_set_title :: proc "contextless" (toplevel: ^xdg_toplevel, title: cstring) {
    XDG_TOPLEVEL_SET_TITLE :: 2
    wl_proxy_marshal_flags((^wl_proxy)(toplevel), XDG_TOPLEVEL_SET_TITLE, nil, version_of(toplevel), 0, title)
}

xdg_toplevel_set_app_id :: proc "contextless" (toplevel: ^xdg_toplevel, app_id: cstring) {
    XDG_TOPLEVEL_SET_APP_ID :: 3
    wl_proxy_marshal_flags((^wl_proxy)(toplevel), XDG_TOPLEVEL_SET_APP_ID, nil, version_of(toplevel), 0, app_id)
}
