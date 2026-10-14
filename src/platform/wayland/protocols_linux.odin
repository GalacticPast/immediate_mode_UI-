package wayland

// Optional protocols from wayland-protocols, translated by hand like xdg_shell_linux.odin:
//   viewporter        (stable)  lets a buffer of any size be shown at the window's logical size
//   fractional-scale  (staging) tells us the exact scale of the output, e.g. 1.5
//   cursor-shape      (staging) lets the compositor draw standard cursors, no cursor images needed

wp_viewporter :: struct {}
wp_viewport :: struct {}
wp_fractional_scale_manager_v1 :: struct {}
wp_fractional_scale_v1 :: struct {}
wp_cursor_shape_manager_v1 :: struct {}
wp_cursor_shape_device_v1 :: struct {}

wp_fractional_scale_v1_listener :: struct {
    // The scale numerator over a denominator of 120, so 1.5 arrives as 180.
    preferred_scale: proc "c" (data: rawptr, fractional_scale: ^wp_fractional_scale_v1, scale: u32),
}

// --- interface tables ------------------------------------------------------

@(private = "file")
get_viewport_types := [2]^wl_interface{&wp_viewport_interface, nil}
@(private = "file")
get_fractional_scale_types := [2]^wl_interface{&wp_fractional_scale_v1_interface, nil}
@(private = "file")
get_cursor_pointer_types := [2]^wl_interface{&wp_cursor_shape_device_v1_interface, nil}

// wl_surface_interface and wl_pointer_interface live inside libwayland; their addresses are only
// known once the program is loaded.
@(init, private = "file")
init_protocol_types :: proc "contextless" () {
    get_viewport_types[1] = &wl_surface_interface
    get_fractional_scale_types[1] = &wl_surface_interface
    get_cursor_pointer_types[1] = &wl_pointer_interface
}

@(private = "file")
wp_viewporter_requests := [?]wl_message{{"destroy", "", nil}, {"get_viewport", "no", raw_data(get_viewport_types[:])}}
wp_viewporter_interface := wl_interface {
    name         = "wp_viewporter",
    version      = 1,
    method_count = len(wp_viewporter_requests),
    methods      = raw_data(wp_viewporter_requests[:]),
}

@(private = "file")
wp_viewport_requests := [?]wl_message {
    {"destroy", "", nil},
    {"set_source", "ffff", nil},
    {"set_destination", "ii", nil},
}
wp_viewport_interface := wl_interface {
    name         = "wp_viewport",
    version      = 1,
    method_count = len(wp_viewport_requests),
    methods      = raw_data(wp_viewport_requests[:]),
}

@(private = "file")
wp_fractional_scale_manager_v1_requests := [?]wl_message {
    {"destroy", "", nil},
    {"get_fractional_scale", "no", raw_data(get_fractional_scale_types[:])},
}
wp_fractional_scale_manager_v1_interface := wl_interface {
    name         = "wp_fractional_scale_manager_v1",
    version      = 1,
    method_count = len(wp_fractional_scale_manager_v1_requests),
    methods      = raw_data(wp_fractional_scale_manager_v1_requests[:]),
}

@(private = "file")
wp_fractional_scale_v1_requests := [?]wl_message{{"destroy", "", nil}}
@(private = "file")
wp_fractional_scale_v1_events := [?]wl_message{{"preferred_scale", "u", nil}}
wp_fractional_scale_v1_interface := wl_interface {
    name         = "wp_fractional_scale_v1",
    version      = 1,
    method_count = len(wp_fractional_scale_v1_requests),
    methods      = raw_data(wp_fractional_scale_v1_requests[:]),
    event_count  = len(wp_fractional_scale_v1_events),
    events       = raw_data(wp_fractional_scale_v1_events[:]),
}

@(private = "file")
wp_cursor_shape_manager_v1_requests := [?]wl_message {
    {"destroy", "", nil},
    {"get_pointer", "no", raw_data(get_cursor_pointer_types[:])},
    {"get_tablet_tool_v2", "no", nil},
}
wp_cursor_shape_manager_v1_interface := wl_interface {
    name         = "wp_cursor_shape_manager_v1",
    version      = 2,
    method_count = len(wp_cursor_shape_manager_v1_requests),
    methods      = raw_data(wp_cursor_shape_manager_v1_requests[:]),
}

@(private = "file")
wp_cursor_shape_device_v1_requests := [?]wl_message{{"destroy", "", nil}, {"set_shape", "uu", nil}}
wp_cursor_shape_device_v1_interface := wl_interface {
    name         = "wp_cursor_shape_device_v1",
    version      = 2,
    method_count = len(wp_cursor_shape_device_v1_requests),
    methods      = raw_data(wp_cursor_shape_device_v1_requests[:]),
}

