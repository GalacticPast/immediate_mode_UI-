package main
import "core:fmt"
import "core:os"
import pl "platform"
import "text"
import gl "vendor:OpenGL"


// this feels so weird
// comming from 'C' land where I literally had to write everything by hand
// well I wrote everything :)
main :: proc() {
    // the binary lives in bin/, assets/ is next to it. Run from the project root so
    // relative asset paths work no matter where the app is launched from
    exe_dir, err := os.get_executable_directory(context.temp_allocator)
    if err == nil {
        os.set_working_directory(os.dir(exe_dir))
    } else {
        fmt.eprintln("couldnt find the executable directory:", err)
    }

    if !pl.startup(600, 400) {
        return
    }

    // the text shader outputs coverage as alpha
    gl.Enable(gl.BLEND)
    gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)

    display_scale := pl.get_display_scale()
    gl.Viewport(0, 0, cast(i32)(f32(600) * display_scale), cast(i32)((f32(400) * display_scale)))

    text.init()
    defer text.deinit()
    text.load_font("assets/font/Archivo-Regular.ttf")

    run: bool = true
    //position: [2]f32 = {20 * display_scale, 20 * display_scale}
    position: [2]f32 = {0, 0}
    color: [3]f32 = {1, 1, 1}
    font_size: f32 = 80
    wrap_width: f32 = 0.0

    for run {
        list: pl.event_list = pl.get_events()
        e: ^pl.event = list.head
        // how am I going to eat it though ?
        eat: ^pl.event = nil
        for e != nil {
            defer { eat = nil }
            #partial switch e.type {
                case .WINDOW_CLOSE:
                    run = false
                    eat = e
                case .KEY_RELEASE:
                    if e.key == .ESCAPE {
                        run = false
                    }
                    eat = e
            }
            e = e.next
            if eat != nil {
                pl.eat_event(&list, eat)
            }
        }
        // draw
        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        text.push_string("H", position, color, font_size, wrap_width)
        // the egl window is never resized yet, so the framebuffer stays at the startup size
        text.flush(cast(u32)(600.0 * display_scale), cast(u32)(400.0 * display_scale))

        pl.swap_buffers()
        free_all(context.temp_allocator)
    }

}
