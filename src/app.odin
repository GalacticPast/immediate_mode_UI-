// The demo application: a debugger for the toy VM, and the original widget gallery.
package main

import "core:fmt"
import ui "ui"

App_Tab :: enum { Debugger, Gallery }

Action :: enum {
    Run_Pause,
    Step,
    Step_100,
    Reset,
    Toggle_Breakpoint,
    Clear_Breakpoints,
    Follow_PC,
    Clear_Output,
    Show_Debugger,
    Show_Gallery,
    Toggle_Theme,
    Toggle_Bounds,
    Quit,
}

ACTION_NAMES := [Action]string {
    .Run_Pause         = "Run / pause",
    .Step              = "Step one instruction",
    .Step_100          = "Step 100 instructions",
    .Reset             = "Reset machine",
    .Toggle_Breakpoint = "Toggle breakpoint on selected line",
    .Clear_Breakpoints = "Clear all breakpoints",
    .Follow_PC         = "Toggle follow PC",
    .Clear_Output      = "Clear output",
    .Show_Debugger     = "Go to debugger",
    .Show_Gallery      = "Go to widget gallery",
    .Toggle_Theme      = "Switch light / dark theme",
    .Toggle_Bounds     = "Show box bounds",
    .Quit              = "Quit",
}

ACTION_KEYS := [Action]string {
    .Run_Pause         = "F5",
    .Step              = "F10",
    .Step_100          = "",
    .Reset             = "Ctrl+R",
    .Toggle_Breakpoint = "F9",
    .Clear_Breakpoints = "",
    .Follow_PC         = "",
    .Clear_Output      = "",
    .Show_Debugger     = "F1",
    .Show_Gallery      = "F2",
    .Toggle_Theme      = "Ctrl+T",
    .Toggle_Bounds     = "",
    .Quit              = "Ctrl+Q",
}

App :: struct {
    tab:          int,
    debugger:     Debugger,
    gallery:      Demo,
    light:        bool,
    palette_open: bool,
    palette_new:  bool, // opened this frame: focus its search field
    query:        [64]u8,
    query_len:    int,
    selected:     int,
    build_ms:     f32, // measured by main around begin_build..end_build
    quit:         bool,
}

app_init :: proc(app: ^App) {
    app^ = {}
    debugger_init(&app.debugger)
    demo_init(&app.gallery)
}

app_destroy :: proc(app: ^App) {
    debugger_destroy(&app.debugger)
}

app_do :: proc(app: ^App, s: ^ui.State, action: Action) {
    d := &app.debugger
    switch action {
        case .Run_Pause: d.running = !d.running
        case .Step: debugger_step(d, s)
        case .Step_100: debugger_step(d, s, 100)
        case .Reset: debugger_reset(d)
        case .Toggle_Breakpoint: d.breakpoints[d.cursor] = !d.breakpoints[d.cursor]
        case .Clear_Breakpoints: d.breakpoints = {}
        case .Follow_PC: d.follow_pc = !d.follow_pc
        case .Clear_Output: clear(&d.vm.output)
        case .Show_Debugger: app.tab = int(App_Tab.Debugger)
        case .Show_Gallery: app.tab = int(App_Tab.Gallery)
        case .Toggle_Theme:
            app.light = !app.light
            s.theme = app.light ? ui.light_theme() : ui.default_theme()
        case .Toggle_Bounds: s.debug_bounds = !s.debug_bounds
        case .Quit: app.quit = true
    }
}

app_build :: proc(s: ^ui.State, app: ^App) {
    // shortcuts first, so they win over whatever widget has focus
    if ui.key_pressed(s, .P, {.Ctrl}) do app_open_palette(app)
    if ui.key_pressed(s, .Q, {.Ctrl}) do app_do(app, s, .Quit)
    if ui.key_pressed(s, .T, {.Ctrl}) do app_do(app, s, .Toggle_Theme)
    if ui.key_pressed(s, .F1) do app_do(app, s, .Show_Debugger)
    if ui.key_pressed(s, .F2) do app_do(app, s, .Show_Gallery)
    // the same keys mean different things on each tab: just an if
    if App_Tab(app.tab) == .Debugger {
        if ui.key_pressed(s, .F5) do app_do(app, s, .Run_Pause)
        if ui.key_pressed(s, .F10) do app_do(app, s, .Step)
        if ui.key_pressed(s, .F9) do app_do(app, s, .Toggle_Breakpoint)
        if ui.key_pressed(s, .R, {.Ctrl}) do app_do(app, s, .Reset)
        debugger_update(&app.debugger, s)
    } else if ui.key_pressed(s, .R, {.Ctrl}) {
        demo_reset(&app.gallery)
    }

    // one background box behind everything, so the theme paints the whole window
    ui.set_next_child_layout_axis(s, .Y)
    ui.set_next_pref_size(s, ui.fill(), ui.fill())
    ui.set_next_palette(s, s.theme.base)
    shell := ui.build_box(s, {.Draw_Background}, "app")
    if ui.parent(s, shell) {
        app_menu_bar(s, app)
        tabs := [?]string{"Debugger", "Widget gallery"} // in App_Tab order
        tab_bar(s, "app_tabs", tabs[:], &app.tab, s.theme.menu_bar)
        switch App_Tab(app.tab) {
            case .Debugger: debugger_build(s, &app.debugger)
            case .Gallery: gallery_build(s, &app.gallery)
        }
        app_status_bar(s, app)
    }
    app_command_palette(s, app)
}

