// RAD Debugger-inspired box UI. See docs/ui.md and third_party/raddebugger/LICENSE.
package ui

import "core:mem"

Vec2 :: [2]f32
Color :: [4]f32 // straight (not premultiplied) rgba
Key :: distinct u64
Axis :: enum { X, Y }
Corner :: enum { Top_Left, Top_Right, Bottom_Right, Bottom_Left }
Rect :: struct { pos, size: Vec2 }
Text_Align :: enum { Left, Center, Right }

//- sizes

Size_Kind :: enum {
    Null,         // no size: stays whatever fixed_size already is
    Pixels,       // value pixels
    Text,         // measured display text, plus value pixels of extra space
    Parent_Pct,   // value fraction of the nearest ancestor whose size doesn't depend on its children
    Children_Sum, // sum of the children along the layout axis, largest child across it
}
Size :: struct {
    kind:       Size_Kind,
    value:      f32,
    strictness: f32, // how much of the size must survive when siblings overflow the parent: 1 keeps all, 0 none
}

//- boxes

Box_Flag :: enum {
    // interaction
    Mouse_Clickable,
    Keyboard_Clickable, // reachable with tab, Enter/Space presses it
    Click_To_Focus,     // a press makes it the focused, active box (text fields)
    Scroll,             // receives wheel events in its signal
    View_Scroll_X,      // wheel events move view_off (children shift, see Skip_View_Off)
    View_Scroll_Y,
    Disabled,
    // layout
    Floating_X, // ignores layout flow on this axis; placed at fixed_position relative to the parent
    Floating_Y,
    Fixed_Width, // fixed_size is set by the builder, the size passes leave it alone
    Fixed_Height,
    Allow_Overflow_X, // children may exceed this box instead of being shrunk to fit
    Allow_Overflow_Y,
    Skip_View_Off_X, // stays put when the parent scrolls (scroll bars inside a scrolled box)
    Skip_View_Off_Y,
    Animate_Pos_X, // slides to new layout positions instead of jumping
    Animate_Pos_Y,
    // appearance
    Draw_Background,
    Draw_Border,
    Draw_Side_Top,
    Draw_Side_Bottom,
    Draw_Side_Left,
    Draw_Side_Right,
    Draw_Text,
    Draw_Drop_Shadow,
    Draw_Hot_Effects,    // brightens while hovered
    Draw_Active_Effects, // darkens while pressed
    Disable_Focus_Border,
    Disable_Text_Trunc,
    Clip,            // children are drawn and hit-tested only inside this box
    Squish_Anchored, // squish shrinks toward the top edge instead of the center
}
Box_Flags :: bit_set[Box_Flag;u64]

CLICKABLE :: Box_Flags{.Mouse_Clickable, .Keyboard_Clickable}
FLOATING :: Box_Flags{.Floating_X, .Floating_Y}
FIXED_SIZE :: Box_Flags{.Fixed_Width, .Fixed_Height}
ALLOW_OVERFLOW :: Box_Flags{.Allow_Overflow_X, .Allow_Overflow_Y}
VIEW_SCROLL :: Box_Flags{.View_Scroll_X, .View_Scroll_Y}
// Boxes that are a surface the pointer can land on. Invisible containers (like the full-screen
// windows layer) and plain text never block the boxes beneath them.
HIT_FLAGS :: Box_Flags{.Mouse_Clickable, .Scroll, .Draw_Background}

Custom_Draw :: proc(s: ^State, b: ^Box, data: rawptr)

