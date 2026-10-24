// A RAD Debugger-flavoured front end for the toy VM in vm.odin. Every panel is a plain
// procedure that reads the VM and builds boxes; nothing caches what the VM looked like.
package main

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import ui "ui"

Watch :: struct {
    text: [32]u8,
    len:  int,
}

Tool_Tab :: enum { Watch, Output, Plot, Inspect }

Debugger :: struct {
    vm:            VM,
    prog:          Program,
    running:       bool,
    speed:         f32, // instructions per second
    budget:        f32, // fractional instructions carried between frames
    measured_ips:  f32,
    breakpoints:   [256]bool,
    run_to:        i32, // -1, or an address to stop at once
    cursor:        i32, // selected disassembly line
    follow_pc:     bool,
    follow_output: bool,
    plot_reg:      Reg,
    tool_tab:      int, // Tool_Tab, when the tools have their own column
    narrow_tab:    int, // 0 = memory, then Tool_Tab + 1, when memory and tools share a pane
    code_width:    f32,
    tools_width:   f32,
    watches:       [dynamic]Watch,
    watch_input:   [32]u8,
    watch_len:     int,
    inspector:     Inspector,
}

debugger_init :: proc(d: ^Debugger) {
    d^ = {
        speed         = 60,
        run_to        = -1,
        follow_pc     = true,
        follow_output = true,
        plot_reg      = .R0,
        code_width    = 300,
        tools_width   = 380,
    }
    program_build(&d.prog)
    vm_reset(&d.vm)
    d.breakpoints[d.prog.address["fib"]] = true
    for text in ([]string{"r0", "sp", "[0x02]", "[r4]"}) do watch_add(d, text)
}

debugger_destroy :: proc(d: ^Debugger) {
    vm_destroy(&d.vm)
    program_destroy(&d.prog)
    delete(d.watches)
    delete(d.inspector.open)
}

watch_add :: proc(d: ^Debugger, expression: string) {
    text := strings.trim_space(expression)
    if len(text) == 0 do return
    w: Watch
    w.len = copy(w.text[:], text)
    append(&d.watches, w)
}

// Evaluates "r3", "pc", "sp", "42", "0x2A", "[0x2A]" or "[r4]" (a memory read).
watch_eval :: proc(d: ^Debugger, text: string) -> (value: i32, ok: bool) {
    t := strings.trim_space(text)
    if len(t) >= 2 && t[0] == '[' && t[len(t) - 1] == ']' {
        addr := watch_eval(d, t[1:len(t) - 1]) or_return
        return i32(d.vm.mem[u8(addr & 0xff)]), true
    }
    switch t {
        case "pc": return d.vm.pc, true
        case "sp": return d.vm.sp, true
    }
    if len(t) == 2 && t[0] == 'r' && t[1] >= '0' && t[1] <= '7' do return d.vm.regs[Reg(t[1] - '0')], true
    n := strconv.parse_int(t) or_return
    return i32(n), true
}

// Runs the VM for this frame's share of instructions, stopping at breakpoints.
debugger_update :: proc(d: ^Debugger, s: ^ui.State) {
    if !d.running {
        d.measured_ips = 0
        return
    }
    s.animating = true
    d.budget += s.dt * d.speed
    steps := min(int(d.budget), 50_000)
    d.budget -= f32(steps)
    done := 0
    for _ in 0 ..< steps {
        vm_step(&d.vm, &d.prog, s.time, d.plot_reg)
        done += 1
        pc := d.vm.pc
        if d.vm.halted || (pc >= 0 && pc < 256 && d.breakpoints[pc]) || pc == d.run_to {
            d.running, d.run_to, d.budget = false, -1, 0
            break
        }
    }
    if s.dt > 0 do d.measured_ips += (f32(done) / s.dt - d.measured_ips) * 0.1
}

debugger_step :: proc(d: ^Debugger, s: ^ui.State, count := 1) {
    d.running = false
    for _ in 0 ..< count do vm_step(&d.vm, &d.prog, s.time, d.plot_reg)
}

debugger_reset :: proc(d: ^Debugger) {
    vm_reset(&d.vm)
    d.running, d.run_to = false, -1
}

