package main

import "core:math"
import pl "platform"
import r "renderer"
import ui "ui"
import gl "vendor:OpenGL"

#assert(len(ui.Cursor) == len(pl.Cursor), "ui.Cursor and platform.Cursor must list the same shapes")

ui_input_key :: proc(key: pl.Key_Type) -> ui.Input_Key {
    if key >= .A && key <= .Z do return ui.Input_Key(int(ui.Input_Key.A) + int(key) - int(pl.Key_Type.A))
    if key >= .F1 && key <= .F12 do return ui.Input_Key(int(ui.Input_Key.F1) + int(key) - int(pl.Key_Type.F1))
    #partial switch key {
        case .TAB: return .Tab
        case .ENTER: return .Enter
        case .ESCAPE: return .Escape
        case .SPACE: return .Space
        case .BACKSPACE: return .Backspace
        case .DELETE: return .Delete
        case .LEFT: return .Left
        case .RIGHT: return .Right
        case .UP: return .Up
        case .DOWN: return .Down
        case .HOME: return .Home
        case .END: return .End
        case .PRIOR: return .Page_Up
        case .NEXT: return .Page_Down
    }
    return .None
}

ui_mods :: proc(mods: pl.Modifiers) -> (out: ui.Modifiers) {
    if .Shift in mods do out += {.Shift}
    if .Ctrl in mods do out += {.Ctrl}
    if .Alt in mods do out += {.Alt}
    return
}

ui_button :: proc(button: pl.Mouse_Button) -> ui.Mouse_Button {
    switch button {
        case .Left: return .Left
        case .Middle: return .Middle
        case .Right: return .Right
    }
    return .Left
}

ui_events :: proc(list: pl.Event_List) -> [dynamic]ui.Event {
    events := make([dynamic]ui.Event, context.temp_allocator)
    for e := list.head; e != nil; e = e.next {
        v := ui.Event{pos = {f32(e.pos.x), f32(e.pos.y)}, mods = ui_mods(e.mods)}
        #partial switch e.type {
            case .MOUSE_MOVE:
                v.kind = .Move
            case .MOUSE_PRESS, .MOUSE_RELEASE:
                v.kind = e.type == .MOUSE_PRESS ? .Press : .Release
                v.button = ui_button(e.button)
            case .MOUSE_SCROLL:
                v.kind, v.scroll = .Scroll, e.scroll
            case .MOUSE_LEAVE:
                v.kind = .Leave
            case .INPUT_CANCEL:
                v.kind = .Cancel
            case .KEY_PRESS, .KEY_REPEAT:
                v.kind, v.key, v.repeat = .Key_Press, ui_input_key(e.key), e.type == .KEY_REPEAT
                if v.key == .None do continue
            case .KEY_RELEASE:
                v.kind, v.key = .Key_Release, ui_input_key(e.key)
                if v.key == .None do continue
            case .TEXT_INPUT:
                v.kind, v.text = .Text, e.text
            case:
                continue
        }
        append(&events, v)
    }
    return events
}

ui_render :: proc(commands: []ui.Draw_Command) {
    scale := pl.get_display_scale()
    width, height := pl.get_framebuffer_size()
    gl.Viewport(0, 0, width, height)
    gl.Enable(gl.SCISSOR_TEST)
    current_clip: ui.Rect
    first := true
    r.start_command()
    for command in commands {
        // a new clip rectangle means a new scissor, so flush what's batched so far
        if first || command.clip != current_clip {
            r.render()
            current_clip = command.clip
            first = false
            x0 := clamp(i32(math.floor(current_clip.pos.x * scale)), 0, width)
            y0 := clamp(i32(math.floor(current_clip.pos.y * scale)), 0, height)
            x1 := clamp(i32(math.ceil((current_clip.pos.x + current_clip.size.x) * scale)), x0, width)
            y1 := clamp(i32(math.ceil((current_clip.pos.y + current_clip.size.y) * scale)), y0, height)
            gl.Scissor(x0, height - y1, x1 - x0, y1 - y0)
        }
        switch draw in command.payload {
            case ui.Rect_Draw:
                // ui.Corner and the renderer agree on corner order: top-left, top-right, bottom-right, bottom-left
                r.push_rect_ex(
                    {draw.rect.pos, draw.rect.size},
                    transmute([4][4]f32)draw.colors,
                    transmute([4]f32)draw.radii,
                    draw.border,
                    draw.softness,
                )
            case ui.Text_Draw:
                r.push_text(draw.text, draw.pos, draw.color, draw.font_size, 0)
        }
    }
    r.end_command()
    r.render()
    gl.Disable(gl.SCISSOR_TEST)
}
