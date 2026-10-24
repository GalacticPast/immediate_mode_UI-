package main

import "core:fmt"
import "core:strings"
import ui "ui"

Demo :: struct {
    color:                                   [3]f32,
    exposure, roughness, progress:           f32,
    enabled:                                 bool,
    shading, quality, selected, applied:     int,
    sidebar_width:                           f32,
    color_open, surface_open, name_open:     bool,
    show_inspector, show_window1, show_about: bool,
    name, committed:                         [64]u8,
    name_len, committed_len:                 int,
    applying:                                bool,
    search:                                  [32]u8,
    search_len:                              int,
}

QUALITY := [?]string{"Draft", "Preview", "Final", "Ultra"}

demo_init :: proc(d: ^Demo) {
    d^ = {
        color          = {0.27, 0.55, 0.86},
        roughness      = 0.4,
        enabled        = true,
        quality        = 1,
        sidebar_width  = 230,
        color_open     = true,
        surface_open   = true,
        name_open      = true,
        show_window1   = true,
    }
    d.name_len = copy(d.name[:], "Untitled")
    d.committed_len = copy(d.committed[:], "Untitled")
}

demo_reset :: proc(d: ^Demo) {
    d.color = {0.27, 0.55, 0.86}
    d.exposure, d.roughness = 0, 0.4
}

// The original widget tour, now one tab of the app.
gallery_build :: proc(s: ^ui.State, d: ^Demo) {
    // a pretend job started by Apply, so the progress bar has something to show
    if d.applying {
        d.progress += s.dt * 0.6
        s.animating = true
        if d.progress >= 1 {
            d.progress, d.applying = 0, false
            d.applied += 1
        }
    }

    if ui.row(s, ui.fill(), ui.fill(), "body") {
        demo_sidebar(s, d)
        demo_divider(s, d)
        demo_inspector(s, d)
    }
    demo_windows(s, d)
}

demo_sidebar :: proc(s: ^ui.State, d: ^Demo) {
    side := s.theme.base
    side.background = s.theme.menu_bar.background
    ui.set_next_pref_size(s, ui.px(d.sidebar_width), ui.fill())
    ui.set_next_palette(s, side)
    sidebar := ui.build_box(s, {.Draw_Background, .Clip}, "sidebar")
    // a deferred scope opened in an if condition ends with that if, so the content goes inside it
    if ui.parent(s, sidebar) {
        if ui.panel(s, 8) do demo_sidebar_content(s, d)
    }
}

demo_sidebar_content :: proc(s: ^ui.State, d: ^Demo) {
    ui.label_weak(s, "MATERIALS")
    search := ui.line_edit(s, "search", d.search[:], &d.search_len)
    if ui.tooltip(s, search) do ui.label(s, "Filter the list by name")
    ui.spacer(s, ui.px(6))
    filter := strings.to_lower(string(d.search[:d.search_len]), context.temp_allocator)
    menu_key := ui.key_from_string(0, "material_menu")
    if ui.scroll_region(s, "materials") {
        selected := s.theme.base
        selected.background = selected.accent
        selected.background.a = 0.35
        for i in 0 ..< 40 {
            name := fmt.tprintf("Material %02d", i + 1)
            if len(filter) > 0 && !strings.contains(strings.to_lower(name, context.temp_allocator), filter) do continue
            if d.selected == i {
                ui.set_next_palette(s, selected)
                ui.set_next_flags(s, {.Draw_Background})
            }
            sig := ui.button_flat(s, fmt.tprintf("%s###material%d", name, i))
            if ui.clicked(sig) do d.selected = i
            if ui.right_clicked(sig) {
                d.selected = i
                ui.ctx_menu_open(s, menu_key)
            }
        }
    }
    if ui.ctx_menu(s, menu_key) {
        ui.label_weak(s, fmt.tprintf("Material %02d", d.selected + 1))
        if ui.clicked(ui.menu_item(s, "Select next")) do d.selected = (d.selected + 1) % 40
        if ui.clicked(ui.menu_item(s, "Reset color")) do demo_reset(d)
        if ui.clicked(ui.menu_item(s, "Open in window")) do d.show_inspector = true
    }
}

demo_divider :: proc(s: ^ui.State, d: ^Demo) {
    line := s.theme.base
    line.background = s.theme.base.border
    ui.set_next_pref_size(s, ui.px(4), ui.fill())
    ui.set_next_palette(s, line)
    ui.set_next_hover_cursor(s, .Resize_EW)
    divider := ui.build_box(s, {.Mouse_Clickable, .Draw_Background, .Draw_Hot_Effects}, "divider")
    sig := ui.signal_from_box(s, divider)
    if .Left_Pressed in sig.flags do ui.store_drag_data(s, d.sidebar_width)
    if ui.dragging(sig) do d.sidebar_width = ui.get_drag_data(s, f32) + ui.drag_delta(s).x
    d.sidebar_width = clamp(d.sidebar_width, 150, max(150, s.viewport.x - 420))
}

demo_inspector :: proc(s: ^ui.State, d: ^Demo) {
    if ui.scroll_region(s, "inspector") {
        if ui.panel(s, 16, "content", ui.children_sum()) do demo_inspector_content(s, d)
    }
}