// 1 right after a write, fading to 0 over half a second.
@(private = "file")
heat :: proc(s: ^ui.State, written: f64) -> f32 {
    if written <= 0 do return 0
    h := 1 - f32(s.time - written) / 0.5
    if h > 0 do s.animating = true
    return clamp(h, 0, 1)
}

@(private = "file")
mix :: proc(a, b: ui.Color, t: f32) -> ui.Color { return a + (b - a) * t }

//- layout

debugger_build :: proc(s: ^ui.State, d: ^Debugger) {
    debugger_toolbar(s, d)
    // immediate mode makes responsive layout an if statement: narrow windows merge the memory
    // view and the tools into one tabbed pane instead of giving the tools a third column
    wide := s.viewport.x >= 1180
    if ui.row(s, ui.fill(), ui.fill(), "panes") {
        ui.spacer(s, ui.px(6))
        if pane(s, "Disassembly", ui.px(d.code_width), ui.fill()) do code_view(s, d)
        splitter(s, "split_code", &d.code_width, 1, 200, 520)
        if ui.column(s, ui.fill(), ui.fill(), "middle") {
            ui.spacer(s, ui.px(6))
            if pane(s, "Registers", ui.fill(), ui.children_sum()) do register_view(s, d)
            ui.spacer(s, ui.px(6))
            if wide {
                if pane(s, "Memory", ui.fill(), ui.fill()) do memory_view(s, d)
            } else {
                if pane(s, "Memory and tools", ui.fill(), ui.fill()) do tools_view(s, d, true)
            }
            ui.spacer(s, ui.px(6))
        }
        if wide {
            splitter(s, "split_tools", &d.tools_width, -1, 260, 640)
            if ui.column(s, ui.px(d.tools_width), ui.fill(), "right") {
                ui.spacer(s, ui.px(6))
                if pane(s, "Tools", ui.fill(), ui.fill()) do tools_view(s, d, false)
                ui.spacer(s, ui.px(6))
            }
        }
        ui.spacer(s, ui.px(6))
    }
}

// A titled panel: user code can define scoped widgets the same way the library does.
@(deferred_in_out = end_pane)
pane :: proc(s: ^ui.State, title: string, width, height: ui.Size) -> bool {
    ui.set_next_child_layout_axis(s, .Y)
    ui.set_next_pref_size(s, width, height)
    ui.set_next_palette(s, s.theme.floating)
    ui.set_next_corner_radius(s, 5)
    b := ui.build_box(s, {.Draw_Background, .Draw_Border, .Clip}, fmt.tprintf("###pane_%s", title))
    ui.push_parent(s, b)
    header := s.theme.title_bar
    ui.set_next_child_layout_axis(s, .X)
    ui.set_next_pref_size(s, ui.fill(), ui.px(24))
    ui.set_next_palette(s, header)
    ui.set_next_corner_radii(s, {.Top_Left = 5, .Top_Right = 5, .Bottom_Right = 0, .Bottom_Left = 0})
    h := ui.build_box(s, {.Draw_Background, .Draw_Side_Bottom}, "###header")
    ui.push_parent(s, h)
    ui.set_next_palette(s, header)
    ui.set_next_font_size(s, 12)
    ui.set_next_pref_height(s, ui.fill())
    ui.label_weak(s, strings.to_upper(title, context.temp_allocator))
    ui.pop_parent(s)
    ui.push_palette(s, s.theme.floating)
    return true
}
end_pane :: proc(s: ^ui.State, title: string, width, height: ui.Size, ok: bool) {
    ui.pop_palette(s)
    ui.pop_parent(s)
}

// A draggable gap between panes that resizes a neighbour. sign is -1 when the pane
// being resized is to the right of the splitter.
splitter :: proc(s: ^ui.State, name: string, width: ^f32, sign, lo, hi: f32) {
    line := s.theme.base
    line.background = {0, 0, 0, 0}
    line.overlay = s.theme.base.accent
    line.overlay.a = 0.5
    ui.set_next_pref_size(s, ui.px(6), ui.fill())
    ui.set_next_palette(s, line)
    ui.set_next_hover_cursor(s, .Resize_EW)
    b := ui.build_box(s, {.Mouse_Clickable, .Draw_Hot_Effects}, name)
    sig := ui.signal_from_box(s, b)
    if .Left_Pressed in sig.flags do ui.store_drag_data(s, width^)
    if ui.dragging(sig) do width^ = ui.get_drag_data(s, f32) + ui.drag_delta(s).x * sign
    width^ = clamp(width^, lo, hi)
}

