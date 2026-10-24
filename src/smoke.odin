package main

import "core:fmt"
import "core:strings"
import pl "platform"
import ui "ui"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

smoke_before_build :: proc(s: ^ui.State, d: ^Demo, frame: int, events: ^[dynamic]ui.Event) {
    if frame == 2 {
        for b in s.order {
            if strings.has_prefix(b.text, "Red   ") {
                p := b.rect.pos + b.rect.size*ui.Vec2{0.8, 0.5}
                append(events, ui.Event{kind = .Press, pos = p}, ui.Event{kind = .Release, pos = p})
                break
            }
        }
    }
    if frame == 4 do d.show_help = true
    if frame == 5 {
        d.show_help = false
        d.page = 1
    }
    if frame == 6 {
        for b in s.order {
            if .Scroll in b.flags do b.scroll_y = 160
        }
    }
}

smoke_capture :: proc(frame: int) {
    err := gl.GetError()
    assert(err == gl.NO_ERROR, fmt.tprintf("OpenGL error: %d", err))
    if frame != 1 && frame != 3 && frame != 4 && frame != 6 do return
    w, h := pl.get_framebuffer_size()
    pixels := make([]u8, int(w*h*4), context.temp_allocator)
    gl.ReadPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
    stbi.flip_vertically_on_write(true)
    path := strings.clone_to_cstring(fmt.tprintf("bin/ui-preview-%d.png", frame), context.temp_allocator)
    assert(stbi.write_png(path, w, h, 4, raw_data(pixels), w*4) != 0)
    fmt.println("Captured", path)
}