Box :: struct {
    // tree links, rebuilt every build
    first, last, next, prev, parent: ^Box,
    child_count:                     int,

    // identity
    key:                             Key,
    first_touched_build:             u64,
    last_touched_build:              u64,

    // build parameters, reset whenever the box is rebuilt
    flags:                           Box_Flags,
    text:                            string, // display text, lives in the build arena
    pref_size:                       [Axis]Size,
    child_layout_axis:               Axis,
    text_align:                      Text_Align,
    text_padding:                    f32,
    font_size:                       f32,
    corner_radii:                    [Corner]f32,
    palette:                         Palette,
    transparency:                    f32, // 0 opaque, 1 invisible; applies to the subtree
    squish:                          f32, // 0 normal size, shrinks the subtree when drawn
    hover_cursor:                    Cursor,
    custom_draw:                     Custom_Draw,
    custom_data:                     rawptr,

    // layout: fixed_size/fixed_position are inputs for Fixed_*/Floating_* boxes and outputs otherwise
    fixed_size:                      Vec2,
    fixed_position:                  Vec2, // relative to the parent
    rect:                            Rect,
    clip:                            Rect, // inherited from clipping ancestors, excludes the box itself

    // persistent across builds
    fixed_position_animated:         Vec2,
    view_off:                        Vec2, // scroll offset of the children
    view_off_target:                 Vec2,
    view_bounds:                     Vec2, // size of the children's content
    hot_t, active_t, disabled_t:     f32,
    focus_hot_t, focus_active_t:     f32,
    text_cursor, text_mark:          int, // byte offsets, used by line_edit
}

//- signals

Signal_Flag :: enum {
    Left_Pressed,
    Middle_Pressed,
    Right_Pressed,
    Left_Dragging,
    Middle_Dragging,
    Right_Dragging,
    Left_Released,
    Middle_Released,
    Right_Released,
    Left_Clicked, // released over the box it was pressed on
    Middle_Clicked,
    Right_Clicked,
    Left_Double_Clicked,
    Left_Triple_Clicked,
    Keyboard_Pressed, // Enter/Space while focused
    Hovering,         // mouse over and not blocked by another box's drag
    Mouse_Over,       // mouse over, even during some other box's drag
    Commit,           // a text field finished editing with Enter
}
Signal_Flags :: bit_set[Signal_Flag;u32]

Signal :: struct {
    box:    ^Box,
    flags:  Signal_Flags,
    scroll: Vec2,
    mods:   Modifiers,
}

//- input

Mouse_Button :: enum { Left, Middle, Right }
Modifier :: enum { Shift, Ctrl, Alt }
Modifiers :: bit_set[Modifier]
Cursor :: enum { Default, Pointer, Text, Resize_EW, Resize_NS, Resize_NWSE, Move, Not_Allowed }

Input_Key :: enum {
    None, Tab, Enter, Escape, Space, Backspace, Delete,
    Left, Right, Up, Down, Home, End, Page_Up, Page_Down,
    A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
    F1, F2, F3, F4, F5, F6, F7, F8, F9, F10, F11, F12,
}

Event_Kind :: enum { Move, Press, Release, Scroll, Key_Press, Key_Release, Text, Leave, Cancel }
Event :: struct {
    kind:     Event_Kind,
    pos:      Vec2, // logical pixels
    button:   Mouse_Button,
    scroll:   Vec2, // logical pixels; positive y scrolls down
    key:      Input_Key,
    mods:     Modifiers,
    text:     rune,
    repeat:   bool,
    consumed: bool,
    // filled by begin_build from the previous layout: who is under the pointer
    target:   Key, // Press: deepest clickable box; Scroll: deepest scrollable box
    chain:    []Key, // Press: every box under the pointer, top-most first
}

Measure_Text :: proc(text: string, font_size: f32) -> Vec2

//- drawing output

Rect_Draw :: struct {
    rect:     Rect,
    colors:   [Corner]Color,
    radii:    [Corner]f32,
    border:   f32, // 0 fills the rect
    softness: f32, // edge blur in pixels, for shadows
}
Text_Draw :: struct {
    text:      string,
    pos:       Vec2, // top-left of the first line
    color:     Color,
    font_size: f32,
}
Draw_Payload :: union { Rect_Draw, Text_Draw }
Draw_Command :: struct {
    clip:    Rect,
    payload: Draw_Payload,
}

//- state