//- toolbar

@(private = "file")
status_chip :: proc(s: ^ui.State, text: string, color: ui.Color) {
    pal := s.theme.base
    pal.background = color
    pal.background.a = 0.22
    pal.text = color
    ui.set_next_palette(s, pal)
    ui.set_next_pref_size(s, ui.text_dim(14), ui.px(22))
    ui.set_next_corner_radius(s, 11)
    ui.set_next_text_align(s, .Center)
    ui.set_next_font_size(s, 12)
    b := ui.build_box_from_key(s, {.Draw_Background, .Draw_Text}, 0)
    ui.set_text(s, b, text)
}

state_color :: proc(d: ^Debugger) -> (string, ui.Color) {
    switch {
        case d.vm.halted: return "HALTED", ui.rgb(0xe06c6c)
        case d.running: return "RUNNING", ui.rgb(0x5cc28a)
    }
    return "PAUSED", ui.rgb(0xe0a84e)
}

debugger_toolbar :: proc(s: ^ui.State, d: ^Debugger) {
    ui.set_next_child_layout_axis(s, .X)
    ui.set_next_pref_size(s, ui.fill(), ui.px(42))
    ui.set_next_palette(s, s.theme.menu_bar)
    bar := ui.build_box(s, {.Draw_Background, .Draw_Side_Bottom}, "toolbar")
    ui.parent(s, bar)
    ui.spacer(s, ui.px(8))
    if ui.column(s, ui.children_sum(), ui.fill()) {
        ui.spacer(s, ui.fill())
        if ui.row(s, ui.children_sum(), ui.px(28)) {
            ui.push_pref_width(s, ui.text_dim(16))
            run := ui.button(s, d.running ? "Pause###run" : "Run###run")
            if ui.clicked(run) do d.running = !d.running
            if ui.tooltip(s, run) do ui.label(s, "F5")
            ui.spacer(s, ui.px(6))
            step := ui.button(s, "Step")
            if ui.clicked(step) do debugger_step(d, s)
            if ui.tooltip(s, step) do ui.label(s, "F10: one instruction")
            ui.spacer(s, ui.px(6))
            if ui.clicked(ui.button(s, "Step x100")) do debugger_step(d, s, 100)
            ui.spacer(s, ui.px(6))
            reset := ui.button(s, "Reset")
            if ui.clicked(reset) do debugger_reset(d)
            if ui.tooltip(s, reset) do ui.label(s, "Ctrl+R: clear memory and registers")
            ui.pop_pref_width(s)
        }
        ui.spacer(s, ui.fill())
    }
    ui.spacer(s, ui.px(16))
    if ui.column(s, ui.px(230), ui.fill()) {
        ui.spacer(s, ui.fill())
        // a logarithmic slider: the slider edits log10(speed), the label shows the speed
        ui.set_next_pref_height(s, ui.px(26))
        exponent := math.log10(clamp(d.speed, 1, 5000))
        speed := ui.slider(s, "Speed", &exponent, 0, math.log10(f32(5000)))
        d.speed = math.pow(10, exponent)
        ui.set_text(s, speed.box, fmt.tprintf("Speed  %.0f ips", d.speed))
        ui.spacer(s, ui.fill())
    }
    ui.spacer(s, ui.px(12))
    if ui.column(s, ui.children_sum(), ui.fill()) {
        ui.spacer(s, ui.fill())
        ui.set_next_pref_width(s, ui.text_dim(34))
        ui.checkbox(s, "Follow PC", &d.follow_pc)
        ui.spacer(s, ui.fill())
    }
    ui.spacer(s, ui.fill())
    if ui.column(s, ui.children_sum(), ui.fill()) {
        ui.spacer(s, ui.fill())
        text, color := state_color(d)
        status_chip(s, text, color)
        ui.spacer(s, ui.fill())
    }
    ui.spacer(s, ui.px(12))
}

//- disassembly

@(private = "file")
Gutter_Draw :: struct {
    breakpoint, is_pc: bool,
}

