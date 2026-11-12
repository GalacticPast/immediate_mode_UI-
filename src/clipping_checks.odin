package main

import ui "ui"

// The red areas mark the parts of each button that extend past a clipping ancestor.
// They are drawn first so the test buttons remain above them in draw order.
clipping_checks :: proc(last_action: ^string) {
    screen := ui.Box_Desc {
        h_size = {type = .BASED_ON_PARENT_PCT, value = 1},
        v_size = {type = .BASED_ON_PARENT_PCT, value = 1},
    }
    if ui.panel("Clipping checks", screen) {
        ui.label("CLIPPING CHECKS - C: return to demo; R: reset result")
        ui.label("Hover/click GREEN: target should react. Hover/click RED: it must not react.")
        ui.label("Yellow indicates hover. Click result: ")
        ui.label(last_action^)

        clip_check_label("1. Floating button extends past its parent", {50, 125})
        clip_check_marker({270, 165}, {60, 38})
        if ui.panel(
            "Floating clip parent",
            ui.Box_Desc {
                h_size = {type = .FIXED, value = 220},
                v_size = {type = .FIXED, value = 70},
                pos = {50, 155},
                flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y, .CLIP},
                color = {0.12, 0.12, 0.12},
            },
        ) {
            if ui.button(
                "Floating target",
                ui.Box_Desc {
                    h_size = {type = .FIXED, value = 120, strictness = 1},
                    v_size = {type = .FIXED, value = 38, strictness = 1},
                    pos = {210, 165},
                    flags = {.DRAW_RECT, .DRAW_TEXT, .HOVERABLE, .PRESSABLE, .FLOATING_X, .FLOATING_Y},
                    color = {0.1, 0.55, 0.25},
                },
            ) {
                last_action^ = "Floating target clicked"
            }
        }

        clip_check_label("2. Normal row: strict children overflow the parent", {50, 245})
        clip_check_marker({270, 278}, {63, 38})
        if ui.panel(
            "Row clip parent",
            ui.Box_Desc {
                h_size = {type = .FIXED, value = 220},
                v_size = {type = .FIXED, value = 70},
                pos = {50, 275},
                flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y, .CLIP},
                children_layout_axis = .HORIZONTAL,
                color = {0.12, 0.12, 0.12},
            },
        ) {
            if ui.box(
                ui.Box_Desc {
                    h_size = {type = .FIXED, value = 160, strictness = 1},
                    v_size = {type = .FIXED, value = 38, strictness = 1},
                    flags = {},
                },
            ) {  }
            if ui.button(
                "Row target",
                ui.Box_Desc {
                    h_size = {type = .FIXED, value = 120, strictness = 1},
                    v_size = {type = .FIXED, value = 38, strictness = 1},
                    color = {0.1, 0.55, 0.25},
                },
            ) {
                last_action^ = "Row target clicked"
            }
        }

        clip_check_label("3. Nested: the grandparent clips the button", {50, 365})
        clip_check_marker({230, 410}, {60, 38})
        if ui.panel(
            "Nested clip ancestor",
            ui.Box_Desc {
                h_size = {type = .FIXED, value = 180},
                v_size = {type = .FIXED, value = 70},
                pos = {50, 395},
                flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y, .CLIP},
                color = {0.12, 0.12, 0.12},
            },
        ) {
            if ui.box(
                ui.Box_Desc {
                    h_size = {type = .FIXED, value = 140},
                    v_size = {type = .FIXED, value = 50},
                    pos = {170, 400},
                    flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y},
                    color = {0.1, 0.25, 0.4},
                },
            ) {
                if ui.button(
                    "Nested target",
                    ui.Box_Desc {
                        h_size = {type = .FIXED, value = 110, strictness = 1},
                        v_size = {type = .FIXED, value = 38, strictness = 1},
                        pos = {180, 410},
                        flags = {.DRAW_RECT, .DRAW_TEXT, .HOVERABLE, .PRESSABLE, .FLOATING_X, .FLOATING_Y},
                        color = {0.1, 0.55, 0.25},
                    },
                ) {
                    last_action^ = "Nested target clicked"
                }
            }
        }

        clip_check_label("4. Floating panel: green button should extend beyond the dark panel", {50, 490})
        clip_check_label("Click the green button to the right of the dark panel", {50, 510})
        if ui.panel(
            "Floating panel outer boundary",
            ui.Box_Desc {
                h_size = {type = .FIXED, value = 160},
                v_size = {type = .FIXED, value = 70},
                pos = {50, 535},
                flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y, .CLIP},
                color = {0.12, 0.12, 0.12},
            },
        ) {
            if ui.panel(
                "Floating panel target",
                ui.Box_Desc {
                    h_size = {type = .FIXED, value = 160},
                    v_size = {type = .FIXED, value = 50},
                    pos = {185, 545},
                    flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y, .CLIP},
                    color = {0.1, 0.25, 0.4},
                },
            ) {
                if ui.button(
                    "Floating panel button",
                    ui.Box_Desc {
                        h_size = {type = .FIXED, value = 145, strictness = 1},
                        v_size = {type = .FIXED, value = 32, strictness = 1},
                        color = {0.1, 0.55, 0.25},
                    },
                ) {
                    last_action^ = "Floating panel button clicked"
                }
            }
        }

        clip_check_label("5. Clipped row: green button stops at the blue row", {50, 630})
        clip_check_label("Click inside the row: reacts; outside the row: no reaction", {50, 650})
        if ui.panel(
            "Unclipped row outer boundary",
            ui.Box_Desc {
                h_size = {type = .FIXED, value = 340},
                v_size = {type = .FIXED, value = 70},
                pos = {50, 675},
                flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y, .CLIP},
                color = {0.12, 0.12, 0.12},
            },
        ) {
            if ui.row(
                "clip",
                ui.Box_Desc {
                    h_size = {type = .FIXED, value = 100, strictness = 1},
                    v_size = {type = .FIXED, value = 45, strictness = 1},
                    flags = {.DRAW_RECT, .CLIP},
                    children_layout_axis = .HORIZONTAL,
                    color = {0.1, 0.25, 0.4},
                },
            ) {
                if ui.button(
                    "Unclipped row button",
                    ui.Box_Desc {
                        h_size = {type = .FIXED, value = 180, strictness = 1},
                        v_size = {type = .FIXED, value = 30, strictness = 1},
                        color = {0.1, 0.55, 0.25},
                    },
                ) {
                    last_action^ = "Unclipped row button clicked"
                }
            }
        }
    }
}

clip_check_marker :: proc(pos, dimensions: [2]f32) {
    if ui.box(
        ui.Box_Desc {
            h_size = {type = .FIXED, value = dimensions.x},
            v_size = {type = .FIXED, value = dimensions.y},
            pos = pos,
            flags = {.DRAW_RECT, .FLOATING_X, .FLOATING_Y},
            color = {0.55, 0.12, 0.12},
        },
    ) {  }
}

clip_check_label :: proc(title: string, pos: [2]f32) {
    ui.label(
        title,
        ui.Box_Desc {
            h_size = {type = .FIXED, value = 500},
            v_size = {type = .FIXED, value = 22},
            pos = pos,
            flags = {.DRAW_TEXT, .FLOATING_X, .FLOATING_Y},
            text_algin_flag = .LEFT,
        },
    )
}
