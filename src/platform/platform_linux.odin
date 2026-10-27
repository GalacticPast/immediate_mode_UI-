package platform

import "core:fmt"
import "core:sys/linux"
import "core:time"
import gl "vendor:OpenGL"
import egl "vendor:egl"
import wl "wayland"

Platform_Linux_State :: struct {
    /* Globals */
    display:                     ^wl.display,
    registry:                    ^wl.registry,
    proxy:                       ^wl.proxy,
    compositor:                  ^wl.compositor,
    surface:                     ^wl.surface,
    seat:                        ^wl.seat,


    // objects
    xdg_wm_base:                 ^wl.xdg_wm_base,
    xdg_surface:                 ^wl.xdg_surface,
    xdg_toplevel:                ^wl.xdg_toplevel,
    xkb_context:                 ^wl.xkb_context,
    xkb_state:                   ^wl.xkb_state,
    xkb_keymap:                  ^wl.xkb_keymap,
    keyboard:                    ^wl.keyboard,
    pointer:                     ^wl.pointer,
    wp_viewporter:               ^wl.wp_viewporter,
    wp_fractional_scale_manager: ^wl.wp_fractional_scale_manager_v1,
    wp_fractional_scale:         ^wl.wp_fractional_scale_v1,
    wp_viewport:                 ^wl.wp_viewport,

    // window specific
    egl_context:                 egl.Context,
    egl_display:                 egl.Display,
    egl_window:                  ^wl.egl_window,
    egl_surface:                 egl.Surface,
    egl_config:                  egl.Config,

    // idk what this is for now
    callback:                    ^wl.callback,
    output:                      ^wl.output,

    // surface
    width:                       i32,
    height:                      i32,
    display_scale:               f32,

    // idk if this should be here at all
    deadline:                    time.Tick,
}
@(private = "file")
p_l_state: Platform_Linux_State

k_listener: wl.keyboard_listener = {
    keymap = proc "c" (data: rawptr, keyboard: ^wl.keyboard, format: u32, fd: i32, size: u32) {
        defer (linux.close(cast(linux.Fd)fd))
        map_shm, err := linux.mmap(0, (uint)(size), {.READ}, {.PRIVATE}, cast(linux.Fd)fd, 0)
        if err != .NONE {
            // well tf am I supposed to do
            return
        }
        defer (linux.munmap(map_shm, (uint)(size)))
        keymap := wl.xkb_keymap_new_from_string(
            p_l_state.xkb_context,
            cast(cstring)map_shm,
            wl.XKB_KEYMAP_FORMAT_TEXT_V1,
            wl.XKB_KEYMAP_COMPILE_NO_FLAGS,
        )
        x_state := wl.xkb_state_new(keymap)
        wl.xkb_keymap_unref(p_l_state.xkb_keymap)
        wl.xkb_state_unref(p_l_state.xkb_state)

        p_l_state.xkb_keymap = keymap
        p_l_state.xkb_state = x_state
    },
    enter = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial: u32, surface: ^wl.surface, keys: ^wl.array) {  },
    leave = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial: u32, surface: ^wl.surface) {  },
    key = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial, time, key, state: u32) {
        // I have no idea why I need to add 8 but the docs say so I guess
        // https://wayland.freedesktop.org/docs/html/apa.html#protocol-spec-wl_keyboard
        ctx := p_state.t_context
        if ctx == nil do return
        // set the context
        context = ctx^

        keycode := key + 8
        sym := wl.xkb_state_key_get_one_sym(p_l_state.xkb_state, keycode)
        //@info: incomplete
        k_type := translate_key_code(sym)
        e := new(Event) // @perf: pointer dangling
        e.key = k_type

        switch state {
            case 0:
                e.type = .KEY_RELEASE
            // idk how to do key repeats for now
            case 1, 2:
                e.type = .KEY_PRESS
            case:
                e.type = .NONE
        }
        push_event(e)
    },
    modifiers = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial, depressed, latched, locked, group: u32) {  },
    repeat_info = proc "c" (data: rawptr, keyboard: ^wl.keyboard, rate, delay: i32) {  },
}