@(private = "file")
gutter_draw :: proc(s: ^ui.State, b: ^ui.Box, data: rawptr) {
    g := cast(^Gutter_Draw)data
    c := b.rect.pos + b.rect.size * 0.5
    if g.breakpoint {
        ui.draw_rect(s, {c - 5, {10, 10}}, ui.rgb(0xe05555), 5)
    } else if b.hot_t > 0.01 {
        ui.draw_rect(s, {c - 5, {10, 10}}, ui.rgb(0xe05555, 0.35 * b.hot_t), 5)
    }
    if g.is_pc do ui.draw_triangle(s, c + {7, 0}, 5, false, s.theme.base.accent)
}

code_view :: proc(s: ^ui.State, d: ^Debugger) {
    menu_key := ui.key_from_string(0, "code_menu")
    pc_line: ^ui.Box
    ui.font_size(s, 13)
    ui.pref_height(s, ui.px(22))
    if ui.scroll_region(s, "code") {
        buf: [64]u8
        for ins, i in d.prog.code {
            addr := i32(i)
            if name, ok := d.prog.labels[i]; ok {
                ui.set_next_text_padding(s, 50)
                ui.label(s, fmt.tprintf("%s:", name))
            }
            pal := s.theme.floating
            flags := ui.Box_Flags{.Mouse_Clickable, .Draw_Hot_Effects}
            if addr == d.vm.pc {
                pal.background = pal.accent
                pal.background.a = 0.3
                flags += {.Draw_Background}
            } else if addr == d.cursor {
                pal.background = pal.overlay
                flags += {.Draw_Background}
            }
            ui.set_next_child_layout_axis(s, .X)
            ui.set_next_palette(s, pal)
            line := ui.build_box(s, flags, fmt.tprintf("###line%d", i))
            if ui.parent(s, line) {
                ui.set_next_pref_width(s, ui.px(24))
                ui.set_next_hover_cursor(s, .Pointer)
                gutter := ui.build_box(s, {.Mouse_Clickable, .Draw_Hot_Effects}, "###gutter")
                g := new(Gutter_Draw, ui.build_allocator(s))
                g^ = {d.breakpoints[i], addr == d.vm.pc}
                gutter.custom_draw, gutter.custom_data = gutter_draw, g
                if ui.clicked(ui.signal_from_box(s, gutter)) do d.breakpoints[i] = !d.breakpoints[i]
                ui.set_next_pref_width(s, ui.text_dim())
                ui.label_weak(s, fmt.tprintf("%04X", i))
                ui.label(s, disassemble(ins, buf[:]))
            }
            sig := ui.signal_from_box(s, line)
            if ui.clicked(sig) do d.cursor = addr
            if ui.double_clicked(sig) do d.breakpoints[i] = !d.breakpoints[i]
            if ui.right_clicked(sig) {
                d.cursor = addr
                ui.ctx_menu_open(s, menu_key)
            }
            if addr == d.vm.pc do pc_line = line
        }
        // keep the current instruction in view: last frame's rects say where it is
        if view := ui.scroll_view(s); d.follow_pc && pc_line != nil && view != nil {
            y := pc_line.rect.pos.y - view.rect.pos.y + view.view_off.y
            visible := view.rect.size.y
            if y < view.view_off_target.y || y + 22 > view.view_off_target.y + visible {
                view.view_off_target.y = y - visible * 0.35
            }
        }
    }
    if ui.ctx_menu(s, menu_key) {
        ui.label_weak(s, fmt.tprintf("  line %04X", d.cursor))
        if ui.clicked(ui.menu_item(s, "Run to here")) {
            d.run_to, d.running = d.cursor, true
        }
        if ui.clicked(ui.menu_item(s, d.breakpoints[d.cursor] ? "Remove breakpoint" : "Add breakpoint", "F9")) {
            d.breakpoints[d.cursor] = !d.breakpoints[d.cursor]
        }
        if ui.clicked(ui.menu_item(s, "Set PC here")) do d.vm.pc = d.cursor
    }
}

//- registers