app_menu_bar :: proc(s: ^ui.State, app: ^App) {
    item :: proc(s: ^ui.State, app: ^App, action: Action, name := "") {
        if ui.clicked(ui.menu_item(s, name != "" ? name : ACTION_NAMES[action], ACTION_KEYS[action])) do app_do(app, s, action)
    }
    if ui.menu_bar(s) {
        if ui.menu(s, "File") {
            item(s, app, .Reset)
            ui.separator(s)
            item(s, app, .Quit)
        }
        if ui.menu(s, "Debug") {
            item(s, app, .Run_Pause, app.debugger.running ? "Pause" : "Run")
            item(s, app, .Step)
            item(s, app, .Step_100)
            ui.separator(s)
            item(s, app, .Toggle_Breakpoint)
            item(s, app, .Clear_Breakpoints)
        }
        if ui.menu(s, "View") {
            item(s, app, .Show_Debugger)
            item(s, app, .Show_Gallery)
            ui.separator(s)
            item(s, app, .Toggle_Theme, app.light ? "Dark theme" : "Light theme")
            item(s, app, .Toggle_Bounds, s.debug_bounds ? "Hide box bounds" : "Show box bounds")
            if ui.clicked(ui.menu_item(s, "Command palette", "Ctrl+P")) do app_open_palette(app)
        }
    }
}

app_status_bar :: proc(s: ^ui.State, app: ^App) {
    d := &app.debugger
    ui.set_next_child_layout_axis(s, .X)
    ui.set_next_pref_size(s, ui.fill(), ui.px(24))
    ui.set_next_palette(s, s.theme.menu_bar)
    bar := ui.build_box(s, {.Draw_Background, .Draw_Side_Top}, "status")
    ui.parent(s, bar)
    ui.palette(s, s.theme.menu_bar)
    ui.font_size(s, 12)
    ui.pref_height(s, ui.fill())
    ui.push_pref_width(s, ui.text_dim(14))
    if App_Tab(app.tab) == .Debugger {
        text, color := state_color(d)
        pal := s.theme.menu_bar
        pal.text = color
        ui.set_next_palette(s, pal)
        ui.label(s, text)
        ui.label_weak(s, fmt.tprintf("pc %04X   cycle %d   %.0f ips", d.vm.pc, d.vm.cycles, d.measured_ips))
    } else {
        ui.label_weak(s, "Widget gallery")
    }
    ui.pop_pref_width(s)
    ui.spacer(s, ui.fill())
    ui.set_next_pref_width(s, ui.text_dim(14))
    // the whole interface is rebuilt every frame; this is what it costs
    ui.label_weak(s, fmt.tprintf("%d boxes   build+layout %.2f ms", len(s.built_boxes), app.build_ms))
    ui.set_next_pref_width(s, ui.text_dim(14))
    ui.label_weak(s, "Ctrl+P commands")
}

//- command palette

app_open_palette :: proc(app: ^App) {
    app.palette_open, app.palette_new = true, true
    app.query_len, app.selected = 0, 0
}

// Every character of query appears in text, in order, ignoring case.
fuzzy_match :: proc(text, query: string) -> bool {
    i := 0
    for c in text {
        if i >= len(query) do break
        lower :: proc(c: rune) -> rune { return c >= 'A' && c <= 'Z' ? c + 32 : c }
        if lower(c) == lower(rune(query[i])) do i += 1
    }
    return i >= len(query)
}

app_command_palette :: proc(s: ^ui.State, app: ^App) {
    if !app.palette_open do return
    query := string(app.query[:app.query_len])
    matches := make([dynamic]Action, context.temp_allocator)
    for name, action in ACTION_NAMES do if fuzzy_match(name, query) do append(&matches, action)
    // up/down are taken before the text field sees them
    if ui.key_pressed(s, .Down) do app.selected += 1
    if ui.key_pressed(s, .Up) do app.selected -= 1
    app.selected = clamp(app.selected, 0, max(len(matches) - 1, 0))

    pos := ui.Vec2{max(20, (s.viewport.x - 460) * 0.5), 70}
    run: Maybe(Action)
    field_key: ui.Key
    if ui.window(s, "Command palette", {position = pos, size = {460, 360}, options = {.No_Title_Bar, .No_Resize}}, &app.palette_open) {
        field := ui.line_edit(s, "query", app.query[:], &app.query_len)
        field_key = field.box.key
        if app.palette_new {
            // open with the cursor already in the search field
            s.focus_hot, s.focus_active = field.box.key, field.box.key
            app.palette_new = false
        } else if s.focus_active != field.box.key {
            app.palette_open = false // Escape, or a click outside (the main UI's signals ran first)
        }
        if ui.committed(field) && len(matches) > 0 do run = matches[app.selected]
        ui.spacer(s, ui.px(6))
        if ui.scroll_region(s, "results") {
            for action, i in matches {
                pal := s.theme.floating
                if i == app.selected {
                    pal.background = pal.accent
                    pal.background.a = 0.3
                    ui.set_next_flags(s, {.Draw_Background})
                }
                ui.set_next_palette(s, pal)
                ui.set_next_text_padding(s, 10)
                sig := ui.menu_item(s, fmt.tprintf("%s###cmd%d", ACTION_NAMES[action], int(action)), ACTION_KEYS[action])
                if ui.clicked(sig) do run = action
                if ui.hovering(sig) do app.selected = i
            }
            if len(matches) == 0 do ui.label_weak(s, "  No command matches")
        }
    }
    // clicks on results or the palette's own background ended editing; take focus back.
    // This runs after end_window, so the window background's signal has already happened.
    if app.palette_open && field_key != 0 {
        s.focus_hot, s.focus_active = field_key, field_key
    }
    if action, ok := run.?; ok {
        app.palette_open = false
        app_do(app, s, action)
    }
}