// Events up to version 10. Which ones arrive depends on the seat version we bind.
BTN_LEFT :: 0x110
BTN_RIGHT :: 0x111
BTN_MIDDLE :: 0x112

p_listener: wl.pointer_listener = {
    enter = proc "c" (data: rawptr, pointer: ^wl.pointer, serial: u32, surface: ^wl.surface, x, y: wl.fixed) {  },
    leave = proc "c" (data: rawptr, pointer: ^wl.pointer, serial: u32, surface: ^wl.surface) {  },
    motion = proc "c" (data: rawptr, pointer: ^wl.pointer, time: u32, x, y: wl.fixed) {
        mouse_x := wl.fixed_to_f32(x)
        mouse_y := wl.fixed_to_f32(y)

        ctx := p_state.t_context
        if ctx == nil do return
        // set the context
        context = ctx^
        e := new(Event) // @perf:
        e.pos = {i32(mouse_x), i32(mouse_y)}
        e.type = .MOUSE_MOVE
        push_event(e)
    },
    button = proc "c" (data: rawptr, pointer: ^wl.pointer, serial, time, button, state: u32) {
        ctx := p_state.t_context
        if ctx == nil do return
        // set the context
        context = ctx^
        e := new(Event) // @perf:
        e.type = .MOUSE_PRESS
        e.key = cast(Key_Type)button
        push_event(e)
    },
    axis = proc "c" (data: rawptr, pointer: ^wl.pointer, time, axis: u32, value: wl.fixed) {  },
    frame = proc "c" (data: rawptr, pointer: ^wl.pointer) {  },                                             // v5
    axis_source = proc "c" (data: rawptr, pointer: ^wl.pointer, axis_source: u32) {  },                     // v5
    axis_stop = proc "c" (data: rawptr, pointer: ^wl.pointer, time, axis: u32) {  },                        // v5
    axis_discrete = proc "c" (data: rawptr, pointer: ^wl.pointer, axis: u32, discrete: i32) {  },           // v5-7
    axis_value120 = proc "c" (data: rawptr, pointer: ^wl.pointer, axis: u32, value120: i32) {  },           // v8
    axis_relative_direction = proc "c" (data: rawptr, pointer: ^wl.pointer, axis, direction: u32) {  },     // v9
    warp = proc "c" (data: rawptr, pointer: ^wl.pointer, x, y: wl.fixed) {  },                              // v10
}

x_base_listener: wl.xdg_wm_base_listener = {
    ping = proc "c" (data: rawptr, wm_base: ^wl.xdg_wm_base, serial: u32) {
        wl.xdg_wm_base_pong(wm_base, serial)
    },
}
w_seat_listener: wl.seat_listener = {
    capabilities = proc "c" (data: rawptr, seat: ^wl.seat, capabilities: u32) {
        keyboard := capabilities & wl.SEAT_CAPABILITY_KEYBOARD
        mouse := capabilities & wl.SEAT_CAPABILITY_POINTER

        if keyboard == wl.SEAT_CAPABILITY_KEYBOARD {
            p_l_state.keyboard = wl.seat_get_keyboard(p_l_state.seat)
            wl.add_listener(p_l_state.keyboard, &k_listener, nil)
        }
        if mouse == wl.SEAT_CAPABILITY_POINTER {
            p_l_state.pointer = wl.seat_get_pointer(p_l_state.seat)
            wl.add_listener(p_l_state.pointer, &p_listener, nil)
        }

    },
    name = proc "c" (data: rawptr, seat: ^wl.seat, name: cstring) {  },
}