// --- requests --------------------------------------------------------------

wp_viewporter_destroy :: proc "contextless" (viewporter: ^wp_viewporter) {
    wl_proxy_marshal_flags((^wl_proxy)(viewporter), 0, nil, version_of(viewporter), WL_MARSHAL_FLAG_DESTROY)
}

wp_viewporter_get_viewport :: proc "contextless" (viewporter: ^wp_viewporter, surface: ^wl_surface) -> ^wp_viewport {
    WP_VIEWPORTER_GET_VIEWPORT :: 1
    return (^wp_viewport)(
        wl_proxy_marshal_flags(
            (^wl_proxy)(viewporter),
            WP_VIEWPORTER_GET_VIEWPORT,
            &wp_viewport_interface,
            version_of(viewporter),
            0,
            rawptr(nil),
            surface,
        ),
    )
}

wp_viewport_destroy :: proc "contextless" (viewport: ^wp_viewport) {
    wl_proxy_marshal_flags((^wl_proxy)(viewport), 0, nil, version_of(viewport), WL_MARSHAL_FLAG_DESTROY)
}

// Double-buffered: applies on the next commit.
wp_viewport_set_destination :: proc "contextless" (viewport: ^wp_viewport, width, height: i32) {
    WP_VIEWPORT_SET_DESTINATION :: 2
    wl_proxy_marshal_flags(
        (^wl_proxy)(viewport),
        WP_VIEWPORT_SET_DESTINATION,
        nil,
        version_of(viewport),
        0,
        width,
        height,
    )
}

wp_fractional_scale_manager_v1_destroy :: proc "contextless" (manager: ^wp_fractional_scale_manager_v1) {
    wl_proxy_marshal_flags((^wl_proxy)(manager), 0, nil, version_of(manager), WL_MARSHAL_FLAG_DESTROY)
}

wp_fractional_scale_manager_v1_get_fractional_scale :: proc "contextless" (
    manager: ^wp_fractional_scale_manager_v1,
    surface: ^wl_surface,
) -> ^wp_fractional_scale_v1 {
    WP_FRACTIONAL_SCALE_MANAGER_V1_GET_FRACTIONAL_SCALE :: 1
    return (^wp_fractional_scale_v1)(
        wl_proxy_marshal_flags(
            (^wl_proxy)(manager),
            WP_FRACTIONAL_SCALE_MANAGER_V1_GET_FRACTIONAL_SCALE,
            &wp_fractional_scale_v1_interface,
            version_of(manager),
            0,
            rawptr(nil),
            surface,
        ),
    )
}

wp_fractional_scale_v1_destroy :: proc "contextless" (fractional_scale: ^wp_fractional_scale_v1) {
    wl_proxy_marshal_flags(
        (^wl_proxy)(fractional_scale),
        0,
        nil,
        version_of(fractional_scale),
        WL_MARSHAL_FLAG_DESTROY,
    )
}

wp_cursor_shape_manager_v1_destroy :: proc "contextless" (manager: ^wp_cursor_shape_manager_v1) {
    wl_proxy_marshal_flags((^wl_proxy)(manager), 0, nil, version_of(manager), WL_MARSHAL_FLAG_DESTROY)
}

wp_cursor_shape_manager_v1_get_pointer :: proc "contextless" (
    manager: ^wp_cursor_shape_manager_v1,
    pointer: ^wl_pointer,
) -> ^wp_cursor_shape_device_v1 {
    WP_CURSOR_SHAPE_MANAGER_V1_GET_POINTER :: 1
    return (^wp_cursor_shape_device_v1)(
        wl_proxy_marshal_flags(
            (^wl_proxy)(manager),
            WP_CURSOR_SHAPE_MANAGER_V1_GET_POINTER,
            &wp_cursor_shape_device_v1_interface,
            version_of(manager),
            0,
            rawptr(nil),
            pointer,
        ),
    )
}

wp_cursor_shape_device_v1_destroy :: proc "contextless" (device: ^wp_cursor_shape_device_v1) {
    wl_proxy_marshal_flags((^wl_proxy)(device), 0, nil, version_of(device), WL_MARSHAL_FLAG_DESTROY)
}

// `serial` must be the one from the latest wl_pointer.enter.
wp_cursor_shape_device_v1_set_shape :: proc "contextless" (
    device: ^wp_cursor_shape_device_v1,
    serial: u32,
    shape: u32,
) {
    WP_CURSOR_SHAPE_DEVICE_V1_SET_SHAPE :: 1
    wl_proxy_marshal_flags(
        (^wl_proxy)(device),
        WP_CURSOR_SHAPE_DEVICE_V1_SET_SHAPE,
        nil,
        version_of(device),
        0,
        serial,
        shape,
    )
}