register_view :: proc(s: ^ui.State, d: ^Debugger) {
    ui.spacer(s, ui.px(6))
    ui.font_size(s, 13)
    for pair in 0 ..< 4 {
        if ui.row(s, ui.fill(), ui.px(26), fmt.tprintf("regrow%d", pair)) {
            ui.spacer(s, ui.px(8))
            for col in 0 ..< 2 {
                r := Reg(pair + col * 4)
                if col == 1 do ui.spacer(s, ui.px(14))
                // the register name selects what the plot shows
                pal := s.theme.floating
                if r == d.plot_reg do pal.text = pal.accent
                ui.set_next_palette(s, pal)
                ui.set_next_pref_width(s, ui.px(34))
                name := ui.button_flat(s, fmt.tprintf("r%d###name%d", int(r), int(r)))
                if ui.clicked(name) {
                    d.plot_reg = r
                    d.vm.history_count = 0
                }
                if ui.tooltip(s, name) do ui.label(s, "Plot this register")
                v := f64(d.vm.regs[r])
                if drag_number(s, fmt.tprintf("##r%d", int(r)), &v, 0.25, true, heat(s, d.vm.reg_write_time[r])) {
                    d.vm.regs[r] = i32(v)
                }
                ui.set_next_pref_width(s, ui.px(86))
                ui.set_next_text_align(s, .Right)
                ui.label_weak(s, fmt.tprintf("0x%08X", u32(d.vm.regs[r])))
            }
            ui.spacer(s, ui.px(8))
        }
        ui.spacer(s, ui.px(2))
    }
    if ui.row(s, ui.fill(), ui.px(26), "special") {
        ui.spacer(s, ui.px(8))
        ui.set_next_pref_width(s, ui.px(34))
        ui.label_weak(s, "pc")
        pc := f64(d.vm.pc)
        if drag_number(s, "##pc", &pc, 0.25, true) do d.vm.pc = i32(clamp(pc, 0, f64(len(d.prog.code) - 1)))
        ui.spacer(s, ui.px(14))
        ui.set_next_pref_width(s, ui.px(34))
        ui.label_weak(s, "sp")
        sp := f64(d.vm.sp)
        if drag_number(s, "##sp", &sp, 0.25, true) do d.vm.sp = i32(clamp(sp, 0xF0, STACK_BASE))
        ui.spacer(s, ui.px(14))
        zero, negative := .Zero in d.vm.flags, .Negative in d.vm.flags
        ui.set_next_pref_width(s, ui.text_dim(34))
        if ui.clicked(ui.checkbox(s, "Z", &zero)) do d.vm.flags ~= {.Zero}
        ui.set_next_pref_width(s, ui.text_dim(34))
        if ui.clicked(ui.checkbox(s, "N", &negative)) do d.vm.flags ~= {.Negative}
        ui.spacer(s, ui.px(8))
    }
    ui.spacer(s, ui.px(6))
}

//- memory

Region :: struct {
    name:  string,
    lo:    int,
    color: ui.Color,
}

REGIONS := [?]Region {
    {"sieve", 0x00, {0.30, 0.56, 0.88, 1}},
    {"fibonacci", 0x80, {0.36, 0.76, 0.54, 1}},
    {"pattern", 0xC0, {0.66, 0.48, 0.86, 1}},
    {"stack", 0xF0, {0.88, 0.66, 0.31, 1}},
}

region_of :: proc(addr: int) -> Region {
    r := REGIONS[0]
    for region in REGIONS do if addr >= region.lo do r = region
    return r
}