r_listener: wl.registry_listener = {
    global = proc "c" (data: rawptr, registry: ^wl.registry, name: u32, interface: cstring, version: u32) {
        switch (interface) {
            case wl.compositor_interface.name:
                p_l_state.compositor = cast(^wl.compositor)wl.registry_bind(
                    registry,
                    name,
                    &wl.compositor_interface,
                    version,
                )
            case wl.xdg_wm_base_interface.name:
                p_l_state.xdg_wm_base = cast(^wl.xdg_wm_base)wl.registry_bind(
                    registry,
                    name,
                    &wl.xdg_wm_base_interface,
                    version,
                )
                wl.add_listener(p_l_state.xdg_wm_base, &x_base_listener, &p_l_state)
            case wl.seat_interface.name:
                p_l_state.seat = cast(^wl.seat)wl.registry_bind(registry, name, &wl.seat_interface, version)
                wl.add_listener(p_l_state.seat, &w_seat_listener, &p_l_state)
            case wl.wp_viewporter_interface.name:
                p_l_state.wp_viewporter = cast(^wl.wp_viewporter)wl.registry_bind(
                    registry,
                    name,
                    &wl.wp_viewporter_interface,
                    version,
                )
            case wl.wp_fractional_scale_manager_v1_interface.name:
                p_l_state.wp_fractional_scale_manager = cast(^wl.wp_fractional_scale_manager_v1)wl.registry_bind(
                    registry,
                    name,
                    &wl.wp_fractional_scale_manager_v1_interface,
                    version,
                )

        }
    },
    global_remove = proc "c" (data: rawptr, registry: ^wl.registry, name: u32) {

    },
}

xdg_s_listener: wl.xdg_surface_listener = {
    configure = proc "c" (data: rawptr, surface: ^wl.xdg_surface, serial: u32) {
        wl.xdg_surface_ack_configure(p_l_state.xdg_surface, serial)
        wl.surface_commit(p_l_state.surface)
    },
}


xdg_t_listener: wl.xdg_toplevel_listener = {
    configure = proc "c" (data: rawptr, toplevel: ^wl.xdg_toplevel, width, height: i32, states: ^wl.array) {
        if width != 0 && height != 0 {
            p_l_state.width = width
            p_l_state.height = height
        }
    },
    close = proc "c" (data: rawptr, toplevel: ^wl.xdg_toplevel) {
        // closing the window
        if p_state.t_context == nil {
            return
        }
        context = p_state.t_context^
        e := new(Event) // @perf: dangling
        e.type = .WINDOW_CLOSE
        push_event(e)
    },
    configure_bounds = proc "c" (data: rawptr, toplevel: ^wl.xdg_toplevel, width, height: i32) {  },
    wm_capabilities = proc "c" (data: rawptr, toplevel: ^wl.xdg_toplevel, capabilities: ^wl.array) {  },
}

wp_fractional_scale_listener: wl.wp_fractional_scale_v1_listener = {
    // The scale numerator over a denominator of 120, so 1.5 arrives as 180.
    preferred_scale = proc "c" (data: rawptr, fractional_scale: ^wl.wp_fractional_scale_v1, scale: u32) {
        p_l_state.display_scale = (f32)(scale) / 120.0
    },
}

