package main

import "core:math"
import pl "platform"
import r "renderer"
import ui "ui"
import gl "vendor:OpenGL"

ui_input_key :: proc(key: pl.Key_Type) -> ui.Input_Key {
    #partial switch key {
    case .TAB: return .Tab
    case .ENTER: return .Enter
    case .SPACE: return .Space
    case .LEFT: return .Left
    case .RIGHT: return .Right
    case .UP: return .Up
    case .DOWN: return .Down
    case .HOME: return .Home
    case .END: return .End
    case .ESCAPE: return .Escape
    case: return .None
    }
}

ui_events :: proc(list: pl.Event_List, shift_down: ^bool) -> [dynamic]ui.Event {
    events := make([dynamic]ui.Event, context.temp_allocator)
    for e := list.head; e != nil; e = e.next {
        v := ui.Event{pos = {f32(e.pos.x), f32(e.pos.y)}}
        #partial switch e.type {
        case .MOUSE_MOVE: v.kind = .Move
        case .MOUSE_PRESS, .MOUSE_RELEASE:
            if e.button != .Left do continue
            v.kind = e.type == .MOUSE_PRESS ? .Press : .Release
        case .MOUSE_SCROLL: v.kind, v.scroll = .Scroll, e.scroll
        case .MOUSE_LEAVE: v.kind = .Leave
        case .INPUT_CANCEL:
            v.kind = .Cancel
            shift_down^ = false
        case .KEY_PRESS, .KEY_REPEAT, .KEY_RELEASE:
            if e.key == .SHIFT || e.key == .LSHIFT || e.key == .RSHIFT {
                shift_down^ = e.type != .KEY_RELEASE
            }
            if e.type == .KEY_RELEASE do continue
            v.kind, v.key, v.shift = .Key_Press, ui_input_key(e.key), shift_down^
            if v.key == .None do continue
        case: continue
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
        if first || command.clip != current_clip {
            r.render()
            current_clip = command.clip
            first = false
            x0 := clamp(i32(math.floor(current_clip.pos.x*scale)), 0, width)
            y0 := clamp(i32(math.floor(current_clip.pos.y*scale)), 0, height)
            x1 := clamp(i32(math.ceil((current_clip.pos.x+current_clip.size.x)*scale)), x0, width)
            y1 := clamp(i32(math.ceil((current_clip.pos.y+current_clip.size.y)*scale)), y0, height)
            gl.Scissor(x0, height-y1, x1-x0, y1-y0)
        }
        switch draw in command.payload {
        case ui.Rect_Draw:
            r.push_rect({draw.rect.pos, draw.rect.size}, draw.color, draw.radius, draw.border)
        case ui.Text_Draw:
            r.push_text(draw.text, draw.pos, draw.color, draw.font_size, 0)
        }
    }
    r.end_command()
    r.render()
    gl.Disable(gl.SCISSOR_TEST)
}
