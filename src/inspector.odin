// A UI for any Odin value, generated from its runtime type info. Because the UI is rebuilt
// from the data every frame, a recursive procedure over the type is the whole implementation:
// no widget objects to create per field, nothing to keep in sync when the value changes.
package main

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:reflect"
import ui "ui"

Inspector :: struct {
    open: map[ui.Key]bool, // expanded state per path, e.g. "vm.regs"
}

INSPECT_MAX_ELEMS :: 16
INSPECT_MAX_DEPTH :: 8

// A number you change by dragging sideways (or with the arrow keys while focused).
// highlight (0..1) tints the background with the accent, used to flash changed values.
drag_number :: proc(s: ^ui.State, name: string, value: ^f64, speed: f64, is_int: bool, highlight: f32 = 0) -> (changed: bool) {
    pal := s.theme.input
    pal.background += (pal.accent - pal.background) * clamp(highlight, 0, 1) * 0.6
    ui.set_next_palette(s, pal)
    ui.set_next_corner_radius(s, 3)
    ui.set_next_text_align(s, .Center)
    ui.set_next_hover_cursor(s, .Resize_EW)
    b := ui.build_box(s, ui.CLICKABLE + {.Draw_Background, .Draw_Border, .Draw_Text, .Draw_Hot_Effects}, name)
    sig := ui.signal_from_box(s, b)
    before := value^
    if .Left_Pressed in sig.flags do ui.store_drag_data(s, value^)
    if ui.dragging(sig) do value^ = ui.get_drag_data(s, f64) + f64(ui.drag_delta(s).x) * speed
    if s.focus_hot == b.key {
        step := is_int ? 1 : speed * 10
        if ui.key_pressed(s, .Right) || ui.key_pressed(s, .Up) do value^ += step
        if ui.key_pressed(s, .Left) || ui.key_pressed(s, .Down) do value^ -= step
    }
    if is_int do value^ = math.round(value^)
    ui.set_text(s, b, is_int ? fmt.tprintf("%d", i64(value^)) : fmt.tprintf("%.3f", value^))
    return value^ != before
}

@(private = "file")
read_int :: proc(p: rawptr, size: int, signed: bool) -> i64 {
    switch size {
        case 1: return signed ? i64((^i8)(p)^) : i64((^u8)(p)^)
        case 2: return signed ? i64((^i16)(p)^) : i64((^u16)(p)^)
        case 4: return signed ? i64((^i32)(p)^) : i64((^u32)(p)^)
        case 8: return (^i64)(p)^
    }
    return 0
}

@(private = "file")
write_int :: proc(p: rawptr, size: int, v: i64) {
    switch size {
        case 1: (^u8)(p)^ = u8(v)
        case 2: (^u16)(p)^ = u16(v)
        case 4: (^u32)(p)^ = u32(v)
        case 8: (^i64)(p)^ = v
    }
}

// Each value is one row: indentation, the field name, then an editor.
@(private = "file")
row_begin :: proc(s: ^ui.State, path, name: string, depth: int) {
    ui.row_begin(s, ui.fill(), ui.children_sum(), fmt.tprintf("###%s", path))
    indent := f32(depth) * 14
    ui.spacer(s, ui.px(indent))
    ui.set_next_pref_width(s, ui.px(max(70, 160 - indent)))
    ui.label_weak(s, name)
}

// A collapsible row for aggregates. Returns whether the children should be built.
@(private = "file")
expander_row :: proc(s: ^ui.State, insp: ^Inspector, path, name, detail: string, depth: int) -> bool {
    key := ui.key_from_string(0, path)
    if key not_in insp.open do insp.open[key] = false
    ui.row_begin(s, ui.fill(), ui.children_sum(), fmt.tprintf("###%s", path))
    ui.spacer(s, ui.px(f32(depth) * 14))
    ui.expander(s, fmt.tprintf("%s   %s###x", name, detail), &insp.open[key])
    ui.row_end(s)
    return insp.open[key]
}

