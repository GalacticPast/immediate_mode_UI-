package main

import "core:fmt"
import "core:strings"
import pl "platform"
import ui "ui"
import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

// the first frames can race the compositor's initial resize, so the script starts late
SMOKE_FRAMES :: 76

// Finds a box from the previous build by its display text.
smoke_find :: proc(s: ^ui.State, text: string) -> ^ui.Box {
    for _, b in s.cache do if strings.has_prefix(b.text, text) do return b
    return nil
}

// Clicks near the box's left edge (its center can be under a window).
smoke_click :: proc(events: ^[dynamic]ui.Event, b: ^ui.Box, button := ui.Mouse_Button.Left) {
    if b == nil do return
    p := b.rect.pos + {min(12, b.rect.size.x * 0.5), b.rect.size.y * 0.5}
    append(events, ui.Event{kind = .Move, pos = p})
    append(events, ui.Event{kind = .Press, pos = p, button = button}, ui.Event{kind = .Release, pos = p, button = button})
}

smoke_before_build :: proc(s: ^ui.State, app: ^App, frame: int, events: ^[dynamic]ui.Event) {
    switch frame {
        case 8:
            // run the VM; the frames until the next capture show it executing
            append(events, ui.Event{kind = .Key_Press, key = .F5})
        case 30:
            if b := smoke_find(s, "Output"); b != nil do smoke_click(events, b)
        case 40:
            if b := smoke_find(s, "Plot"); b != nil do smoke_click(events, b)
        case 50:
            append(events, ui.Event{kind = .Key_Press, key = .P, mods = {.Ctrl}})
        case 52:
            for c in "theme" do append(events, ui.Event{kind = .Text, text = c})
        case 58:
            append(events, ui.Event{kind = .Key_Press, key = .Enter})
        case 62:
            if b := smoke_find(s, "Inspect"); b != nil do smoke_click(events, b)
        case 66:
            if b := smoke_find(s, "theme"); b != nil do smoke_click(events, b)
        case 70:
            if b := smoke_find(s, "debugger   Debugger"); b != nil {
                append(events, ui.Event{kind = .Scroll, pos = b.rect.pos + {40, 30}, scroll = {0, 70}})
            }
    }
}

smoke_capture :: proc(frame: int) {
    err := gl.GetError()
    assert(err == gl.NO_ERROR, fmt.tprintf("OpenGL error: %d", err))
    if frame != 28 && frame != 48 && frame != 56 && frame != 75 do return
    w, h := pl.get_framebuffer_size()
    pixels := make([]u8, int(w * h * 4), context.temp_allocator)
    gl.ReadPixels(0, 0, w, h, gl.RGBA, gl.UNSIGNED_BYTE, raw_data(pixels))
    stbi.flip_vertically_on_write(true)
    path := strings.clone_to_cstring(fmt.tprintf("bin/ui-preview-%d.png", frame), context.temp_allocator)
    assert(stbi.write_png(path, w, h, 4, raw_data(pixels), w * 4) != 0)
    fmt.println("Captured", path)
}
