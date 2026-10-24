package main

import "core:fmt"
import ui "ui"

Demo :: struct {
    color: [3]f32,
    sidebar_width: f32,
    enabled, advanced, scene_open, show_help: bool,
    page, material, clicks: int,
    exposure: f32,
}

demo_build :: proc(s: ^ui.State, d: ^Demo) {
    outer := ui.begin_container(s, "workspace", .Y, ui.fill(), ui.fill(), {16, 16}, 12)
    outer.style.background = {0.075, 0.085, 0.105}
    outer.flags += {.Background}

    ui.begin_container(s, "header", .X, ui.fill(), ui.px(58), {}, 12)
    ui.begin_container(s, "heading", .Y, ui.fill(), ui.fill(), {}, 1)
    title := ui.label(s, "BOX LABORATORY")
    title.style.font_size = 22
    title.style.text = {0.92, 0.94, 0.98}
    subtitle := ui.label(s, "Immediate-mode tools / Odin + OpenGL")
    subtitle.style.font_size = 12
    subtitle.style.text = {0.48, 0.55, 0.65}
    ui.end_container(s)
    style := s.style
    style.width, style.height = ui.px(100), ui.px(32)
    ui.push_style(s, style)
    if ui.button(s, "How it works").clicked do d.show_help = true
    ui.pop_style(s)
    ui.end_container(s)

    body := ui.begin_container(s, "body", .X, ui.fill(), ui.fill(), {}, 6)
    max_sidebar := max(f32(150), s.viewport.x-470)
    d.sidebar_width = clamp(d.sidebar_width, 150, max_sidebar)
    sidebar := ui.begin_container(s, "sidebar", .Y, ui.px(d.sidebar_width), ui.fill(), {12, 12}, 8, {.Background, .Border, .Clip})
    sidebar.style.background = {0.10, 0.115, 0.14}
    ui.label(s, "WORKSPACE")
    if ui.button(s, "Color inspector").clicked do d.page = 0
    if ui.button(s, "Layout stress test").clicked do d.page = 1
    ui.checkbox(s, "Show box bounds", &s.debug_bounds)
    if ui.tree_header(s, "Scene collection", &d.scene_open) {
        list := ui.begin_container(s, "objects", .Y, ui.fill(), ui.fill(), {2, 4}, 3, {.Scroll, .Clip})
        list.style.background = {0.08, 0.09, 0.11}
        list.flags += {.Background}
        for i in 0 ..< 40 {
            if ui.button(s, fmt.tprintf("Material %02d###material_%d", i+1, i)).clicked do d.material = i
        }
        ui.end_container(s)
    }
    ui.end_container(s)

    divider := ui.box(s, "divider", {.Background, .Clickable})
    divider.style.width, divider.style.height = ui.px(6), ui.fill()
    divider.style.background = {0.17, 0.22, 0.29}
    if divider.signal.dragging || divider.signal.pressed || divider.signal.released {
        d.sidebar_width = clamp(divider.signal.drag_pos.x-body.rect.pos.x-3, 150, max_sidebar)
        sidebar.style.width = ui.px(d.sidebar_width)
    }
    d.sidebar_width += f32(divider.signal.step)*8

    panel := ui.begin_container(s, "inspector", .Y, ui.fill(), ui.fill(), {18, 16}, 12, {.Background, .Border, .Clip, .Scroll})
    panel.style.background = {0.115, 0.13, 0.16}
    heading := ui.label(s, fmt.tprintf("Material %02d / %s", d.material+1, d.page == 0 ? "Color" : "Layout"))
    heading.style.font_size = 19
    if d.page == 0 {
        ui.label(s, "BASE COLOR")
        ui.begin_container(s, "rgb", .X, ui.fill(), ui.px(106), {}, 14)
        ui.begin_container(s, "channels", .Y, ui.fill(), ui.fill(), {}, 8)
        channel_style := s.style
        channel_style.height = ui.px(30)
        channel_style.accent = {0.95, 0.37, 0.37}
        ui.push_style(s, channel_style)
        ui.slider(s, "Red", &d.color.r, 0, 1)
        ui.pop_style(s)
        channel_style.accent = {0.37, 0.8, 0.49}
        ui.push_style(s, channel_style)
        ui.slider(s, "Green", &d.color.g, 0, 1)
        ui.pop_style(s)
        channel_style.accent = {0.37, 0.61, 0.98}
        ui.push_style(s, channel_style)
        ui.slider(s, "Blue", &d.color.b, 0, 1)
        ui.pop_style(s)
        ui.end_container(s)
        ui.color_preview(s, "preview", d.color, ui.px(120), ui.fill())
        ui.end_container(s)
        info := ui.label(s, fmt.tprintf("RGB  %03d  %03d  %03d", int(d.color.r*255), int(d.color.g*255), int(d.color.b*255)))
        info.style.text = {0.55, 0.64, 0.75}
        ui.checkbox(s, "Enable material", &d.enabled)
        ui.slider(s, "Exposure", &d.exposure, -2, 2)
        ui.begin_container(s, "actions", .X, ui.fill(), ui.px(32), {}, 8)
        if ui.button(s, "Reset").clicked {
            d.color = {0.27, 0.55, 0.86}
            d.exposure = 0
        }
        if ui.button(s, "Apply", !d.enabled).clicked do d.clicks += 1
        ui.button(s, "Unavailable", true)
        ui.end_container(s)
        if ui.tree_header(s, "Advanced settings", &d.advanced) {
            ui.begin_container(s, "advanced", .Y, ui.fill(), ui.children(), {10, 6}, 4, {.Background, .Border})
            ui.label(s, "Preview shading")
            ui.radio(s, "Material 01", &d.material, 0)
            ui.radio(s, "Material 02", &d.material, 1)
            ui.radio(s, "Material 03", &d.material, 2)
            ui.end_container(s)
        }
        ui.label(s, fmt.tprintf("Applied %d time%s", d.clicks, d.clicks == 1 ? "" : "s"))
        ui.label(s, "Tab to focus / arrows to adjust sliders")
    } else {
        ui.label(s, "Rows share space using 1 : 2 : 1 fill weights.")
        for i in 0 ..< 30 {
            ui.begin_container(s, fmt.tprintf("row_%d", i), .X, ui.fill(), ui.px(42), {}, 8)
            for j in 0 ..< 3 {
                b := ui.color_preview(s, fmt.tprintf("cell_%d", j),
                    {0.14+f32(j)*0.04, 0.22+f32(i%4)*0.025, 0.32+f32(j)*0.05},
                    ui.fill(j == 1 ? 2 : 1), ui.fill())
                ui.set_text(s, b, fmt.tprintf("%d / %d", i+1, j+1))
                b.style.text_align = .Center
            }
            ui.end_container(s)
        }
    }
    ui.end_container(s)
    ui.end_container(s)
    status := ui.label(s, fmt.tprintf("%d boxes   |   drag divider to resize   |   wheel to scroll", len(s.order)))
    status.style.font_size = 12
    status.style.text = {0.48, 0.55, 0.65}
    ui.end_container(s)

    if d.show_help {
        ui.push_parent(s, s.root)
        backdrop := ui.begin_container(s, "help_backdrop", .Y, ui.px(s.viewport.x), ui.px(s.viewport.y), {}, 0, {.Floating, .Clickable})
        if backdrop.signal.clicked do d.show_help = false
        popup := ui.begin_container(s, "help", .Y, ui.px(440), ui.children(), {22, 18}, 10, {.Floating, .Background, .Border, .Clickable, .Clip})
        popup.floating_pos = {max(0, (s.viewport.x-440)*0.5), max(0, (s.viewport.y-290)*0.5)}
        popup.style.background = {0.12, 0.15, 0.20}
        ui.label(s, "RAD-STYLE BOX UI")
        ui.label(s, "Each frame rebuilds a tree of reusable boxes.")
        ui.label(s, "Layout resolves sizes, then places children.")
        ui.label(s, "Stable keys retain focus, dragging and scrolling.")
        ui.label(s, "The renderer draws the completed tree in order.")
        if ui.button(s, "Close").clicked do d.show_help = false
        ui.end_container(s)
        ui.end_container(s)
        ui.pop_parent(s)
    }
}
