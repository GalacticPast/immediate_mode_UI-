package main
import "core:fmt"
import "core:os"
import "text"
import gl "vendor:OpenGL"


import pl "platform"
import r "renderer"

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

    f_w, f_h := pl.get_framebuffer_size()
    gl.Viewport(0, 0, f_w, f_h)

    text.init()
    defer text.deinit()
    glyphs := text.load_font("assets/font/Archivo-Regular.ttf")
    r.init()
    defer r.deinit()
    r.upload_to_gpu(glyphs)

    run := true
    //position: [2]f32 = {20 * display_scale, 20 * display_scale}
    position: [2]f32 = {0, 0}
    color: [3]f32 = {1, 1, 1}
    font_size: f32 = 12
    wrap_width: f32 = 0.0

    for run {
        list := pl.get_events()
        e := list.head
        for e != nil {
            eat: ^pl.Event
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

        r.start_command()
        r.push({{100, 100}, {65, 65}}, {0, 0, 0.4})
        r.push("Havavavavavafads;lkfjasdihadkgaskdjgh8oiurijeagndbmn", position, color, font_size, wrap_width)
        r.end_command()

        r.render()

        pl.swap_buffers()
        free_all(context.temp_allocator)
    }

}
