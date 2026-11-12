package wayland

// @note: Bindings for libxkbcommon, which turns Wayland's physical key codes into keysyms and text
// @note: using the keyboard layout the compositor sends us. C enums are int sized, so they are c.int here.

import "core:c"

foreign import xkb "system:xkbcommon"

xkb_context :: struct {}
xkb_keymap :: struct {}
xkb_state :: struct {}

XKB_CONTEXT_NO_FLAGS :: 0
XKB_KEYMAP_FORMAT_TEXT_V1 :: 1
XKB_KEYMAP_COMPILE_NO_FLAGS :: 0

// @note: ASCII
XKB_KEY_BackSpace :: 0xff08 /* @note: U+0008 BACKSPACE */
XKB_KEY_Tab :: 0xff09 /* @note: U+0009 CHARACTER TABULATION */
XKB_KEY_Linefeed :: 0xff0a /* @note: U+000A LINE FEED */
XKB_KEY_Clear :: 0xff0b /* @note: U+000B LINE TABULATION */
XKB_KEY_Return :: 0xff0d /* @note: U+000D CARRIAGE RETURN */
XKB_KEY_Pause :: 0xff13 /* @note: Pause, hold */
XKB_KEY_Scroll_Lock :: 0xff14
XKB_KEY_Sys_Req :: 0xff15
XKB_KEY_Escape :: 0xff1b /* @note: U+001B ESCAPE */
XKB_KEY_Delete :: 0xffff /* @note: U+007F DELETE */
XKB_KEY_space :: 0x0020 /* @note: U+0020 SPACE */
XKB_KEY_exclam :: 0x0021 /* @note: U+0021 EXCLAMATION MARK */
XKB_KEY_quotedbl :: 0x0022 /* @note: U+0022 QUOTATION MARK */
XKB_KEY_numbersign :: 0x0023 /* @note: U+0023 NUMBER SIGN */
XKB_KEY_dollar :: 0x0024 /* @note: U+0024 DOLLAR SIGN */
XKB_KEY_percent :: 0x0025 /* @note: U+0025 PERCENT SIGN */
XKB_KEY_ampersand :: 0x0026 /* @note: U+0026 AMPERSAND */
XKB_KEY_apostrophe :: 0x0027 /* @note: U+0027 APOSTROPHE */
XKB_KEY_quoteright :: 0x0027 /* @note: deprecated */
XKB_KEY_parenleft :: 0x0028 /* @note: U+0028 LEFT PARENTHESIS */
XKB_KEY_parenright :: 0x0029 /* @note: U+0029 RIGHT PARENTHESIS */
XKB_KEY_asterisk :: 0x002a /* @note: U+002A ASTERISK */
XKB_KEY_plus :: 0x002b /* @note: U+002B PLUS SIGN */
XKB_KEY_comma :: 0x002c /* @note: U+002C COMMA */
XKB_KEY_minus :: 0x002d /* @note: U+002D HYPHEN-MINUS */
XKB_KEY_period :: 0x002e /* @note: U+002E FULL STOP */
XKB_KEY_slash :: 0x002f /* @note: U+002F SOLIDUS */
XKB_KEY_0 :: 0x0030 /* @note: U+0030 DIGIT ZERO */
XKB_KEY_1 :: 0x0031 /* @note: U+0031 DIGIT ONE */
XKB_KEY_2 :: 0x0032 /* @note: U+0032 DIGIT TWO */
XKB_KEY_3 :: 0x0033 /* @note: U+0033 DIGIT THREE */
XKB_KEY_4 :: 0x0034 /* @note: U+0034 DIGIT FOUR */
XKB_KEY_5 :: 0x0035 /* @note: U+0035 DIGIT FIVE */
XKB_KEY_6 :: 0x0036 /* @note: U+0036 DIGIT SIX */
XKB_KEY_7 :: 0x0037 /* @note: U+0037 DIGIT SEVEN */
XKB_KEY_8 :: 0x0038 /* @note: U+0038 DIGIT EIGHT */
XKB_KEY_9 :: 0x0039 /* @note: U+0039 DIGIT NINE */
XKB_KEY_colon :: 0x003a /* @note: U+003A COLON */
XKB_KEY_semicolon :: 0x003b /* @note: U+003B SEMICOLON */
XKB_KEY_less :: 0x003c /* @note: U+003C LESS-THAN SIGN */
XKB_KEY_equal :: 0x003d /* @note: U+003D EQUALS SIGN */
XKB_KEY_greater :: 0x003e /* @note: U+003E GREATER-THAN SIGN */
XKB_KEY_question :: 0x003f /* @note: U+003F QUESTION MARK */
XKB_KEY_at :: 0x0040 /* @note: U+0040 COMMERCIAL AT */
XKB_KEY_A :: 0x0041 /* @note: U+0041 LATIN CAPITAL LETTER A */
XKB_KEY_B :: 0x0042 /* @note: U+0042 LATIN CAPITAL LETTER B */
XKB_KEY_C :: 0x0043 /* @note: U+0043 LATIN CAPITAL LETTER C */
XKB_KEY_D :: 0x0044 /* @note: U+0044 LATIN CAPITAL LETTER D */
XKB_KEY_E :: 0x0045 /* @note: U+0045 LATIN CAPITAL LETTER E */
XKB_KEY_F :: 0x0046 /* @note: U+0046 LATIN CAPITAL LETTER F */
XKB_KEY_G :: 0x0047 /* @note: U+0047 LATIN CAPITAL LETTER G */
XKB_KEY_H :: 0x0048 /* @note: U+0048 LATIN CAPITAL LETTER H */
XKB_KEY_I :: 0x0049 /* @note: U+0049 LATIN CAPITAL LETTER I */
XKB_KEY_J :: 0x004a /* @note: U+004A LATIN CAPITAL LETTER J */
XKB_KEY_K :: 0x004b /* @note: U+004B LATIN CAPITAL LETTER K */
XKB_KEY_L :: 0x004c /* @note: U+004C LATIN CAPITAL LETTER L */
XKB_KEY_M :: 0x004d /* @note: U+004D LATIN CAPITAL LETTER M */
XKB_KEY_N :: 0x004e /* @note: U+004E LATIN CAPITAL LETTER N */
XKB_KEY_O :: 0x004f /* @note: U+004F LATIN CAPITAL LETTER O */
XKB_KEY_P :: 0x0050 /* @note: U+0050 LATIN CAPITAL LETTER P */
XKB_KEY_Q :: 0x0051 /* @note: U+0051 LATIN CAPITAL LETTER Q */
XKB_KEY_R :: 0x0052 /* @note: U+0052 LATIN CAPITAL LETTER R */
XKB_KEY_S :: 0x0053 /* @note: U+0053 LATIN CAPITAL LETTER S */
XKB_KEY_T :: 0x0054 /* @note: U+0054 LATIN CAPITAL LETTER T */
XKB_KEY_U :: 0x0055 /* @note: U+0055 LATIN CAPITAL LETTER U */
XKB_KEY_V :: 0x0056 /* @note: U+0056 LATIN CAPITAL LETTER V */
XKB_KEY_W :: 0x0057 /* @note: U+0057 LATIN CAPITAL LETTER W */
XKB_KEY_X :: 0x0058 /* @note: U+0058 LATIN CAPITAL LETTER X */
XKB_KEY_Y :: 0x0059 /* @note: U+0059 LATIN CAPITAL LETTER Y */
XKB_KEY_Z :: 0x005a /* @note: U+005A LATIN CAPITAL LETTER Z */
XKB_KEY_bracketleft :: 0x005b /* @note: U+005B LEFT SQUARE BRACKET */
XKB_KEY_backslash :: 0x005c /* @note: U+005C REVERSE SOLIDUS */
XKB_KEY_bracketright :: 0x005d /* @note: U+005D RIGHT SQUARE BRACKET */
XKB_KEY_asciicircum :: 0x005e /* @note: U+005E CIRCUMFLEX ACCENT */
XKB_KEY_underscore :: 0x005f /* @note: U+005F LOW LINE */
XKB_KEY_grave :: 0x0060 /* @note: U+0060 GRAVE ACCENT */
XKB_KEY_quoteleft :: 0x0060 /* @note: deprecated */
XKB_KEY_a :: 0x0061 /* @note: U+0061 LATIN SMALL LETTER A */
XKB_KEY_b :: 0x0062 /* @note: U+0062 LATIN SMALL LETTER B */
XKB_KEY_c :: 0x0063 /* @note: U+0063 LATIN SMALL LETTER C */
XKB_KEY_d :: 0x0064 /* @note: U+0064 LATIN SMALL LETTER D */
XKB_KEY_e :: 0x0065 /* @note: U+0065 LATIN SMALL LETTER E */
XKB_KEY_f :: 0x0066 /* @note: U+0066 LATIN SMALL LETTER F */
XKB_KEY_g :: 0x0067 /* @note: U+0067 LATIN SMALL LETTER G */
XKB_KEY_h :: 0x0068 /* @note: U+0068 LATIN SMALL LETTER H */
XKB_KEY_i :: 0x0069 /* @note: U+0069 LATIN SMALL LETTER I */
XKB_KEY_j :: 0x006a /* @note: U+006A LATIN SMALL LETTER J */
XKB_KEY_k :: 0x006b /* @note: U+006B LATIN SMALL LETTER K */
XKB_KEY_l :: 0x006c /* @note: U+006C LATIN SMALL LETTER L */
XKB_KEY_m :: 0x006d /* @note: U+006D LATIN SMALL LETTER M */
XKB_KEY_n :: 0x006e /* @note: U+006E LATIN SMALL LETTER N */
XKB_KEY_o :: 0x006f /* @note: U+006F LATIN SMALL LETTER O */
XKB_KEY_p :: 0x0070 /* @note: U+0070 LATIN SMALL LETTER P */
XKB_KEY_q :: 0x0071 /* @note: U+0071 LATIN SMALL LETTER Q */
XKB_KEY_r :: 0x0072 /* @note: U+0072 LATIN SMALL LETTER R */
XKB_KEY_s :: 0x0073 /* @note: U+0073 LATIN SMALL LETTER S */
XKB_KEY_t :: 0x0074 /* @note: U+0074 LATIN SMALL LETTER T */
XKB_KEY_u :: 0x0075 /* @note: U+0075 LATIN SMALL LETTER U */
XKB_KEY_v :: 0x0076 /* @note: U+0076 LATIN SMALL LETTER V */
XKB_KEY_w :: 0x0077 /* @note: U+0077 LATIN SMALL LETTER W */
XKB_KEY_x :: 0x0078 /* @note: U+0078 LATIN SMALL LETTER X */
XKB_KEY_y :: 0x0079 /* @note: U+0079 LATIN SMALL LETTER Y */
XKB_KEY_z :: 0x007a /* @note: U+007A LATIN SMALL LETTER Z */
XKB_KEY_braceleft :: 0x007b /* @note: U+007B LEFT CURLY BRACKET */
XKB_KEY_bar :: 0x007c /* @note: U+007C VERTICAL LINE */
XKB_KEY_braceright :: 0x007d /* @note: U+007D RIGHT CURLY BRACKET */
XKB_KEY_asciitilde :: 0x007e /* @note: U+007E TILDE */


