package platform

import "core:fmt"
import "core:sys/linux"
import wl "wayland"

platform_state :: struct {
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
    egl_window:   ^wl.egl_window,

    // idk what this is for now
    callback:     ^wl.callback,
    output:       ^wl.output,
}
@(private = "file")
p_state: platform_state

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
            p_state.xkb_context,
            cast(cstring)map_shm,
            wl.XKB_KEYMAP_FORMAT_TEXT_V1,
            wl.XKB_KEYMAP_COMPILE_NO_FLAGS,
        )
        x_state: ^wl.xkb_state = wl.xkb_state_new(keymap)
        wl.xkb_keymap_unref(p_state.xkb_keymap)
        wl.xkb_state_unref(p_state.xkb_state)

        p_state.xkb_keymap = keymap
        p_state.xkb_state = x_state
    },
    enter = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial: u32, surface: ^wl.surface, keys: ^wl.array) {  },
    leave = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial: u32, surface: ^wl.surface) {  },
    key = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial, time, key, state: u32) {
        keycode := key + 8
        sym: u32 = wl.xkb_state_key_get_one_sym(p_state.xkb_state, key)
        //@info: incomplete
    },
    modifiers = proc "c" (data: rawptr, keyboard: ^wl.keyboard, serial, depressed, latched, locked, group: u32) {  },
    repeat_info = proc "c" (data: rawptr, keyboard: ^wl.keyboard, rate, delay: i32) {  },
}

// Events up to version 10. Which ones arrive depends on the seat version we bind.
p_listener: pointer_listener = {
    enter = proc "c" (data: rawptr, pointer: ^pointer, serial: u32, surface: ^surface, x, y: fixed) {  },
    leave = proc "c" (data: rawptr, pointer: ^pointer, serial: u32, surface: ^surface) {  },
    motion = proc "c" (data: rawptr, pointer: ^pointer, time: u32, x, y: fixed) {  },
    button = proc "c" (data: rawptr, pointer: ^pointer, serial, time, button, state: u32) {  },
    axis = proc "c" (data: rawptr, pointer: ^pointer, time, axis: u32, value: fixed) {  },
    frame = proc "c" (data: rawptr, pointer: ^pointer) {  },                                             // v5
    axis_source = proc "c" (data: rawptr, pointer: ^pointer, axis_source: u32) {  },                     // v5
    axis_stop = proc "c" (data: rawptr, pointer: ^pointer, time, axis: u32) {  },                        // v5
    axis_discrete = proc "c" (data: rawptr, pointer: ^pointer, axis: u32, discrete: i32) {  },           // v5-7
    axis_value120 = proc "c" (data: rawptr, pointer: ^pointer, axis: u32, value120: i32) {  },           // v8
    axis_relative_direction = proc "c" (data: rawptr, pointer: ^pointer, axis, direction: u32) {  },     // v9
    warp = proc "c" (data: rawptr, pointer: ^pointer, x, y: fixed) {  },                                 // v10
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
            p_state.keyboard = wl.seat_get_keyboard(p_state.seat)
            wl.add_listener(p_state.keyboard, &k_listener, nil)
        }

    },
    name = proc "c" (data: rawptr, seat: ^wl.seat, name: cstring) {  },
}


r_listener: wl.registry_listener = {
    global = proc "c" (data: rawptr, registry: ^wl.registry, name: u32, interface: cstring, version: u32) {
        switch (interface) {
            case wl.compositor_interface.name:
                p_state.compositor = cast(^wl.compositor)wl.registry_bind(
                    registry,
                    name,
                    &wl.compositor_interface,
                    version,
                )
            case wl.xdg_wm_base_interface.name:
                p_state.xdg_wm_base = cast(^wl.xdg_wm_base)wl.registry_bind(
                    registry,
                    name,
                    &wl.xdg_wm_base_interface,
                    version,
                )
                wl.add_listener(p_state.xdg_wm_base, &x_base_listener, &p_state)
            case wl.seat_interface.name:
                p_state.seat = cast(^wl.seat)wl.registry_bind(registry, name, &wl.seat_interface, version)
                wl.add_listener(p_state.xdg_wm_base, &w_seat_listener, &p_state)
            case:
        }
    },
    global_remove = proc "c" (data: rawptr, registry: ^wl.registry, name: u32) {

    },
}

startup :: proc() -> (ok: bool) {

    p_state.display = wl.display_connect(nil)
    if p_state.display == nil {
        fmt.eprintln("Error: Failed to connect the display to wayland")
        return false
    }
    p_state.registry = wl.display_get_registry(p_state.display)
    if p_state.registry == nil {
        fmt.eprintln("Error: Failed to get the registry")
        return false
    }

    p_state.xkb_context = wl.xkb_context_new(wl.XKB_CONTEXT_NO_FLAGS)
    if p_state.xkb_context == nil {
        fmt.eprintln("Error: Failed to get xkb context")
        return false
    }

    wl.add_listener(p_state.registry, &r_listener, &p_state)

    return true
}