startup :: proc(width, height: i32) -> (ok: bool) {

    // for now @temp
    p_l_state.width = width
    p_l_state.height = height

    p_l_state.display = wl.display_connect(nil)
    if p_l_state.display == nil {
        fmt.eprintln("Error: Failed to connect the display to wayland")
        return false
    }
    p_l_state.registry = wl.display_get_registry(p_l_state.display)
    if p_l_state.registry == nil {
        fmt.eprintln("Error: Failed to get the registry")
        return false
    }

    p_l_state.xkb_context = wl.xkb_context_new(wl.XKB_CONTEXT_NO_FLAGS)
    if p_l_state.xkb_context == nil {
        fmt.eprintln("Error: Failed to get xkb context")
        return false
    }

    wl.add_listener(p_l_state.registry, &r_listener, &p_l_state)

    wl.display_roundtrip(p_l_state.display)

    p_l_state.surface = wl.compositor_create_surface(p_l_state.compositor)
    if p_l_state.surface == nil {
        fmt.eprintln("Error failed to get surface")
        return false
    }

    p_l_state.xdg_surface = wl.xdg_wm_base_get_xdg_surface(p_l_state.xdg_wm_base, p_l_state.surface)
    if p_l_state.xdg_surface == nil {
        fmt.eprintln("Error failed to get xdg surface")
        return false
    }

    wl.add_listener(p_l_state.xdg_surface, &xdg_s_listener, &p_l_state)

    p_l_state.xdg_toplevel = wl.xdg_surface_get_toplevel(p_l_state.xdg_surface)
    if p_l_state.xdg_toplevel == nil {
        fmt.eprintln("Error failed to get xdg toplevel")
        return false
    }

    wl.add_listener(p_l_state.xdg_toplevel, &xdg_t_listener, &p_l_state)

    wl.xdg_toplevel_set_title(p_l_state.xdg_toplevel, "odin odin odin")
    wl.xdg_toplevel_set_app_id(p_l_state.xdg_toplevel, "odin odin odin")

    wl.xdg_toplevel_set_min_size(p_l_state.xdg_toplevel, width, height)
    wl.xdg_toplevel_set_max_size(p_l_state.xdg_toplevel, width, height)

    if p_l_state.wp_viewporter != nil {
        p_l_state.wp_viewport = wl.wp_viewporter_get_viewport(p_l_state.wp_viewporter, p_l_state.surface)
        wl.wp_viewport_set_destination(p_l_state.wp_viewport, width, height)
    }

    if p_l_state.wp_fractional_scale_manager != nil {
        p_l_state.wp_fractional_scale = wl.wp_fractional_scale_manager_v1_get_fractional_scale(
            p_l_state.wp_fractional_scale_manager,
            p_l_state.surface,
        )
        wl.add_listener(p_l_state.wp_fractional_scale, &wp_fractional_scale_listener, &p_l_state)
    }

    wl.surface_commit(p_l_state.surface)

    // opengl

    p_l_state.egl_display = egl.GetPlatformDisplay(.WAYLAND_KHR, p_l_state.display, nil)
    if p_l_state.egl_display == egl.NO_DISPLAY {
        fmt.eprintln("Error failed to get egl display")
        return false
    }
    major, minor: i32

    result: b32 = egl.Initialize(p_l_state.egl_display, &major, &minor)
    if result == false {
        fmt.eprintfln("Cannot initialize EGL display: Error: %d", egl.GetError())
        return false
    }
    if major < 1 || (major == 1 && minor < 3) {
        fmt.eprintln("EGL version 4.3 or higher required")
        return false
    }

    result = egl.BindAPI(egl.OPENGL_API)
    if result == false {
        fmt.eprintfln("Coulndnt bind OPENGL API : Error: %d", egl.GetError())
        return false
    }
    config_attribs: []i32 = {
        egl.SURFACE_TYPE,
        egl.WINDOW_BIT,
        egl.CONFORMANT,
        egl.OPENGL_BIT,
        egl.RENDERABLE_TYPE,
        egl.OPENGL_BIT,
        egl.COLOR_BUFFER_TYPE,
        egl.RGB_BUFFER,
        egl.RED_SIZE,
        8,
        egl.GREEN_SIZE,
        8,
        egl.BLUE_SIZE,
        8,
        egl.DEPTH_SIZE,
        24,
        egl.STENCIL_SIZE,
        8,
        egl.NONE,
    }
    egl_config_count: i32 = 0

    result = egl.ChooseConfig(
        p_l_state.egl_display,
        raw_data(config_attribs),
        &p_l_state.egl_config,
        1,
        &egl_config_count,
    )
    if result == false {
        fmt.eprintfln("Cannot choose egl config. error: %d\n", egl.GetError())
        return false
    }
    if egl_config_count != 1 {
        fmt.eprintfln("Got more than one config %d\n", egl_config_count)
        return false
    }

    p_l_state.egl_window = wl.egl_window_create(p_l_state.surface, p_l_state.width, p_l_state.height)

    if p_l_state.egl_window == nil {
        fmt.eprintln("Failed to create wl_egl_window!")
        return false
    }

    surface_attributes: []i32 = {egl.RENDER_BUFFER, egl.BACK_BUFFER, egl.NONE}

    p_l_state.egl_surface = egl.CreateWindowSurface(
        p_l_state.egl_display,
        p_l_state.egl_config,
        cast(egl.NativeWindowType)p_l_state.egl_window,
        raw_data(surface_attributes),
    )

    if p_l_state.egl_surface == egl.NO_SURFACE {
        fmt.eprintfln("Cannot create EGL surface. ERROR: %d", egl.GetError())
        return false
    }

    context_attributes: []i32 = {
        egl.CONTEXT_MAJOR_VERSION,
        4,
        egl.CONTEXT_MINOR_VERSION,
        5,
        egl.CONTEXT_OPENGL_PROFILE_MASK,
        egl.CONTEXT_OPENGL_CORE_PROFILE_BIT,
        egl.NONE,
    }

    p_l_state.egl_context = egl.CreateContext(
        p_l_state.egl_display,
        p_l_state.egl_config,
        egl.NO_CONTEXT,
        raw_data(context_attributes),
    )
    if p_l_state.egl_context == egl.NO_CONTEXT {
        fmt.eprintfln("Cannot create EGL context, OpenGL 4.5 not supported? ERROR:%d", egl.GetError())
        return false
    }

    egl_make_current: b32 = egl.MakeCurrent(
        p_l_state.egl_display,
        p_l_state.egl_surface,
        p_l_state.egl_surface,
        p_l_state.egl_context,
    )

    if !egl_make_current {
        fmt.eprintln("Failed to make context current")
        return false
    }

    // The compositor sends preferred_scale only after the surface has shown a frame, so show one frame and
    // then read the events it sent back.
    egl.SwapBuffers(p_l_state.egl_display, p_l_state.egl_surface)
    wl.display_roundtrip(p_l_state.display)

    if p_l_state.display_scale != 1.0 {
        wl.egl_window_resize(
            p_l_state.egl_window,
            i32(f32(width) * p_l_state.display_scale),
            i32(f32(height) * p_l_state.display_scale),
            0,
            0,
        )
    }

    gl.load_up_to(4, 5, egl.gl_set_proc_address)

    fmt.println("Opengl initialization sucessful.")

    wl.surface_commit(p_l_state.surface)

    // request the first frame deadline right here so that we dont sleep on it
    request_deadline(time.tick_now())
    return true

}