// @note: control modifiers
XKB_KEY_Shift_L :: 0xffe1 /* @note: Left shift */
XKB_KEY_Shift_R :: 0xffe2 /* @note: Right shift */
XKB_KEY_Control_L :: 0xffe3 /* @note: Left control */
XKB_KEY_Control_R :: 0xffe4 /* @note: Right control */
XKB_KEY_Caps_Lock :: 0xffe5 /* @note: Caps lock */
XKB_KEY_Shift_Lock :: 0xffe6 /* @note: Shift lock */
XKB_KEY_Meta_L :: 0xffe7 /* @note: Left meta */
XKB_KEY_Meta_R :: 0xffe8 /* @note: Right meta */
XKB_KEY_Alt_L :: 0xffe9 /* @note: Left alt */
XKB_KEY_Alt_R :: 0xffea /* @note: Right alt */
XKB_KEY_Super_L :: 0xffeb /* @note: Left super */
XKB_KEY_Super_R :: 0xffec /* @note: Right super */
XKB_KEY_Hyper_L :: 0xffed /* @note: Left hyper */
XKB_KEY_Hyper_R :: 0xffee /* @note: Right hyper */

/* @note: Keypad functions, keypad numbers cleverly chosen to map to ASCII */

XKB_KEY_KP_Space :: 0xff80 /* @note: <U+0020 SPACE>*/
XKB_KEY_KP_Tab :: 0xff89 /* @note: <U+0009 CHARACTER TABULATION>*/
XKB_KEY_KP_Enter :: 0xff8d /* @note: <U+000D CARRIAGE RETURN>*/
XKB_KEY_KP_F1 :: 0xff91 /* @note: PF1, KP_A, ... */
XKB_KEY_KP_F2 :: 0xff92
XKB_KEY_KP_F3 :: 0xff93
XKB_KEY_KP_F4 :: 0xff94
XKB_KEY_KP_Home :: 0xff95
XKB_KEY_KP_Left :: 0xff96
XKB_KEY_KP_Up :: 0xff97
XKB_KEY_KP_Right :: 0xff98
XKB_KEY_KP_Down :: 0xff99
XKB_KEY_KP_Prior :: 0xff9a
XKB_KEY_KP_Page_Up :: 0xff9a /* @note: deprecated alias for KP_Prior */
XKB_KEY_KP_Next :: 0xff9b
XKB_KEY_KP_Page_Down :: 0xff9b /* @note: deprecated alias for KP_Next */
XKB_KEY_KP_End :: 0xff9c
XKB_KEY_KP_Begin :: 0xff9d
XKB_KEY_KP_Insert :: 0xff9e
XKB_KEY_KP_Delete :: 0xff9f
XKB_KEY_KP_Equal :: 0xffbd /* @note: <U+003D EQUALS SIGN>*/
XKB_KEY_KP_Multiply :: 0xffaa /* @note: <U+002A ASTERISK>*/
XKB_KEY_KP_Add :: 0xffab /* @note: <U+002B PLUS SIGN>*/
XKB_KEY_KP_Separator :: 0xffac /* @note: <U+002C COMMA>*/
XKB_KEY_KP_Subtract :: 0xffad /* @note: <U+002D HYPHEN-MINUS>*/
XKB_KEY_KP_Decimal :: 0xffae /* @note: <U+002E FULL STOP>*/
XKB_KEY_KP_Divide :: 0xffaf /* @note: <U+002F SOLIDUS>*/
XKB_KEY_KP_0 :: 0xffb0 /* @note: <U+0030 DIGIT ZERO>*/
XKB_KEY_KP_1 :: 0xffb1 /* @note: <U+0031 DIGIT ONE>*/
XKB_KEY_KP_2 :: 0xffb2 /* @note: <U+0032 DIGIT TWO>*/
XKB_KEY_KP_3 :: 0xffb3 /* @note: <U+0033 DIGIT THREE>*/
XKB_KEY_KP_4 :: 0xffb4 /* @note: <U+0034 DIGIT FOUR>*/
XKB_KEY_KP_5 :: 0xffb5 /* @note: <U+0035 DIGIT FIVE>*/
XKB_KEY_KP_6 :: 0xffb6 /* @note: <U+0036 DIGIT SIX>*/
XKB_KEY_KP_7 :: 0xffb7 /* @note: <U+0037 DIGIT SEVEN>*/
XKB_KEY_KP_8 :: 0xffb8 /* @note: <U+0038 DIGIT EIGHT>*/
XKB_KEY_KP_9 :: 0xffb9 /* @note: <U+0039 DIGIT NINE>*/

