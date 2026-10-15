package wayland

// Interface descriptions for the xdg-shell protocol.
//
// libwayland only ships the core protocol, so C projects run
// `wayland-scanner private-code /usr/share/wayland-protocols/stable/xdg-shell/xdg-shell.xml`
// to generate these tables. They are translated by hand here. Request and event order (and so the
// opcodes) must match the XML exactly. Only the object-type slots we need are filled in; we never
// create positioners or popups.

@(private = "file")
get_xdg_surface_types := [2]^interface{&xdg_surface_interface, nil} // [1] = &surface_interface, set in init below
@(private = "file")
get_toplevel_types := [1]^interface{&xdg_toplevel_interface}

// surface_interface is a variable inside libwayland, so its address is only known once the program
// is loaded.
@(init, private = "file")
init_xdg_shell_types :: proc "contextless" () {
    get_xdg_surface_types[1] = &surface_interface
}

@(private = "file")
xdg_wm_base_requests := [?]message {
    {"destroy", "", nil},
    {"create_positioner", "n", nil},
    {"get_xdg_surface", "no", raw_data(get_xdg_surface_types[:])},
    {"pong", "u", nil},
}
@(private = "file")
xdg_wm_base_events := [?]message{{"ping", "u", nil}}

xdg_wm_base_interface := interface {
    name         = "xdg_wm_base",
    version      = 7,
    method_count = len(xdg_wm_base_requests),
    methods      = raw_data(xdg_wm_base_requests[:]),
    event_count  = len(xdg_wm_base_events),
    events       = raw_data(xdg_wm_base_events[:]),
}

@(private = "file")
xdg_surface_requests := [?]message {
    {"destroy", "", nil},
    {"get_toplevel", "n", raw_data(get_toplevel_types[:])},
    {"get_popup", "n?oo", nil},
    {"set_window_geometry", "iiii", nil},
    {"ack_configure", "u", nil},
}
@(private = "file")
xdg_surface_events := [?]message{{"configure", "u", nil}}

xdg_surface_interface := interface {
    name         = "xdg_surface",
    version      = 7,
    method_count = len(xdg_surface_requests),
    methods      = raw_data(xdg_surface_requests[:]),
    event_count  = len(xdg_surface_events),
    events       = raw_data(xdg_surface_events[:]),
}

@(private = "file")
xdg_toplevel_requests := [?]message {
    {"destroy", "", nil},
    {"set_parent", "?o", nil},
    {"set_title", "s", nil},
    {"set_app_id", "s", nil},
    {"show_window_menu", "ouii", nil},
    {"move", "ou", nil},
    {"resize", "ouu", nil},
    {"set_max_size", "ii", nil},
    {"set_min_size", "ii", nil},
    {"set_maximized", "", nil},
    {"unset_maximized", "", nil},
    {"set_fullscreen", "?o", nil},
    {"unset_fullscreen", "", nil},
    {"set_minimized", "", nil},
}
@(private = "file")
xdg_toplevel_events := [?]message {
    {"configure", "iia", nil},
    {"close", "", nil},
    {"configure_bounds", "4ii", nil},
    {"wm_capabilities", "5a", nil},
}

xdg_toplevel_interface := interface {
    name         = "xdg_toplevel",
    version      = 7,
    method_count = len(xdg_toplevel_requests),
    methods      = raw_data(xdg_toplevel_requests[:]),
    event_count  = len(xdg_toplevel_events),
    events       = raw_data(xdg_toplevel_events[:]),
}