inspect :: proc(s: ^ui.State, insp: ^Inspector, name: string, data: rawptr, id: typeid, path: string = "", depth := 0) {
    path := path == "" ? name : path
    ti := type_info_of(id)
    base := runtime.type_info_base(ti)
    type_name := fmt.tprint(id)
    if depth > INSPECT_MAX_DEPTH {
        row_begin(s, path, name, depth)
        ui.label_weak(s, "...")
        ui.row_end(s)
        return
    }

    // Four floats are shown as a color: a swatch and four sliders. ui.Color is an alias of
    // [4]f32, not a distinct type, so the type info has no "Color" name to look for.
    if array, ok := base.variant.(runtime.Type_Info_Array); ok && array.count == 4 && array.elem.id == f32 {
        c := (^ui.Color)(data)
        row_begin(s, path, name, depth)
        ui.set_next_pref_size(s, ui.px(26), ui.px(22))
        ui.color_swatch(s, "##swatch", c^)
        ui.spacer(s, ui.px(6))
        ui.slider_n(s, "##rgba", c[:], 0, 1)
        ui.row_end(s)
        return
    }

    #partial switch info in base.variant {
        case runtime.Type_Info_Struct:
            if expander_row(s, insp, path, name, type_name, depth) {
                for f in reflect.struct_fields_zipped(id) {
                    field := rawptr(uintptr(data) + f.offset)
                    inspect(s, insp, f.name, field, f.type.id, fmt.tprintf("%s.%s", path, f.name), depth + 1)
                }
            }

        case runtime.Type_Info_Boolean:
            row_begin(s, path, name, depth)
            if ti.size == 1 {
                ui.checkbox(s, (^bool)(data)^ ? "true###v" : "false###v", (^bool)(data))
            } else {
                ui.label(s, fmt.tprint(any{data, id}))
            }
            ui.row_end(s)

        case runtime.Type_Info_Integer:
            row_begin(s, path, name, depth)
            v := f64(read_int(data, ti.size, info.signed))
            if drag_number(s, "##v", &v, 0.25, true) do write_int(data, ti.size, i64(v))
            ui.row_end(s)

        case runtime.Type_Info_Float:
            row_begin(s, path, name, depth)
            switch ti.size {
                case 4:
                    v := f64((^f32)(data)^)
                    if drag_number(s, "##v", &v, 0.01, false) do (^f32)(data)^ = f32(v)
                case 8:
                    drag_number(s, "##v", (^f64)(data), 0.01, false)
                case:
                    ui.label(s, fmt.tprint(any{data, id}))
            }
            ui.row_end(s)

        case runtime.Type_Info_Enum:
            row_begin(s, path, name, depth)
            names := reflect.enum_field_names(id)
            values := reflect.enum_field_values(id)
            current, _ := reflect.as_i64(any{data, id})
            index := -1
            for v, i in values do if i64(v) == current do index = i
            ui.combo(s, "##v", &index, names)
            if index >= 0 && i64(values[index]) != current do write_int(data, ti.size, i64(values[index]))
            ui.row_end(s)

        case runtime.Type_Info_Bit_Set:
            row_begin(s, path, name, depth)
            bits := read_int(data, ti.size, false)
            if elem := runtime.type_info_base(info.elem); elem != nil {
                if _, is_enum := elem.variant.(runtime.Type_Info_Enum); is_enum {
                    for field_name, i in reflect.enum_field_names(info.elem.id) {
                        bit := i64(reflect.enum_field_values(info.elem.id)[i]) - info.lower
                        on := bits & (1 << u64(bit)) != 0
                        ui.set_next_pref_width(s, ui.text_dim(34))
                        if ui.clicked(ui.checkbox(s, fmt.tprintf("%s##bit%d", field_name, i), &on)) {
                            bits ~= 1 << u64(bit)
                            write_int(data, ti.size, bits)
                        }
                    }
                } else {
                    ui.label(s, fmt.tprintf("%b", bits))
                }
            }
            ui.row_end(s)

        case runtime.Type_Info_String:
            row_begin(s, path, name, depth)
            ui.label(s, fmt.tprintf("%q", any{data, id}))
            ui.row_end(s)

        case runtime.Type_Info_Array:
            if expander_row(s, insp, path, name, type_name, depth) {
                inspect_elems(s, insp, path, data, info.elem.id, info.elem_size, info.count, depth, nil)
            }

        case runtime.Type_Info_Enumerated_Array:
            if expander_row(s, insp, path, name, type_name, depth) {
                inspect_elems(s, insp, path, data, info.elem.id, info.elem_size, info.count, depth, reflect.enum_field_names(info.index.id))
            }

        case runtime.Type_Info_Dynamic_Array:
            raw := (^runtime.Raw_Dynamic_Array)(data)
            if expander_row(s, insp, path, name, fmt.tprintf("%s, len %d", type_name, raw.len), depth) {
                inspect_elems(s, insp, path, raw.data, info.elem.id, info.elem_size, raw.len, depth, nil)
            }

        case runtime.Type_Info_Slice:
            raw := (^runtime.Raw_Slice)(data)
            if expander_row(s, insp, path, name, fmt.tprintf("%s, len %d", type_name, raw.len), depth) {
                inspect_elems(s, insp, path, raw.data, info.elem.id, info.elem_size, raw.len, depth, nil)
            }

        case runtime.Type_Info_Map:
            row_begin(s, path, name, depth)
            ui.label(s, fmt.tprintf("%s, %d entries", type_name, int((^runtime.Raw_Map)(data).len)))
            ui.row_end(s)

        case runtime.Type_Info_Pointer, runtime.Type_Info_Multi_Pointer, runtime.Type_Info_Procedure:
            // pointers aren't followed: cycles (box.parent.first...) would never end
            row_begin(s, path, name, depth)
            ui.label_weak(s, fmt.tprintf("%s  %p", type_name, (^rawptr)(data)^))
            ui.row_end(s)

        case runtime.Type_Info_Union:
            row_begin(s, path, name, depth)
            variant := reflect.union_variant_typeid(any{data, id})
            ui.label_weak(s, variant == nil ? "nil" : fmt.tprintf("%v: %v", variant, any{data, id}))
            ui.row_end(s)

        case:
            row_begin(s, path, name, depth)
            ui.label_weak(s, type_name)
            ui.row_end(s)
    }
}

@(private = "file")
inspect_elems :: proc(s: ^ui.State, insp: ^Inspector, path: string, data: rawptr, elem: typeid, elem_size, count: int, depth: int, names: []string) {
    shown := min(count, INSPECT_MAX_ELEMS)
    for i in 0 ..< shown {
        label := i < len(names) ? names[i] : fmt.tprintf("[%d]", i)
        inspect(s, insp, label, rawptr(uintptr(data) + uintptr(i * elem_size)), elem, fmt.tprintf("%s[%d]", path, i), depth + 1)
    }
    if count > shown {
        row_begin(s, fmt.tprintf("%s[more]", path), "", depth + 1)
        ui.label_weak(s, fmt.tprintf("... %d more", count - shown))
        ui.row_end(s)
    }
}