dispatch :: proc() -> bool {
    defer { p_l_state.deadline = {} }
    result: i32 = wl.display_prepare_read(p_l_state.display)
    if result == -1 {
        result = wl.display_dispatch_pending(p_l_state.display)
        return result == -1 ? false : true
    }
    wl.display_flush(p_l_state.display)

    raw_fd: linux.Fd = cast(linux.Fd)wl.display_get_fd(p_l_state.display)
    fds := []linux.Poll_Fd{{fd = raw_fd, events = {.IN}}}

    ready, err := linux.poll(fds, poll_timeout_ms(p_l_state.deadline))
    if err != .NONE && err != .EINTR {
        fmt.eprintln("Linux poll failed ", err)
        wl.display_cancel_read(p_l_state.display)
        return false
    }

    if ready > 0 {
        // also fails here if the compositor hung up (ERR / HUP)
        if wl.display_read_events(p_l_state.display) == -1 {
            return false
        }
    } else {
        // timed out or interrupted by a signal, nothing to read
        wl.display_cancel_read(p_l_state.display)
    }

    result = wl.display_dispatch_pending(p_l_state.display)
    return result == -1 ? false : true
}

request_deadline :: proc(deadline: time.Tick) {
    p_l_state.deadline = deadline
}

swap_buffers :: proc() {
    egl.SwapBuffers(p_l_state.egl_display, p_l_state.egl_surface)
}

