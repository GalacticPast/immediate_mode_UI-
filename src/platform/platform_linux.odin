package platform

import "core:fmt"
import "core:sys/linux"
import gl "vendor:OpenGL"
import egl "vendor:egl"
import wl "wayland"

platform_linux_state :: struct {
    /* Globals */
    display:      ^wl.display,
    registry:     ^wl.registry,
    proxy:        ^wl.proxy,
    compositor:   ^wl.compositor,
    surface:      ^wl.surface,
    seat:         ^wl.seat,
    xdg_wm_base:  ^wl.xdg_wm_base,
    xkb_context:  ^wl.xkb_context,
    xkb_state:    ^wl.xkb_state,
    xkb_keymap:   ^wl.xkb_keymap,
    //objects
    xdg_surface:  ^wl.xdg_surface,
    xdg_toplevel: ^wl.xdg_toplevel,
    keyboard:     ^wl.keyboard,
    pointer:      ^wl.pointer,

    // window specific
    egl_context:  egl.Context,
    egl_display:  egl.Display,
    egl_window:   ^wl.egl_window,
    egl_surface:  egl.Surface,
    egl_config:   egl.Config,

    // idk what this is for now
    callback:     ^wl.callback,
    output:       ^wl.output,

    // surface
    width:        i32,
    height:       i32,
}
@(private = "file")
p_l_state: platform_linux_state