memory_view :: proc(s: ^ui.State, d: ^Debugger) {
    mem_pane := ui.top_parent(s)
    // cells fit last frame's pane width: the previous layout is free information
    cell := clamp((mem_pane.rect.size.x - 70) / 16, 18, 34)
    row_h := max(18, cell * 0.72)
    ui.font_size(s, 12)
    ui.pref_height(s, ui.px(row_h))
    if ui.scroll_region(s, "mem") {
        if ui.row(s, ui.fill(), ui.px(20), "columns") {
            ui.spacer(s, ui.px(50))
            for col in 0 ..< 16 {
                ui.set_next_pref_width(s, ui.px(cell))
                ui.set_next_text_align(s, .Center)
                ui.label_weak(s, fmt.tprintf("%X", col))
            }
        }
        for row in 0 ..< 16 {
            if ui.row(s, ui.fill(), ui.px(row_h), fmt.tprintf("memrow%d", row)) {
                ui.set_next_pref_width(s, ui.px(50))
                ui.set_next_text_align(s, .Right)
                ui.set_next_text_padding(s, 10)
                ui.label_weak(s, fmt.tprintf("%02X", row * 16))
                for col in 0 ..< 16 {
                    addr := row * 16 + col
                    region := region_of(addr)
                    h := heat(s, d.vm.mem_write_time[addr])
                    pal := s.theme.input
                    pal.background = mix(pal.background, region.color, 0.12 + 0.6 * h)
                    if d.vm.mem[addr] == 0 do pal.text = pal.text_weak
                    flags := ui.Box_Flags{.Mouse_Clickable, .Draw_Background, .Draw_Text, .Draw_Hot_Effects}
                    if i32(addr) == d.vm.sp && d.vm.sp < STACK_BASE {
                        pal.border = pal.accent
                        flags += {.Draw_Border}
                    }
                    ui.set_next_palette(s, pal)
                    ui.set_next_pref_width(s, ui.px(cell))
                    ui.set_next_text_align(s, .Center)
                    ui.set_next_text_padding(s, 0)
                    ui.set_next_corner_radius(s, 2)
                    b := ui.build_box(s, flags, fmt.tprintf("%02X###c%d", d.vm.mem[addr], addr))
                    sig := ui.signal_from_box(s, b)
                    if ui.clicked(sig) do watch_add(d, fmt.tprintf("[0x%02X]", addr))
                    if ui.tooltip(s, sig) {
                        ui.labelf(s, "0x%02X  %s", addr, region.name)
                        ui.label_weak(s, fmt.tprintf("value %d  0b%08b", d.vm.mem[addr], d.vm.mem[addr]))
                        ui.label_weak(s, "click to watch")
                    }
                }
            }
        }
        ui.spacer(s, ui.px(6))
        if ui.row(s, ui.fill(), ui.px(20), "legend") {
            ui.spacer(s, ui.px(50))
            for region in REGIONS {
                pal := s.theme.floating
                pal.background = region.color
                ui.set_next_palette(s, pal)
                ui.set_next_pref_size(s, ui.px(10), ui.px(10))
                ui.set_next_corner_radius(s, 2)
                ui.build_box_from_key(s, {.Draw_Background}, 0)
                ui.set_next_pref_width(s, ui.text_dim(10))
                ui.label_weak(s, region.name)
            }
        }
    }
}

//- tools

tools_view :: proc(s: ^ui.State, d: ^Debugger, with_memory: bool) {
    names := [?]string{"Memory", "Watch", "Output", "Plot", "Inspect"} // Memory, then Tool_Tab order
    tab := with_memory ? &d.narrow_tab : &d.tool_tab
    tab_bar(s, "tool_tabs", with_memory ? names[:] : names[1:], tab, s.theme.title_bar)
    which := with_memory ? tab^ - 1 : tab^
    if which < 0 {
        memory_view(s, d)
        return
    }
    switch Tool_Tab(which) {
        case .Watch: watch_view(s, d)
        case .Output: output_view(s, d)
        case .Plot: plot_view(s, d)
        case .Inspect: inspect_view(s, d)
    }
}

watch_view :: proc(s: ^ui.State, d: ^Debugger) {
    ui.spacer(s, ui.px(8))
    if ui.row(s, ui.fill(), ui.px(28), "add_watch") {
        ui.spacer(s, ui.px(8))
        input := ui.line_edit(s, "expression", d.watch_input[:], &d.watch_len)
        if ui.tooltip(s, input) do ui.label(s, "r0..r7, pc, sp, a number, or [address]")
        ui.spacer(s, ui.px(6))
        ui.set_next_pref_width(s, ui.px(60))
        add := ui.button(s, "Add")
        if ui.clicked(add) || ui.committed(input) {
            watch_add(d, string(d.watch_input[:d.watch_len]))
            d.watch_len = 0
        }
        ui.spacer(s, ui.px(8))
    }
    ui.spacer(s, ui.px(6))
    remove := -1
    if ui.scroll_region(s, "watches") {
        for &w, i in d.watches {
            text := string(w.text[:w.len])
            if ui.row(s, ui.fill(), ui.px(24), fmt.tprintf("watch%d", i)) {
                ui.spacer(s, ui.px(8))
                ui.set_next_pref_width(s, ui.px(110))
                ui.label(s, text)
                if value, ok := watch_eval(d, text); ok {
                    ui.labelf(s, "%d", value)
                    ui.set_next_pref_width(s, ui.px(100))
                    ui.label_weak(s, fmt.tprintf("0x%X", u32(value)))
                } else {
                    ui.label_weak(s, "can't evaluate")
                }
                ui.set_next_pref_width(s, ui.px(26))
                ui.set_next_text_align(s, .Center)
                // removing while iterating would skip a row, so remember it for after the loop
                if ui.clicked(ui.button_flat(s, "x")) do remove = i
                ui.spacer(s, ui.px(4))
            }
        }
    }
    if remove >= 0 do ordered_remove(&d.watches, remove)
}

