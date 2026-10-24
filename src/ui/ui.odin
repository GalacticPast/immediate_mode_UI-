// RAD Debugger-inspired box UI. See docs/ui.md and third_party/raddebugger/LICENSE.
package ui

import "core:mem"

Vec2 :: [2]f32
Color :: [3]f32
Key :: distinct u64
Axis :: enum { X, Y }
Rect :: struct { pos, size: Vec2 }
Size_Kind :: enum { Pixels, Text, Children, Parent_Percent, Fill }
Size :: struct {
    kind: Size_Kind,
    value: f32,
    strictness: f32, // 1 preserves the requested size; 0 permits full shrinkage.
}
Flag :: enum { Background, Border, Text, Clickable, Disabled, Clip, Scroll, Floating }
Flags :: bit_set[Flag]
Text_Align :: enum { Left, Center, Right }
Style :: struct {
    width, height: Size,
    axis: Axis,
    padding: Vec2,
    gap: f32,
    font_size: f32,
    background, border, text, accent: Color,
    radius: f32,
    text_align: Text_Align,
}
Signal :: struct {
    hovered, pressed, released, clicked, dragging: bool,
    drag_pos, drag_delta: Vec2,
    step: int,
    home, end: bool,
}
Event_Kind :: enum { Move, Press, Release, Scroll, Key_Press, Cancel, Leave }
Input_Key :: enum { None, Tab, Enter, Space, Left, Right, Up, Down, Home, End, Escape }
Event :: struct {
    kind: Event_Kind,
    pos: Vec2,
    scroll: f32, // logical pixels; positive moves down
    key: Input_Key,
    shift: bool,
}
Measure_Text :: proc(text: string, font_size: f32) -> Vec2
Custom_Draw :: proc(state: ^State, box: ^Box, data: rawptr)
Box :: struct {
    key: Key,
    parent, first, last, next, prev: ^Box,
    child_count: int,
    flags: Flags,
    style: Style,
    text: string, // owned by the UI build arena, valid until next begin_build
    text_offset, floating_pos: Vec2,
    rect, clip: Rect,
    measured, content_size: Vec2,
    custom_draw: Custom_Draw,
    custom_data: rawptr,
    // Persistent fields. Construction replaces everything above on each build.
    last_build: u64,
    scroll_y, hot_t, active_t: f32,
    signal: Signal,
}
// Keep the name of the original placeholder usable while adopting Odin type naming.
Ui_box :: Box
Rect_Draw :: struct { rect: Rect, color: Color, radius, border: f32 }
Text_Draw :: struct { text: string, pos: Vec2, color: Color, font_size: f32 }
Draw_Payload :: union { Rect_Draw, Text_Draw }
Draw_Command :: struct { clip: Rect, payload: Draw_Payload }
State :: struct {
    allocator: mem.Allocator,
    frame_arena: mem.Dynamic_Arena,
    cache: map[Key]^Box,
    boxes, transient, order: [dynamic]^Box,
    parents: [dynamic]^Box,
    styles: [dynamic]Style,
    commands: [dynamic]Draw_Command,
    root, parent: ^Box,
    style: Style,
    measure_text: Measure_Text,
    build_index: u64,
    building: bool,
    viewport: Vec2,
    mouse, drag_start: Vec2,
    pointer_inside: bool,
    hot, active, focus: Key,
    dt: f32,
    animating: bool,
    debug_bounds: bool,
}