/* @note: Cursor control & motion */

XKB_KEY_Home :: 0xff50
XKB_KEY_Left :: 0xff51 /* @note: Move left, left arrow */
XKB_KEY_Up :: 0xff52 /* @note: Move up, up arrow */
XKB_KEY_Right :: 0xff53 /* @note: Move right, right arrow */
XKB_KEY_Down :: 0xff54 /* @note: Move down, down arrow */
XKB_KEY_Prior :: 0xff55 /* @note: Prior, previous */
XKB_KEY_Page_Up :: 0xff55 /* @note: deprecated alias for Prior */
XKB_KEY_Next :: 0xff56 /* @note: Next */
XKB_KEY_Page_Down :: 0xff56 /* @note: deprecated alias for Next */
XKB_KEY_End :: 0xff57 /* @note: EOL */
XKB_KEY_Begin :: 0xff58 /* @note: BOL */

@(default_calling_convention = "c")
foreign xkb {
    xkb_context_new :: proc(flags: c.int) -> ^xkb_context ---
    xkb_context_unref :: proc(ctx: ^xkb_context) ---
    xkb_keymap_new_from_string :: proc(ctx: ^xkb_context, str: cstring, format: c.int, flags: c.int) -> ^xkb_keymap ---
    xkb_keymap_unref :: proc(keymap: ^xkb_keymap) ---
    xkb_keymap_key_repeats :: proc(keymap: ^xkb_keymap, key: u32) -> c.int ---
    xkb_state_new :: proc(keymap: ^xkb_keymap) -> ^xkb_state ---
    xkb_state_unref :: proc(state: ^xkb_state) ---
    xkb_state_update_mask :: proc(state: ^xkb_state, depressed_mods, latched_mods, locked_mods: u32, depressed_layout, latched_layout, locked_layout: u32) -> c.int ---
    xkb_state_key_get_one_sym :: proc(state: ^xkb_state, key: u32) -> u32 ---
    xkb_state_key_get_utf32 :: proc(state: ^xkb_state, key: u32) -> u32 ---
}