output_view :: proc(s: ^ui.State, d: ^Debugger) {
    ui.spacer(s, ui.px(6))
    if ui.row(s, ui.fill(), ui.px(26), "output_bar") {
        ui.spacer(s, ui.px(8))
        ui.label_weak(s, fmt.tprintf("%d lines (%d shown)", d.vm.output_total, len(d.vm.output)))
        ui.set_next_pref_width(s, ui.text_dim(34))
        ui.checkbox(s, "Follow", &d.follow_output)
        ui.set_next_pref_width(s, ui.px(64))
        if ui.clicked(ui.button(s, "Clear")) do clear(&d.vm.output)
        ui.spacer(s, ui.px(8))
    }
    colors := [Channel]ui.Color{.Prime = REGIONS[0].color, .Fib = REGIONS[1].color, .Pass = REGIONS[3].color}
    ui.font_size(s, 12)
    ui.pref_height(s, ui.px(18))
    if ui.scroll_region(s, "output") {
        for line in d.vm.output {
            pal := s.theme.floating
            pal.text = colors[line.channel]
            ui.set_next_palette(s, pal)
            ui.set_next_text_padding(s, 10)
            ui.label(s, fmt.tprintf("%8d   %-6v %d", line.cycle, line.channel, line.value))
        }
        if view := ui.scroll_view(s); d.follow_output && view != nil {
            view.view_off_target.y = max(f32) // end_build clamps it to the bottom
        }
    }
}

@(private = "file")
Plot_Draw :: struct {
    samples: []i32,
    lo, hi:  i32,
    color:   ui.Color,
    hover:   int,
}

@(private = "file")
plot_draw :: proc(s: ^ui.State, b: ^ui.Box, data: rawptr) {
    p := cast(^Plot_Draw)data
    r := ui.pad_rect(b.rect, -8)
    n := len(p.samples)
    if n == 0 {
        ui.draw_text(s, "step or run to collect samples", r.pos, s.theme.base.text_weak, 12)
        return
    }
    span := f32(max(p.hi - p.lo, 1))
    w := r.size.x / f32(HISTORY)
    for v, i in p.samples {
        t := f32(v - p.lo) / span
        h := max(1, t * r.size.y)
        c := p.color
        if i != p.hover do c.a = 0.35 + 0.65 * f32(i) / f32(n)
        ui.draw_rect(s, {{r.pos.x + f32(i) * w, r.pos.y + r.size.y - h}, {max(w - 1, 1), h}}, c, 1)
    }
}

