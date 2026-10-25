package ui

Action_Type :: enum {
    NONE,
    PRESSABLE,
    HOVERABLE,
    DRAGGABLE,
    RESIZABLE,
}

Action_Types :: bit_set[Action_Type;u32]

Size_Type :: enum {
    NONE = 0,
    FIXED,
    BASED_ON_TEXT,
    BASED_ON_CHILDREN_SUM,
    BASED_ON_PARENT,
}
// it will default to vertical
Axis_Type :: enum {
    VERTICAL,
    HORIZONTAL,
}

Size :: struct {
    type:  Size_Type,
    pos:   [2]f32,
    dimen: [2]f32,
}

Box :: struct {
    // per build
    // first -> children
    prev, next, parent, first, last: ^Box,
    size:                            Size,
    action_type:                     Action_Types,
    children_layout_axis:            Axis_Type,

    //
}


window :: proc() -> bool {

    return false
}
