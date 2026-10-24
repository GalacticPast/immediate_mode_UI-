package main

import "core:fmt"
import "core:os"
import "core:time"
import pl "platform"
import r "renderer"
import "text"
import "ui"
import gl "vendor:OpenGL"

UI_SMOKE_TEST :: #config(UI_SMOKE_TEST, false)

main :: proc() {
    exe_dir, err := os.get_executable_directory(context.temp_allocator)
    if err == nil {
        os.set_working_directory(os.dir(exe_dir))
    } else {
        fmt.eprintln("Could not find the executable directory:", err)
    }
    if !pl.startup(1060, 760) do return
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
    text.init()
    defer text.deinit()
    glyphs := text.load_font("assets/font/Archivo-Regular.ttf")
    r.init()
    defer r.deinit()
    r.upload_to_gpu(glyphs)
    state: ui.State
    ui.init(&state, r.calculate_size)
    defer ui.deinit(&state)
    demo := Demo {
        color         = {0.27, 0.55, 0.86},
        sidebar_width = 230,
        enabled       = true,
        scene_open    = true,
    }
    shift_down: bool
    previous := time.tick_now()
    frame_index := 0
    pl.request_deadline(previous)
    for {
        events := pl.get_events()
        quit := false
        for e := events.head; e != nil; e = e.next {
            if e.type == .WINDOW_CLOSE do quit = true
            if e.type == .KEY_PRESS && e.key == .ESCAPE do demo.show_help = false
        }
        if quit do break
        now := time.tick_now()
        dt := f32(time.tick_diff(previous, now)) / f32(time.Second)
        previous = now
        width, height := pl.get_window_size()
        inputs := ui_events(events, &shift_down)
        when UI_SMOKE_TEST {
            smoke_before_build(&state, &demo, frame_index, &inputs)
        }
        ui.begin_build(&state, {f32(width), f32(height)}, inputs[:], dt)
        demo_build(&state, &demo)
        ui.end_build(&state)
        gl.ClearColor(0.075, 0.085, 0.105, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        ui_render(state.commands[:])
        when UI_SMOKE_TEST {
            smoke_capture(frame_index)
        }
        pl.swap_buffers()
        // Poll while animating; otherwise the UI sleeps until an input/resize event.
        if state.animating || state.active != 0 || UI_SMOKE_TEST {
            pl.request_deadline(time.tick_add(time.tick_now(), 16 * time.Millisecond))
        }
        free_all(context.temp_allocator)
        frame_index += 1
        when UI_SMOKE_TEST {
            if frame_index == 7 do break
        }
    }
}
