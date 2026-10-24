package ui

import "core:mem"

// RAD keeps one stack per box property. A box takes the top of every stack when it's built.
// push_*/pop_* bracket a range of boxes, set_next_* applies to the next box only, and the
// scoped form pops at the end of the enclosing scope:
//
//     if ui.pref_width(s, ui.px(120)) { ...boxes... }
//     { ui.palette(s, s.theme.floating); ...boxes... }

stack_push :: proc(st: ^Stack($T), value: T, auto_pop := false) {
    append(&st.items, Stack_Item(T){value, auto_pop})
}
stack_pop :: proc(st: ^Stack($T)) -> T {
    assert(len(st.items) > 1, "UI stack underflow: more pops than pushes")
    return pop(&st.items).value
}
stack_top :: proc(st: ^Stack($T)) -> T {
    return st.items[len(st.items) - 1].value
}
stack_reset :: proc(st: ^Stack($T), base: T) {
    clear(&st.items)
    append(&st.items, Stack_Item(T){value = base})
}
@(private)
stack_auto_pop :: proc(st: ^Stack($T)) {
    for len(st.items) > 1 && st.items[len(st.items) - 1].auto_pop do pop(&st.items)
}
@(private)
stack_init :: proc(st: ^Stack($T), allocator: mem.Allocator) {
    st.items = make([dynamic]Stack_Item(T), allocator)
}

@(private)
stacks_init :: proc(s: ^State) {
    a := s.allocator
    st := &s.stacks
    stack_init(&st.parent, a)
    stack_init(&st.child_layout_axis, a)
    stack_init(&st.pref_width, a)
    stack_init(&st.pref_height, a)
    stack_init(&st.fixed_x, a)
    stack_init(&st.fixed_y, a)
    stack_init(&st.fixed_width, a)
    stack_init(&st.fixed_height, a)
    stack_init(&st.flags, a)
    stack_init(&st.text_align, a)
    stack_init(&st.text_padding, a)
    stack_init(&st.font_size, a)
    stack_init(&st.corner_radii, a)
    stack_init(&st.palette, a)
    stack_init(&st.transparency, a)
    stack_init(&st.squish, a)
    stack_init(&st.hover_cursor, a)
}

@(private)
stacks_destroy :: proc(s: ^State) {
    st := &s.stacks
    delete(st.parent.items)
    delete(st.child_layout_axis.items)
    delete(st.pref_width.items)
    delete(st.pref_height.items)
    delete(st.fixed_x.items)
    delete(st.fixed_y.items)
    delete(st.fixed_width.items)
    delete(st.fixed_height.items)
    delete(st.flags.items)
    delete(st.text_align.items)
    delete(st.text_padding.items)
    delete(st.font_size.items)
    delete(st.corner_radii.items)
    delete(st.palette.items)
    delete(st.transparency.items)
    delete(st.squish.items)
    delete(st.hover_cursor.items)
}

// The bottom of each stack: the defaults every build starts from.
@(private)
stacks_reset :: proc(s: ^State) {
    st := &s.stacks
    stack_reset(&st.parent, nil)
    stack_reset(&st.child_layout_axis, Axis.Y)
    stack_reset(&st.pref_width, fill())
    stack_reset(&st.pref_height, px(s.theme.row_height))
    stack_reset(&st.fixed_x, nil)
    stack_reset(&st.fixed_y, nil)
    stack_reset(&st.fixed_width, nil)
    stack_reset(&st.fixed_height, nil)
    stack_reset(&st.flags, Box_Flags{})
    stack_reset(&st.text_align, Text_Align.Left)
    stack_reset(&st.text_padding, 6)
    stack_reset(&st.font_size, s.theme.font_size)
    stack_reset(&st.corner_radii, [Corner]f32{})
    stack_reset(&st.palette, s.theme.base)
    stack_reset(&st.transparency, 0)
    stack_reset(&st.squish, 0)
    stack_reset(&st.hover_cursor, Cursor.Default)
}

@(private)
stacks_auto_pop :: proc(s: ^State) {
    st := &s.stacks
    stack_auto_pop(&st.parent)
    stack_auto_pop(&st.child_layout_axis)
    stack_auto_pop(&st.pref_width)
    stack_auto_pop(&st.pref_height)
    stack_auto_pop(&st.fixed_x)
    stack_auto_pop(&st.fixed_y)
    stack_auto_pop(&st.fixed_width)
    stack_auto_pop(&st.fixed_height)
    stack_auto_pop(&st.flags)
    stack_auto_pop(&st.text_align)
    stack_auto_pop(&st.text_padding)
    stack_auto_pop(&st.font_size)
    stack_auto_pop(&st.corner_radii)
    stack_auto_pop(&st.palette)
    stack_auto_pop(&st.transparency)
    stack_auto_pop(&st.squish)
    stack_auto_pop(&st.hover_cursor)
}