demo_inspector_content :: proc(s: ^ui.State, d: ^Demo) {
    ui.set_next_font_size(s, 22)
    ui.set_next_pref_height(s, ui.px(34))
    ui.label(s, fmt.tprintf("Material %02d - %s", d.selected + 1, string(d.committed[:d.committed_len])))
    ui.label_weak(s, "Boxes rebuilt every frame, laid out and drawn like RAD Debugger's UI")
    ui.spacer(s, ui.px(10))

    ui.expander(s, "Base color", &d.color_open)
    if d.color_open {
        ui.row(s, ui.fill(), ui.children_sum(), "color")
        ui.spacer(s, ui.px(24))
        if ui.column(s, ui.fill(), ui.children_sum()) {
            ui.slider_n(s, "RGB", d.color[:], 0, 1)
            ui.spacer(s, ui.px(6))
            ui.slider(s, "Exposure", &d.exposure, -2, 2)
            ui.labelf(s, "#%02x%02x%02x", u8(d.color.r * 255), u8(d.color.g * 255), u8(d.color.b * 255))
        }
        ui.spacer(s, ui.px(12))
        ui.set_next_pref_size(s, ui.px(96), ui.px(84))
        swatch := ui.color_swatch(s, "swatch", {d.color.r, d.color.g, d.color.b, 1})
        if ui.tooltip(s, swatch) {
            ui.label(s, "Current base color")
            ui.label_weak(s, fmt.tprintf("exposure %+.2f", d.exposure))
        }
    }

    ui.expander(s, "Surface", &d.surface_open)
    if d.surface_open {
        ui.row(s, ui.fill(), ui.children_sum(), "surface")
        ui.spacer(s, ui.px(24))
        if ui.column(s, ui.fill(), ui.children_sum()) {
            ui.slider(s, "Roughness", &d.roughness, 0, 1)
            ui.checkbox(s, "Enable material", &d.enabled)
            ui.label_weak(s, "Shading")
            ui.radio(s, "Flat", &d.shading, 0)
            ui.radio(s, "Smooth", &d.shading, 1)
            ui.radio(s, "Physically based", &d.shading, 2)
            ui.combo(s, "Quality", &d.quality, QUALITY[:])
        }
    }

    ui.expander(s, "Name", &d.name_open)
    if d.name_open {
        ui.row(s, ui.fill(), ui.children_sum(), "naming")
        ui.spacer(s, ui.px(24))
        if ui.column(s, ui.fill(), ui.children_sum()) {
            name := ui.line_edit(s, "name", d.name[:], &d.name_len)
            if ui.committed(name) do d.committed_len = copy(d.committed[:], d.name[:d.name_len])
            ui.label_weak(s, "Click, or Tab + Enter, to edit. Enter commits, Escape stops.")
        }
    }

    ui.spacer(s, ui.px(10))
    ui.set_next_pref_height(s, ui.px(8))
    ui.progress_bar(s, d.progress)
    ui.spacer(s, ui.px(10))
    if ui.row(s, ui.fill(), ui.px(30), "actions") {
        if ui.clicked(ui.button(s, "Reset")) do demo_reset(d)
        ui.spacer(s, ui.px(8))
        if ui.disabled(s, !d.enabled || d.applying) {
            apply := ui.button(s, "Apply")
            if ui.clicked(apply) do d.applying = true
        }
        ui.spacer(s, ui.px(8))
        inspector := ui.button(s, "Inspector window")
        if ui.clicked(inspector) do d.show_inspector = !d.show_inspector
        if ui.tooltip(s, inspector) do ui.label(s, "A floating, movable, resizable window")
    }
    ui.labelf(s, "Applied %d time%s", d.applied, d.applied == 1 ? "" : "s")
}

demo_windows :: proc(s: ^ui.State, d: ^Demo) {
    inspector_pos := ui.Vec2{max(20, s.viewport.x - 340), 90}
    if ui.window(s, "Inspector", {position = inspector_pos, size = {310, 230}}, &d.show_inspector) {
        ui.labelf(s, "Material %02d", d.selected + 1)
        ui.slider_n(s, "RGB", d.color[:], 0, 1)
        ui.checkbox(s, "Enable material", &d.enabled)
        ui.combo(s, "Quality", &d.quality, QUALITY[:])
        if ui.clicked(ui.button(s, "Close")) do d.show_inspector = false
    }

    // The snippet from the C version, in Odin: @(static) locals and a scoped window.
    if ui.window(s, "window 1", {position = {100, 100}, size = {330, 220}}, &d.show_window1) {
        @(static) check := false
        ui.checkbox(s, "Checkbox", &check)
        @(static) choice := -1
        ui.radio(s, "radio 0", &choice, 0)
        ui.radio(s, "radio 1", &choice, 1)
        ui.radio(s, "radio 2", &choice, 2)
        @(static) rgba: [4]f32
        ui.slider_n(s, "color", rgba[:], 0, 255, "%.0f")
    }

    if ui.window(s, "About", {position = {300, 200}, size = {340, 150}, options = {.No_Resize}}, &d.show_about) {
        ui.label(s, "RAD-style box UI in Odin")
        ui.label_weak(s, "Layout, signals and stacks after RAD Debugger (MIT)")
        if ui.clicked(ui.button(s, "OK")) do d.show_about = false
    }
}
