package main
import "core:fmt"
import "core:os"
import "text"
import ui "ui"

import gl "vendor:OpenGL"

import pl "platform"
import r "renderer"

// @note: A zero-width wrapper lets the first branch be built first while placing
// @note: both branches at the same x coordinate.
overlap_check :: proc(menu_first: bool, open: ^bool, last_action: ^string) {
    fixed := ui.Box_Desc {
        h_size = {type = .FIXED, value = 160},
        v_size = {type = .FIXED, value = 26},
    }
    overlay := ui.Box_Desc {
        h_size = {type = .FIXED, value = 0},
        v_size = {type = .FIXED, value = 55},
        flags = {},
    }
    if ui.row() {
        if menu_first {
            if ui.box(overlay) {
                if ui.dropdown("Menu first", open, fixed) {
                    if ui.button("First menu item", fixed) {
                        last_action^ = "Menu-first item clicked"
                    }
                }
            }
            if ui.column() {
                if ui.box(
                    ui.Box_Desc{v_size = {type = .FIXED, value = 26}, flags = {.DRAW_RECT}, color = {1, 0, 1}},
                ) {  }
                if ui.button("Under first menu", fixed) {
                    last_action^ = "Under menu-first clicked"
                }
            }
        } else {
            if ui.box(overlay) {
                if ui.box(
                    {
                        h_size = {type = .FIXED, value = 26},
                        v_size = {type = .FIXED, value = 26},
                        flags = {.DRAW_RECT},
                        color = {1, 1, 0},
                    },
                ) {

                }
                if ui.button("Under second menu", fixed) {
                    last_action^ = "Under menu-second clicked"
                }
            }
            if ui.dropdown("Menu second", open, fixed) {
                if ui.button("Second menu item", fixed) {
                    last_action^ = "Menu-second item clicked"
                }
            }
        }
    }
}

// @note: this feels so weird
// @note: comming from 'C' land where I literally had to write everything by hand
// @note: well I wrote everything :)
main :: proc() {
    // @note: the binary lives in bin/, assets/ is next to it. Run from the project root so
    // @note: relative asset paths work no matter where the app is launched from
    exe_dir, err := os.get_executable_directory(context.temp_allocator)
    if err == nil {
        os.set_working_directory(os.dir(exe_dir))
    } else {
        fmt.eprintln("couldnt find the executable directory:", err)
    }

    if !pl.startup(900, 800) {
        return
    }

    // @note: the text shader outputs coverage as alpha
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
                        eat = e
                    }
            }
            e = e.next
            if eat != nil {
                pl.eat_event(&list, eat)
            }
        }

        // @note: Space makes the press and release deterministic even on slow frames.
        if ui.build(list) {
            description := ui.Box_Desc {
                h_size = {type = .BASED_ON_PARENT_PCT, value = 1},
                v_size = {type = .BASED_ON_PARENT_PCT, value = 1},
            }
            if ui.panel("panel", description) {
                if ui.scroll_region(
                    "view",
                    {
                        h_size = {type = .FIXED, value = 400},
                        v_size = {type = .FIXED, value = 500},
                        flags = {.SCROLLABLE_X, .SCROLLABLE_Y, .OVERFLOW_X, .OVERFLOW_Y},
                    },
                ) {
                    if ui.box(
                        {
                            h_size = {type = .FIXED, value = 1000},
                            v_size = {type = .FIXED, value = 300},
                            color = {0, 1, 0},
                        },
                    ) {
                    }
                    if ui.box(
                        {
                            h_size = {type = .BASED_ON_PARENT_PCT, value = 1},
                            v_size = {type = .FIXED, value = 1900},
                            color = {1, 0, 0},
                        },
                    ) {  }
                }
            }
        }

        ui_draw_commands := ui.build_draw_commands()

        // @note: draw

        gl.ClearColor(0, 0, 0, 1)
        gl.Clear(gl.COLOR_BUFFER_BIT)

        r.start_command()
        for cmd in ui_draw_commands {
            switch (cmd.type) {
                case .RECTANGLE:
                    r.push({cmd.rect.pos, cmd.rect.dimen}, cmd.color, {cmd.clip.pos, cmd.clip.dimen})
                case .TEXT:
                    r.push(cmd.title, cmd.rect.pos, cmd.color, 12, 0, {cmd.clip.pos, cmd.clip.dimen})
                case .NONE:
            }
        }
        r.end_command()

        r.render()

        pl.swap_buffers()
        free_all(context.temp_allocator)
    }

}