@(private)
stacks_balanced :: proc(s: ^State) -> bool {
    st := &s.stacks
    sizes := [?]int {
        len(st.parent.items), len(st.child_layout_axis.items), len(st.pref_width.items),
        len(st.pref_height.items), len(st.fixed_x.items), len(st.fixed_y.items),
        len(st.fixed_width.items), len(st.fixed_height.items), len(st.flags.items),
        len(st.text_align.items), len(st.text_padding.items), len(st.font_size.items),
        len(st.corner_radii.items), len(st.palette.items), len(st.transparency.items),
        len(st.squish.items), len(st.hover_cursor.items),
    }
    for n in sizes do if n != 1 do return false
    return true
}

//- parent

push_parent :: proc(s: ^State, b: ^Box) { stack_push(&s.stacks.parent, b) }
pop_parent :: proc(s: ^State) -> ^Box { return stack_pop(&s.stacks.parent) }
top_parent :: proc(s: ^State) -> ^Box { return stack_top(&s.stacks.parent) }
@(deferred_in = end_parent)
parent :: proc(s: ^State, b: ^Box) -> bool { push_parent(s, b); return true }
end_parent :: proc(s: ^State, b: ^Box) { pop_parent(s) }

//- layout

push_child_layout_axis :: proc(s: ^State, v: Axis) { stack_push(&s.stacks.child_layout_axis, v) }
pop_child_layout_axis :: proc(s: ^State) -> Axis { return stack_pop(&s.stacks.child_layout_axis) }
set_next_child_layout_axis :: proc(s: ^State, v: Axis) { stack_push(&s.stacks.child_layout_axis, v, true) }

push_pref_width :: proc(s: ^State, v: Size) { stack_push(&s.stacks.pref_width, v) }
pop_pref_width :: proc(s: ^State) -> Size { return stack_pop(&s.stacks.pref_width) }
set_next_pref_width :: proc(s: ^State, v: Size) { stack_push(&s.stacks.pref_width, v, true) }
@(deferred_in = end_pref_width)
pref_width :: proc(s: ^State, v: Size) -> bool { push_pref_width(s, v); return true }
end_pref_width :: proc(s: ^State, v: Size) { pop_pref_width(s) }

push_pref_height :: proc(s: ^State, v: Size) { stack_push(&s.stacks.pref_height, v) }
pop_pref_height :: proc(s: ^State) -> Size { return stack_pop(&s.stacks.pref_height) }
set_next_pref_height :: proc(s: ^State, v: Size) { stack_push(&s.stacks.pref_height, v, true) }
@(deferred_in = end_pref_height)
pref_height :: proc(s: ^State, v: Size) -> bool { push_pref_height(s, v); return true }
end_pref_height :: proc(s: ^State, v: Size) { pop_pref_height(s) }

set_next_pref_size :: proc(s: ^State, width, height: Size) {
    set_next_pref_width(s, width)
    set_next_pref_height(s, height)
}

// fixed_x/fixed_y make the box floating at that offset from its parent.
push_fixed_x :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_x, Maybe(f32)(v)) }
pop_fixed_x :: proc(s: ^State) { stack_pop(&s.stacks.fixed_x) }
set_next_fixed_x :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_x, Maybe(f32)(v), true) }
push_fixed_y :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_y, Maybe(f32)(v)) }
pop_fixed_y :: proc(s: ^State) { stack_pop(&s.stacks.fixed_y) }
set_next_fixed_y :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_y, Maybe(f32)(v), true) }
set_next_fixed_pos :: proc(s: ^State, pos: Vec2) {
    set_next_fixed_x(s, pos.x)
    set_next_fixed_y(s, pos.y)
}

// fixed_width/fixed_height bypass the size passes entirely.
push_fixed_width :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_width, Maybe(f32)(v)) }
pop_fixed_width :: proc(s: ^State) { stack_pop(&s.stacks.fixed_width) }
set_next_fixed_width :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_width, Maybe(f32)(v), true) }
push_fixed_height :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_height, Maybe(f32)(v)) }
pop_fixed_height :: proc(s: ^State) { stack_pop(&s.stacks.fixed_height) }
set_next_fixed_height :: proc(s: ^State, v: f32) { stack_push(&s.stacks.fixed_height, Maybe(f32)(v), true) }
set_next_fixed_size :: proc(s: ^State, size: Vec2) {
    set_next_fixed_width(s, size.x)
    set_next_fixed_height(s, size.y)
}

//- flags (added to the flags each box is built with)

push_flags :: proc(s: ^State, v: Box_Flags) { stack_push(&s.stacks.flags, stack_top(&s.stacks.flags) | v) }
pop_flags :: proc(s: ^State) -> Box_Flags { return stack_pop(&s.stacks.flags) }
set_next_flags :: proc(s: ^State, v: Box_Flags) { stack_push(&s.stacks.flags, stack_top(&s.stacks.flags) | v, true) }
@(deferred_in = end_flags)
flags :: proc(s: ^State, v: Box_Flags) -> bool { push_flags(s, v); return true }
end_flags :: proc(s: ^State, v: Box_Flags) { pop_flags(s) }

