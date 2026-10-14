package wayland

// Bindings for libxkbcommon, which turns Wayland's physical key codes into keysyms and text
// using the keyboard layout the compositor sends us. C enums are int sized, so they are c.int here.

import "core:c"

foreign import xkb "system:xkbcommon"

xkb_context :: struct {}
xkb_keymap :: struct {}
xkb_state :: struct {}

XKB_CONTEXT_NO_FLAGS :: 0
XKB_KEYMAP_FORMAT_TEXT_V1 :: 1
XKB_KEYMAP_COMPILE_NO_FLAGS :: 0

@(default_calling_convention = "c")
foreign xkb {
    xkb_context_new            :: proc(flags: c.int) -> ^xkb_context ---
    xkb_context_unref          :: proc(ctx: ^xkb_context) ---
    xkb_keymap_new_from_string :: proc(ctx: ^xkb_context, str: cstring, format: c.int, flags: c.int) -> ^xkb_keymap ---
    xkb_keymap_unref           :: proc(keymap: ^xkb_keymap) ---
    xkb_keymap_key_repeats     :: proc(keymap: ^xkb_keymap, key: u32) -> c.int ---
    xkb_state_new              :: proc(keymap: ^xkb_keymap) -> ^xkb_state ---
    xkb_state_unref            :: proc(state: ^xkb_state) ---
    xkb_state_update_mask      :: proc(state: ^xkb_state, depressed_mods, latched_mods, locked_mods: u32, depressed_layout, latched_layout, locked_layout: u32) -> c.int ---
    xkb_state_key_get_one_sym  :: proc(state: ^xkb_state, key: u32) -> u32 ---
    xkb_state_key_get_utf32    :: proc(state: ^xkb_state, key: u32) -> u32 ---
}