k_listener: wl.keyboard_listener = {
    keymap = proc "c" (data: rawptr, keyboard: ^wl.keyboard, format: u32, fd: i32, size: u32) {
        defer (linux.close(cast(linux.Fd)fd))
        map_shm, err := linux.mmap(0, (uint)(size), {.READ}, {.PRIVATE}, cast(linux.Fd)fd, 0)
        if err != .NONE {
            // well tf am I supposed to do
            return
        }
        defer (linux.munmap(map_shm, (uint)(size)))
        keymap: ^wl.xkb_keymap = wl.xkb_keymap_new_from_string(
            p_l_state.xkb_context,
            cast(cstring)map_shm,
            wl.XKB_KEYMAP_FORMAT_TEXT_V1,
            wl.XKB_KEYMAP_COMPILE_NO_FLAGS,
        )
        x_state: ^wl.xkb_state = wl.xkb_state_new(keymap)
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
        if ctx == nil {
            return
        }
        // set the context
        context = ctx^

        keycode := key + 8
        sym: u32 = wl.xkb_state_key_get_one_sym(p_l_state.xkb_state, keycode)
        //@info: incomplete
        k_type: key_type = translate_key_code(sym)
        e: ^event = new(event)
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
p_listener: wl.pointer_listener = {
    enter = proc "c" (data: rawptr, pointer: ^wl.pointer, serial: u32, surface: ^wl.surface, x, y: wl.fixed) {  },
    leave = proc "c" (data: rawptr, pointer: ^wl.pointer, serial: u32, surface: ^wl.surface) {  },
    motion = proc "c" (data: rawptr, pointer: ^wl.pointer, time: u32, x, y: wl.fixed) {  },
    button = proc "c" (data: rawptr, pointer: ^wl.pointer, serial, time, button, state: u32) {  },
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
        keyboard: u32 = capabilities & wl.SEAT_CAPABILITY_KEYBOARD

        if keyboard == wl.SEAT_CAPABILITY_KEYBOARD {
            p_l_state.keyboard = wl.seat_get_keyboard(p_l_state.seat)
            wl.add_listener(p_l_state.keyboard, &k_listener, nil)
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
            case:
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
        context = p_state.t_context^
        e: ^event = new(event)
        e.type = .WINDOW_CLOSE
        push_event(e)
    },
    configure_bounds = proc "c" (data: rawptr, toplevel: ^wl.xdg_toplevel, width, height: i32) {  },
    wm_capabilities = proc "c" (data: rawptr, toplevel: ^wl.xdg_toplevel, capabilities: ^wl.array) {  },
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

    // if (state->display_scale != 1.0f)
    // {
    //     wl_egl_window_resize(state->egl_window, (s32)(state->width * state->display_scale),
    //                          (s32)(state->height * state->display_scale), 0, 0);
    // }

    gl.load_up_to(4, 5, egl.gl_set_proc_address)

    fmt.println("Opengl initialization sucessful.")

    wl.surface_commit(p_l_state.surface)
    return true

}

dispatch :: proc() -> bool {
    wl.display_flush(p_l_state.display)

    result: i32 = wl.display_dispatch_pending(p_l_state.display)

    return result == -1 ? false : true
}

swap_buffers :: proc() {
    egl.SwapBuffers(p_l_state.egl_display, p_l_state.egl_surface)
}

translate_key_code :: proc "contextless" (xkb_key: u32) -> key_type {
    switch (xkb_key) {
        case wl.XKB_KEY_Escape:
            return .KEY_ESCAPE
        case wl.XKB_KEY_a:
            return .KEY_A
        case wl.XKB_KEY_b:
            return .KEY_B
        case wl.XKB_KEY_c:
            return .KEY_C
        case wl.XKB_KEY_d:
            return .KEY_D
        case wl.XKB_KEY_e:
            return .KEY_E
        case wl.XKB_KEY_f:
            return .KEY_F
        case wl.XKB_KEY_g:
            return .KEY_G
        case wl.XKB_KEY_h:
            return .KEY_H
        case wl.XKB_KEY_i:
            return .KEY_I
        case wl.XKB_KEY_j:
            return .KEY_J
        case wl.XKB_KEY_k:
            return .KEY_K
        case wl.XKB_KEY_l:
            return .KEY_L
        case wl.XKB_KEY_m:
            return .KEY_M
        case wl.XKB_KEY_n:
            return .KEY_N
        case wl.XKB_KEY_o:
            return .KEY_O
        case wl.XKB_KEY_p:
            return .KEY_P
        case wl.XKB_KEY_q:
            return .KEY_Q
        case wl.XKB_KEY_r:
            return .KEY_R
        case wl.XKB_KEY_s:
            return .KEY_S
        case wl.XKB_KEY_t:
            return .KEY_T
        case wl.XKB_KEY_u:
            return .KEY_U
        case wl.XKB_KEY_v:
            return .KEY_V
        case wl.XKB_KEY_w:
            return .KEY_W
        case wl.XKB_KEY_x:
            return .KEY_X
        case wl.XKB_KEY_y:
            return .KEY_Y
        case wl.XKB_KEY_z:
            return .KEY_Z
        case wl.XKB_KEY_Left:
            return .KEY_LEFT
        case wl.XKB_KEY_Up:
            return .KEY_UP
        case wl.XKB_KEY_Right:
            return .KEY_RIGHT
        case wl.XKB_KEY_Down:
            return .KEY_DOWN
        case wl.XKB_KEY_space:
            return .KEY_SPACE
        case wl.XKB_KEY_KP_0:
            return .KEY_NUMPAD0
        case wl.XKB_KEY_KP_1:
            return .KEY_NUMPAD1
        case wl.XKB_KEY_KP_2:
            return .KEY_NUMPAD2
        case wl.XKB_KEY_KP_3:
            return .KEY_NUMPAD3
        case wl.XKB_KEY_KP_4:
            return .KEY_NUMPAD4
        case wl.XKB_KEY_KP_5:
            return .KEY_NUMPAD5
        case wl.XKB_KEY_KP_6:
            return .KEY_NUMPAD6
        case wl.XKB_KEY_KP_7:
            return .KEY_NUMPAD7
        case wl.XKB_KEY_KP_8:
            return .KEY_NUMPAD8
        case wl.XKB_KEY_KP_9:
            return .KEY_NUMPAD9
        case wl.XKB_KEY_Shift_L:
            return .KEY_LSHIFT
        case wl.XKB_KEY_Shift_R:
            return .KEY_RSHIFT
        case wl.XKB_KEY_Control_L:
            return .KEY_LCONTROL
        case wl.XKB_KEY_Control_R:
            return .KEY_RCONTROL
        case wl.XKB_KEY_Caps_Lock:
            return .KEY_CAPITAL
        case wl.XKB_KEY_Alt_L:
            return .KEY_LALT
        case wl.XKB_KEY_Alt_R:
            return .KEY_RALT
    }
    return .KEY_MAX_KEYS
}