// Everything built in the scope is drawn dimmed and ignores input.
@(deferred_in = end_disabled)
disabled :: proc(s: ^State, is_disabled := true) -> bool {
    push_flags(s, is_disabled ? {.Disabled} : {})
    return true
}
end_disabled :: proc(s: ^State, is_disabled := true) { pop_flags(s) }

//- text

push_text_align :: proc(s: ^State, v: Text_Align) { stack_push(&s.stacks.text_align, v) }
pop_text_align :: proc(s: ^State) -> Text_Align { return stack_pop(&s.stacks.text_align) }
set_next_text_align :: proc(s: ^State, v: Text_Align) { stack_push(&s.stacks.text_align, v, true) }
@(deferred_in = end_text_align)
text_align :: proc(s: ^State, v: Text_Align) -> bool { push_text_align(s, v); return true }
end_text_align :: proc(s: ^State, v: Text_Align) { pop_text_align(s) }

push_text_padding :: proc(s: ^State, v: f32) { stack_push(&s.stacks.text_padding, v) }
pop_text_padding :: proc(s: ^State) -> f32 { return stack_pop(&s.stacks.text_padding) }
set_next_text_padding :: proc(s: ^State, v: f32) { stack_push(&s.stacks.text_padding, v, true) }

push_font_size :: proc(s: ^State, v: f32) { stack_push(&s.stacks.font_size, v) }
pop_font_size :: proc(s: ^State) -> f32 { return stack_pop(&s.stacks.font_size) }
set_next_font_size :: proc(s: ^State, v: f32) { stack_push(&s.stacks.font_size, v, true) }
@(deferred_in = end_font_size)
font_size :: proc(s: ^State, v: f32) -> bool { push_font_size(s, v); return true }
end_font_size :: proc(s: ^State, v: f32) { pop_font_size(s) }

//- appearance

push_corner_radius :: proc(s: ^State, v: f32) { stack_push(&s.stacks.corner_radii, all_corners(v)) }
push_corner_radii :: proc(s: ^State, v: [Corner]f32) { stack_push(&s.stacks.corner_radii, v) }
pop_corner_radius :: proc(s: ^State) { stack_pop(&s.stacks.corner_radii) }
set_next_corner_radius :: proc(s: ^State, v: f32) { stack_push(&s.stacks.corner_radii, all_corners(v), true) }
set_next_corner_radii :: proc(s: ^State, v: [Corner]f32) { stack_push(&s.stacks.corner_radii, v, true) }
@(deferred_in = end_corner_radius)
corner_radius :: proc(s: ^State, v: f32) -> bool { push_corner_radius(s, v); return true }
end_corner_radius :: proc(s: ^State, v: f32) { pop_corner_radius(s) }

push_palette :: proc(s: ^State, v: Palette) { stack_push(&s.stacks.palette, v) }
pop_palette :: proc(s: ^State) -> Palette { return stack_pop(&s.stacks.palette) }
set_next_palette :: proc(s: ^State, v: Palette) { stack_push(&s.stacks.palette, v, true) }
top_palette :: proc(s: ^State) -> Palette { return stack_top(&s.stacks.palette) }
@(deferred_in = end_palette)
palette :: proc(s: ^State, v: Palette) -> bool { push_palette(s, v); return true }
end_palette :: proc(s: ^State, v: Palette) { pop_palette(s) }

push_transparency :: proc(s: ^State, v: f32) { stack_push(&s.stacks.transparency, v) }
pop_transparency :: proc(s: ^State) -> f32 { return stack_pop(&s.stacks.transparency) }
set_next_transparency :: proc(s: ^State, v: f32) { stack_push(&s.stacks.transparency, v, true) }
@(deferred_in = end_transparency)
transparency :: proc(s: ^State, v: f32) -> bool { push_transparency(s, v); return true }
end_transparency :: proc(s: ^State, v: f32) { pop_transparency(s) }

push_squish :: proc(s: ^State, v: f32) { stack_push(&s.stacks.squish, v) }
pop_squish :: proc(s: ^State) -> f32 { return stack_pop(&s.stacks.squish) }
set_next_squish :: proc(s: ^State, v: f32) { stack_push(&s.stacks.squish, v, true) }

push_hover_cursor :: proc(s: ^State, v: Cursor) { stack_push(&s.stacks.hover_cursor, v) }
pop_hover_cursor :: proc(s: ^State) -> Cursor { return stack_pop(&s.stacks.hover_cursor) }
set_next_hover_cursor :: proc(s: ^State, v: Cursor) { stack_push(&s.stacks.hover_cursor, v, true) }