Stack_Item :: struct($T: typeid) {
    value:    T,
    auto_pop: bool, // pushed by set_next_*: popped after the next box is built
}
Stack :: struct($T: typeid) {
    items: [dynamic]Stack_Item(T),
}

Stacks :: struct {
    parent:            Stack(^Box),
    child_layout_axis: Stack(Axis),
    pref_width:        Stack(Size),
    pref_height:       Stack(Size),
    fixed_x:           Stack(Maybe(f32)),
    fixed_y:           Stack(Maybe(f32)),
    fixed_width:       Stack(Maybe(f32)),
    fixed_height:      Stack(Maybe(f32)),
    flags:             Stack(Box_Flags),
    text_align:        Stack(Text_Align),
    text_padding:      Stack(f32),
    font_size:         Stack(f32),
    corner_radii:      Stack([Corner]f32),
    palette:           Stack(Palette),
    transparency:      Stack(f32),
    squish:            Stack(f32),
    hover_cursor:      Stack(Cursor),
}

Anim :: struct {
    value, target: f32,
    last_build:    u64,
}

Ctx_Menu :: struct {
    key:          Key,
    anchor_key:   Key,
    anchor_off:   Vec2,
    open:         bool,
    opened_build: u64,
    built:        bool, // touched during the current build
    container:    ^Box, // the menu's panel while it's being built
    width:        f32, // widest item so far, measured while building
}

Window_State :: struct {
    pos, size:  Vec2,
    last_build: u64,
}

State :: struct {
    allocator:          mem.Allocator,
    // Double buffered: the previous build's transient boxes, strings and draw order stay valid
    // while the next build routes input through them.
    build_arenas:       [2]mem.Dynamic_Arena,
    cache:              map[Key]^Box,
    free_boxes:         [dynamic]^Box,
    stacks:             Stacks,
    theme:              Theme,
    measure_text:       Measure_Text,

    // current build
    build_index:        u64,
    building:           bool,
    viewport:           Vec2,
    dt:                 f32,
    time:               f64,
    events:             [dynamic]Event,
    root:               ^Box,
    windows_root:       ^Box,
    tooltip_root:       ^Box,
    ctx_menu_root:      ^Box,
    built_boxes:        [dynamic]^Box, // this build, in build order

    // interaction
    mouse:              Vec2,
    mouse_inside:       bool,
    mods:               Modifiers,
    hover_chain:        [dynamic]Key, // boxes under the mouse, top-most first
    hot:                Key,
    active:             [Mouse_Button]Key,
    focus_hot:          Key, // keyboard focus
    focus_active:       Key, // keyboard focus that owns text input (an editing line_edit)
    focus_visible:      bool, // focus came from the keyboard, so draw the focus border
    drag_start_mouse:   Vec2,
    drag_data:          [dynamic]u8,
    last_press_time:    f64,
    last_press_key:     Key,
    last_press_pos:     Vec2,
    press_count:        int,
    anims:              map[Key]Anim,
    ctx_menu:           Ctx_Menu,
    windows:            map[Key]Window_State,
    window_order:       [dynamic]Key, // front to back
    window_stack:       [dynamic]^Box,
    scroll_stack:       [dynamic][2]^Box,
    tooltip_key:        Key, // box whose hover is being timed for a tooltip
    tooltip_time:       f32,
    tooltip_wanted:     bool,
    clipboard:          [dynamic]u8,
    set_clipboard:      proc(text: string), // optional: defaults to an internal buffer
    get_clipboard:      proc() -> string,

    // results of end_build
    commands:           [dynamic]Draw_Command,
    draw_order:         [dynamic]^Box, // painter order, previous build
    focus_order:        [dynamic]Key, // keyboard-clickable boxes in tree order
    cursor:             Cursor,
    animating:          bool, // another build is needed soon even without input

    // draw traversal state, used by custom draw callbacks through draw_rect/draw_text
    draw_clip:          Rect,
    draw_scale:         f32,
    draw_offset:        Vec2,
    draw_alpha:         f32,
    debug_bounds:       bool,
}