plot_view :: proc(s: ^ui.State, d: ^Debugger) {
    samples := make([]i32, d.vm.history_count, ui.build_allocator(s))
    start := (d.vm.history_head - d.vm.history_count + HISTORY) % HISTORY
    for &v, i in samples do v = d.vm.history[(start + i) % HISTORY]
    lo, hi: i32 = 0, 1
    if len(samples) > 0 do lo, hi = samples[0], samples[0]
    for v in samples {
        lo = min(lo, v)
        hi = max(hi, v)
    }

    ui.spacer(s, ui.px(6))
    if ui.row(s, ui.fill(), ui.px(26), "plot_bar") {
        ui.spacer(s, ui.px(8))
        for r in Reg {
            pal := s.theme.floating
            if r == d.plot_reg {
                pal.background = pal.accent
                pal.background.a = 0.3
                ui.set_next_flags(s, {.Draw_Background})
            }
            ui.set_next_palette(s, pal)
            ui.set_next_pref_width(s, ui.px(30))
            ui.set_next_text_align(s, .Center)
            if ui.clicked(ui.button_flat(s, fmt.tprintf("r%d###plot%d", int(r), int(r)))) {
                d.plot_reg = r
                d.vm.history_count = 0
            }
        }
        ui.spacer(s, ui.px(8))
    }
    if ui.row(s, ui.fill(), ui.px(22), "plot_stats") {
        ui.spacer(s, ui.px(8))
        ui.label_weak(s, fmt.tprintf("min %d   max %d   last %d   %d samples", lo, hi, len(samples) > 0 ? samples[len(samples) - 1] : 0, len(samples)))
    }
    pal := s.theme.input
    ui.set_next_palette(s, pal)
    ui.set_next_pref_size(s, ui.fill(), ui.fill())
    ui.set_next_corner_radius(s, 4)
    plot := ui.build_box(s, {.Mouse_Clickable, .Draw_Background, .Draw_Border}, "plot")
    sig := ui.signal_from_box(s, plot)
    p := new(Plot_Draw, ui.build_allocator(s))
    p^ = {samples = samples, lo = lo, hi = hi, color = REGIONS[0].color, hover = -1}
    inner := ui.pad_rect(plot.rect, -8)
    if ui.mouse_over(sig) && inner.size.x > 0 {
        p.hover = int((s.mouse.x - inner.pos.x) / inner.size.x * HISTORY)
        if p.hover >= 0 && p.hover < len(samples) {
            if ui.tooltip(s, sig) do ui.labelf(s, "r%d = %d  (%d steps ago)", int(d.plot_reg), samples[p.hover], len(samples) - 1 - p.hover)
        }
    }
    plot.custom_draw, plot.custom_data = plot_draw, p
    ui.spacer(s, ui.px(8))
}

inspect_view :: proc(s: ^ui.State, d: ^Debugger) {
    ui.font_size(s, 13)
    if ui.scroll_region(s, "inspect") {
        ui.spacer(s, ui.px(6))
        ui.label_weak(s, "  Generated from type info. Edit anything; the theme too.")
        inspect(s, &d.inspector, "vm", &d.vm, VM)
        inspect(s, &d.inspector, "debugger", d, Debugger)
        inspect(s, &d.inspector, "theme", &s.theme, ui.Theme)
        ui.spacer(s, ui.px(6))
    }
}

//- shared

// Tabs are just flat buttons and an underline: no tab widget needed in the library.
tab_bar :: proc(s: ^ui.State, name: string, tabs: []string, current: ^int, background: ui.Palette) {
    ui.set_next_child_layout_axis(s, .X)
    ui.set_next_pref_size(s, ui.fill(), ui.px(30))
    ui.set_next_palette(s, background)
    bar := ui.build_box(s, {.Draw_Background, .Draw_Side_Bottom}, name)
    ui.parent(s, bar)
    ui.spacer(s, ui.px(6))
    for tab, i in tabs {
        selected := current^ == i
        pal := background
        pal.text = selected ? background.text : background.text_weak
        ui.set_next_palette(s, pal)
        ui.set_next_pref_width(s, ui.text_dim(20))
        ui.set_next_text_align(s, .Center)
        ui.set_next_hover_cursor(s, .Pointer)
        b := ui.build_box(s, ui.CLICKABLE + {.Draw_Text, .Draw_Hot_Effects}, fmt.tprintf("%s###tab%d", tab, i))
        if ui.pressed(ui.signal_from_box(s, b)) do current^ = i
        t := new(f32, ui.build_allocator(s))
        t^ = ui.animate(s, b.key, selected ? 1 : 0)
        b.custom_data = t
        b.custom_draw = proc(s: ^ui.State, b: ^ui.Box, data: rawptr) {
            t := (cast(^f32)data)^
            if t < 0.01 do return
            w := b.rect.size.x * t
            ui.draw_rect(s, {{b.rect.pos.x + (b.rect.size.x - w) * 0.5, b.rect.pos.y + b.rect.size.y - 2}, {w, 2}}, b.palette.accent, 1)
        }
    }
}
