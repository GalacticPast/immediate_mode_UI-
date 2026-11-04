package main
import "core:fmt"
import "core:os"
import "text"
import ui "ui"

import gl "vendor:OpenGL"

import pl "platform"
import r "renderer"

// A zero-width wrapper lets the first branch be built first while placing
// both branches at the same x coordinate.
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
                if ui.box(ui.Box_Desc{v_size = {type = .FIXED, value = 26}, flags = {.NONE}, color = {1, 1, 0}}) {  }
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

    if !pl.startup(900, 800) {
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

    res: bool = false
    first_menu_open: bool = false
    second_menu_open: bool = false
    last_action := "No button clicked"
    mouse_pos: pl.Vector2
    have_mouse_pos := false
    option: u32 = 0
    red: f32 = 0
    header: bool = false
    for run {
        list := pl.get_events()
        same_frame_click := false
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
                case .KEY_PRESS:
                    if e.key == .SPACE {
                        same_frame_click = have_mouse_pos
                        last_action = "Space sent: no button clicked"
                        eat = e
                    }
                case .MOUSE_MOVE:
                    mouse_pos = e.pos
                    have_mouse_pos = true
            }
            e = e.next
            if eat != nil {
                pl.eat_event(&list, eat)
            }
        }

        // Space makes the press and release deterministic even on slow frames.
        synthetic_press := pl.Event {
            type = .MOUSE_BTN_PRESSED,
            key  = .BTN_LEFT,
            pos  = mouse_pos,
        }
        synthetic_release := pl.Event {
            type = .MOUSE_BTN_RELEASED,
            key  = .BTN_LEFT,
            pos  = mouse_pos,
        }
        if same_frame_click {
            synthetic_press.prev = list.tail
            synthetic_press.next = &synthetic_release
            synthetic_release.prev = &synthetic_press
            if list.tail != nil {
                list.tail.next = &synthetic_press
            } else {
                list.head = &synthetic_press
            }
            list.tail = &synthetic_release
            list.length += 2
        }

        if ui.build(list) {
            description := ui.Box_Desc {
                h_size = {type = .BASED_ON_PARENT_PCT, value = 1},
                v_size = {type = .BASED_ON_PARENT_PCT, value = 1},
            }
            if ui.panel("panel", description) {
                ui.label("INPUT: click overlapping menu items; status should name the item")
                ui.label("Menu built before underlying button")
                overlap_check(true, &first_menu_open, &last_action)
                ui.label("Underlying button built before menu")
                overlap_check(false, &second_menu_open, &last_action)
                ui.label(last_action)
                ui.label("Hover, hold, right-click, drag in; Space sends press and release together")
                if ui.button("Reset click status") {
                    last_action = "No button clicked"
                }

                ui.label("LAYOUT: colored boxes should stack without overlap")
                if ui.row() {
                    if ui.panel(
                        "Horizontal sample",
                        ui.Box_Desc{children_layout_axis = .HORIZONTAL, color = {0.1, 0.1, 0.1}},
                    ) {
                        if ui.box(
                            ui.Box_Desc {
                                h_size = {type = .FIXED, value = 40},
                                v_size = {type = .FIXED, value = 20},
                                color = {0.8, 0.3, 0.2},
                            },
                        ) {  }
                        if ui.box(
                            ui.Box_Desc {
                                h_size = {type = .FIXED, value = 25},
                                v_size = {type = .FIXED, value = 15},
                                color = {0.2, 0.5, 0.8},
                            },
                        ) {  }
                    }
                    if ui.panel("Vertical sample", ui.Box_Desc{color = {0.1, 0.1, 0.1}}) {
                        if ui.box(
                            ui.Box_Desc {
                                h_size = {type = .FIXED, value = 40},
                                v_size = {type = .FIXED, value = 20},
                                color = {0.8, 0.3, 0.2},
                            },
                        ) {  }
                        if ui.box(
                            ui.Box_Desc {
                                h_size = {type = .FIXED, value = 25},
                                v_size = {type = .FIXED, value = 15},
                                color = {0.2, 0.5, 0.8},
                            },
                        ) {  }
                    }
                }
                ui.label("PERCENT: blue box is 100 x 30 inside a 200 x 120 panel")
                if ui.panel(
                    "Percentage sample",
                    ui.Box_Desc {
                        h_size = {type = .FIXED, value = 200},
                        v_size = {type = .FIXED, value = 120},
                        color = {0.1, 0.1, 0.1},
                    },
                ) {
                    if ui.box(ui.Box_Desc{flags = {}}) {
                        if ui.box(
                            ui.Box_Desc {
                                h_size = {type = .BASED_ON_PARENT_PCT, value = 0.5},
                                v_size = {type = .BASED_ON_PARENT_PCT, value = 0.25},
                                color = {0.2, 0.5, 0.8},
                            },
                        ) {  }
                    }
                }

                ui.label("WIDGETS")
                if ui.collapsable_header("header", &header) {
                    if ui.panel("large container") {
                        if ui.box(
                            {
                                h_size = {type = .FIXED, value = 80},
                                v_size = {type = .FIXED, value = 50},
                                color = {0.8, 0.4, 0.2},
                            },
                        ) {
                            if ui.button("button") {

                            }
                        }
                    }
                }
                if ui.row() {
                    if ui.panel("small container") {
                        if ui.box(
                            {
                                h_size = {type = .FIXED, value = 30},
                                v_size = {type = .FIXED, value = 25},
                                color = {0.2, 0.5, 0.8},
                            },
                        ) {  }
                    }
                    ui.checkbox("click me", &res)
                }
                if ui.column() {
                    ui.radio("low", &option, 0)
                    ui.radio("medium", &option, 1)
                    ui.radio("high", &option, 2)
                }
                ui.slider("red", &red, 0, 1)
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
                    r.push(cmd.title, cmd.clip.pos, cmd.color, 12, 0)
                case .NONE:
            }
        }
        r.end_command()

        r.render()

        pl.swap_buffers()
        free_all(context.temp_allocator)
    }

}