get_display_scale :: proc() -> f32 {
    return p_l_state.display_scale
}

// physical framebuffer size
get_framebuffer_size :: proc() -> (i32, i32) {
    return cast(i32)(cast(f32)p_l_state.width * p_l_state.display_scale),
        cast(i32)(cast(f32)p_l_state.height * p_l_state.display_scale)
}

get_window_size :: proc() -> (i32, i32) {
    return p_l_state.width, p_l_state.height
}


translate_key_code :: proc "contextless" (xkb_key: u32) -> Key_Type {
    switch (xkb_key) {
        case wl.XKB_KEY_Escape:
            return .ESCAPE
        case wl.XKB_KEY_a:
            return .A
        case wl.XKB_KEY_b:
            return .B
        case wl.XKB_KEY_c:
            return .C
        case wl.XKB_KEY_d:
            return .D
        case wl.XKB_KEY_e:
            return .E
        case wl.XKB_KEY_f:
            return .F
        case wl.XKB_KEY_g:
            return .G
        case wl.XKB_KEY_h:
            return .H
        case wl.XKB_KEY_i:
            return .I
        case wl.XKB_KEY_j:
            return .J
        case wl.XKB_KEY_k:
            return .K
        case wl.XKB_KEY_l:
            return .L
        case wl.XKB_KEY_m:
            return .M
        case wl.XKB_KEY_n:
            return .N
        case wl.XKB_KEY_o:
            return .O
        case wl.XKB_KEY_p:
            return .P
        case wl.XKB_KEY_q:
            return .Q
        case wl.XKB_KEY_r:
            return .R
        case wl.XKB_KEY_s:
            return .S
        case wl.XKB_KEY_t:
            return .T
        case wl.XKB_KEY_u:
            return .U
        case wl.XKB_KEY_v:
            return .V
        case wl.XKB_KEY_w:
            return .W
        case wl.XKB_KEY_x:
            return .X
        case wl.XKB_KEY_y:
            return .Y
        case wl.XKB_KEY_z:
            return .Z
        case wl.XKB_KEY_Left:
            return .LEFT
        case wl.XKB_KEY_Up:
            return .UP
        case wl.XKB_KEY_Right:
            return .RIGHT
        case wl.XKB_KEY_Down:
            return .DOWN
        case wl.XKB_KEY_space:
            return .SPACE
        case wl.XKB_KEY_KP_0:
            return .NUMPAD0
        case wl.XKB_KEY_KP_1:
            return .NUMPAD1
        case wl.XKB_KEY_KP_2:
            return .NUMPAD2
        case wl.XKB_KEY_KP_3:
            return .NUMPAD3
        case wl.XKB_KEY_KP_4:
            return .NUMPAD4
        case wl.XKB_KEY_KP_5:
            return .NUMPAD5
        case wl.XKB_KEY_KP_6:
            return .NUMPAD6
        case wl.XKB_KEY_KP_7:
            return .NUMPAD7
        case wl.XKB_KEY_KP_8:
            return .NUMPAD8
        case wl.XKB_KEY_KP_9:
            return .NUMPAD9
        case wl.XKB_KEY_Shift_L:
            return .LSHIFT
        case wl.XKB_KEY_Shift_R:
            return .RSHIFT
        case wl.XKB_KEY_Control_L:
            return .LCONTROL
        case wl.XKB_KEY_Control_R:
            return .RCONTROL
        case wl.XKB_KEY_Caps_Lock:
            return .CAPITAL
        case wl.XKB_KEY_Alt_L:
            return .LALT
        case wl.XKB_KEY_Alt_R:
            return .RALT
    }
    return .MAX_KEYS
}
