package main
import "core:fmt"
import "core:os"
import "text"
import ui "ui"

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

    ui.init()
    defer ui.deinit()

    text.init()
    defer text.deinit()
    glyphs := text.load_font("assets/font/Archivo-Regular.ttf")
    r.init()
    defer r.deinit()
    r.upload_to_gpu(glyphs)

    run := true

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

        if ui.build(list) {
            description := ui.Box_Desc {
                h_size = {type = .BASED_ON_PARENT_PCT, value = 0.5},
                v_size = {type = .BASED_ON_PARENT_PCT, value = 1},
            }
            if ui.panel("panel_2", description) {
                if ui.box({children_layout_axis = .HORIZONTAL}) {
                    if ui.box({children_layout_axis = .VERTICAL}) {
                        ui.label("label")
                        ui.label("label_1")
                    }
                    if ui.button("button_2", {color = {0.3, 0.3, 0}}) {
                        fmt.println("button pressed")
                    }
                }

            }
        }
        ui_draw_commands := ui.build_draw_commands()
        // draw


        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        r.start_command()
        for cmd in ui_draw_commands {
            switch (cmd.type) {
                case .RECTANGLE:
                    r.push({cmd.clip.pos, cmd.clip.dimen}, cmd.color)
                case .TEXT:
                    r.push(cmd.str, cmd.clip.pos, cmd.color, 12, 0)
                case .NONE:
            }
        }
        r.end_command()

        r.render()

        pl.swap_buffers()
        free_all(context.temp_allocator)
    }

}
