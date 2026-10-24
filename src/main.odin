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
    app: App
    app_init(&app)
    defer app_destroy(&app)
    previous := time.tick_now()
    frame_index := 0
    pl.request_deadline(previous)
    for {
        events := pl.get_events()
        quit := false
        for e := events.head; e != nil; e = e.next {
            if e.type == .WINDOW_CLOSE do quit = true
        }
        if quit do break
        now := time.tick_now()
        dt := f32(time.tick_diff(previous, now)) / f32(time.Second)
        previous = now
        width, height := pl.get_window_size()
        inputs := ui_events(events)
        when UI_SMOKE_TEST {
            smoke_before_build(&state, &app, frame_index, &inputs)
        }
        build_start := time.tick_now()
        ui.begin_build(&state, {f32(width), f32(height)}, inputs[:], dt)
        app_build(&state, &app)
        ui.end_build(&state)
        app.build_ms = f32(time.duration_milliseconds(time.tick_since(build_start)))
        if app.quit do break
        pl.set_cursor(pl.Cursor(int(state.cursor)))
        gl.ClearColor(0.075, 0.085, 0.105, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)
        ui_render(state.commands[:])
        when UI_SMOKE_TEST {
            smoke_capture(frame_index)
        }
        pl.swap_buffers()
        // Poll while animating; otherwise the UI sleeps until an input/resize event.
        if state.animating || state.active != {} || UI_SMOKE_TEST {
            pl.request_deadline(time.tick_add(time.tick_now(), 16 * time.Millisecond))
        }
        free_all(context.temp_allocator)
        frame_index += 1
        when UI_SMOKE_TEST {
            if frame_index == SMOKE_FRAMES do break
        }
    }
}
