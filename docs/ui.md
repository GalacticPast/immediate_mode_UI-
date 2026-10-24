# Box UI

An Odin adaptation of RAD Debugger's UI layer (`src/ui/ui_core.*`, `ui_basic_widgets.c`),
drawn by this project's OpenGL renderer: analytic SDF boxes and Slug-style glyphs.

## Run and test

```sh
./build.sh && ./bin/app
odin test src/ui -out:/tmp/odin-ui-tests -vet
odin build src -out:bin/app-smoke -define:UI_SMOKE_TEST=true && ./bin/app-smoke   # writes bin/ui-preview-*.png
```

## Source map

| file | contents |
| --- | --- |
| `src/ui/ui.odin` | types: `Box`, flags, `Size`, `Signal`, events, draw commands, `State` |
| `src/ui/core.odin` | box cache and keys, `build_box`, `signal_from_box`, focus, animation, `begin_build`/`end_build` |
| `src/ui/stacks.odin` | per-property stacks: `push_*`, `pop_*`, `set_next_*`, scoped versions |
| `src/ui/layout.odin` | RAD's five layout passes, clipping |
| `src/ui/draw.odin` | tree to draw commands; `draw_rect`/`draw_text` for custom draw callbacks |
| `src/ui/theme.odin` | `Palette`, `Theme`, the default dark theme |
| `src/ui/text_edit.odin` | single-line text operations (pure, unit tested) |
| `src/ui/widgets.odin` | row/column/padding/panel, label, button, checkbox, radio, expander, slider, `slider_n`, progress bar, swatch, `line_edit` |
| `src/ui/popups.odin` | tooltip, context menu, menu bar, combo, window, scroll region, scroll bar |
| `src/ui_bridge.odin` | platform events to UI events; draw commands to the renderer |
| `src/demo.odin` | the demo app |

The `ui` package imports neither the platform nor the renderer. Text measurement is
injected, so tests use fake metrics. Coordinates are logical pixels.

## Frame

```odin
ui.begin_build(&state, viewport, events, dt)   // routes input through LAST build's layout
build_your_ui(&state)                          // boxes + signals
ui.end_build(&state)                           // prune, animate, layout, emit state.commands
render(state.commands)
platform.set_cursor(state.cursor)
// state.animating: build again soon even without input
```

## Boxes, keys, signals

Everything is a `Box`. `build_box(s, flags, "name")` makes one with the current top of every
stack. Keyed boxes persist in a cache: position, scroll offset and hot/active animation survive
between builds; everything else is rebuilt. Keys hash the name with the nearest keyed
ancestor. `"Label##id"` hides `##id` from the display text. `"Label###id"` also hashes only
`###id`, so the label can change. An empty name makes a transient box, which can't be
interacted with. A duplicate key in one build becomes transient, like RAD.

`signal_from_box(s, b)` consumes this build's events for `b` using the geometry from the
previous build and returns flags: `Left_Pressed`, `Left_Clicked`, `Left_Dragging`,
`Left_Double_Clicked`, `Right_Clicked`, `Keyboard_Pressed`, `Hovering`, `Mouse_Over`,
`Commit`, … Use the helpers `clicked`, `pressed`, `dragging`, `right_clicked`, `hovering`.

Occlusion: `begin_build` hit-tests every press against the previous draw order. A press goes
only to the deepest `Mouse_Clickable` box under the pointer, so a window over a button gets
the click no matter which signal is computed first. Only surfaces (`Draw_Background`,
`Mouse_Clickable`, `Scroll`) block the pointer. Invisible containers and text don't.

Draw order follows RAD: **earlier siblings are drawn on top**. The context-menu, tooltip and
window roots are built first in `begin_build`, so they cover the main UI.

## Stacks

Each box property has a stack (RAD's generated `ui_push_*`):

```odin
ui.push_pref_width(s, ui.px(120)); ...; ui.pop_pref_width(s)
ui.set_next_palette(s, s.theme.floating)       // the next box only
if ui.pref_width(s, ui.px(120)) { ... }        // scoped: pops when the if ends
{ ui.font_size(s, 12); ... }                   // scoped to the block
```

The scoped forms use `@(deferred_in)`. **The deferred pop runs at the end of the scope that
contains the call.** In an `if` condition that's the `if` statement itself, so
`if !ui.panel(s) do return` closes the panel immediately. Put the content inside the `if`
(or call it as a plain statement in a block). The compiler rejects deferred calls inside
`&&`/`||`.

Stacks: parent, child_layout_axis, pref_width/height, fixed_x/y (floating position),
fixed_width/height, flags, text_align, text_padding, font_size, corner radii, palette,
transparency, squish, hover_cursor. `end_build` asserts that every stack is balanced.

## Layout (RAD's `ui_layout_root`, per axis, X then Y)

1. standalone: `px(n)`, `text_dim(pad)`
2. upwards dependent: `pct(f)` of the nearest ancestor not sized by its children
3. downwards dependent: `children_sum()`
4. enforce constraints: children that overflow a parent are shrunk by their
   `(1 - strictness)` share; `Allow_Overflow_*` turns this off (scroll content)
5. position: children placed along `child_layout_axis`, offset by the parent's `view_off`;
   `Floating_*` boxes use `fixed_position`; `view_bounds` records the content size

`fill()` is `pct(1, 0)`: it takes what its siblings leave, and several fills split it evenly.
There are no padding/gap fields, as in RAD. Use `spacer`, `padding` or `panel`. A container
inside a scroll region must be `children_sum()` along the scrolling axis.

## Widgets and overlays

`label`, `label_weak`, `labelf`, `separator`, `button`, `button_flat`, `checkbox`, `radio`,
`expander`, `slider`, `slider_n`, `progress_bar`, `color_swatch`, `line_edit`, `combo`,
`menu_bar`/`menu`/`menu_item`, `ctx_menu_open`/`ctx_menu`, `tooltip`, `window`,
`scroll_region`, `scroll_bar`, and the layout helpers `row`, `column`, `spacer`, `padding`,
`panel`, `disabled`.

- **Tooltips** appear after the pointer rests 0.5 s; they never block hit testing.
- **Context menus** open anchored to a box (or the pointer). They close on Escape, on a press
  outside (presses on the anchor are left to it, so it can toggle), or when not built.
  Items measure themselves so the panel fits the widest one. Open/close animates
  transparency and squish.
- **Windows** are floating panels with a title bar (drag to move), optional close button,
  resize grip and drop shadow. A press anywhere in a window raises it.
- **line_edit** edits a caller-owned `[]u8` + length: click/drag/double-click (word)/
  triple-click (all) to select, arrows, Ctrl+arrows by word, Home/End, Backspace/Delete
  (Ctrl for words), Ctrl+A/C/X/V. Enter commits (`.Commit`), Escape or clicking elsewhere
  stops editing. Long text scrolls sideways to keep the caret visible.
- **Keyboard**: Tab/Shift+Tab move focus, Enter/Space press, arrows/Home/End adjust a
  focused slider. `key_pressed(s, .Q, {.Ctrl})` for app shortcuts.

## Look

A `Theme` holds palettes per surface (base, button, input, floating, title bar, menu bar,
tooltip, scroll bar). Widgets use the theme unless a palette was pushed or `set_next`'d.
Drawing supports alpha, per-corner radii, per-corner colors (gradients), borders and soft
edges, so hot/active effects are gradients and shadows are blurred SDF rects.
`transparency` and `squish` apply to whole subtrees (squish scales the drawing around the
box's center, or its top with `Squish_Anchored`).

Renderer packing (`src/renderer/draw.odin`, `assets/shaders/text_*.glsl`): box instances reuse
the glyph-only slots. Corner radii go in matrix column 0, border and softness in column 1, and
corner colors in the four band columns. Glyph alpha lives in the glyph matrix's column 2, which
never reaches the output because quad z is 0.

## Platform additions

Events now carry modifiers, typed text (`TEXT_INPUT`), right/middle buttons and 2-axis
scroll. Wayland applies xkb modifier state (so Shift changes keysyms and text), maps
Backspace/Delete/Home/End/PageUp/PageDown, and generates key repeat from `repeat_info`.
Windows uses `WM_CHAR`, `GetKeyState`, `WM_MOUSEHWHEEL` and `WM_SETCURSOR`. Both implement
`set_cursor` (Wayland: cursor-shape-v1).

## The demo app

`src/app.odin` builds a debugger for a toy VM (`src/vm.odin`) next to the original widget
gallery (`src/demo.odin`, now a tab). Things worth reading for how immediate mode pays off:

- `src/debugger.odin`: every panel reads the VM directly each frame. Registers flash and memory
  cells glow from a "last written" time, with no change events. Follow PC and the output console
  scroll by setting `ui.scroll_view(s).view_off_target`. Under 1180 px the memory view and the
  tools merge into one tabbed pane, decided by a single `if`.
- `src/inspector.odin`: `inspect` builds an editor for any value from its runtime type info
  (structs, arrays, enums, bit sets, numbers, `[4]f32` as colors). The Inspect tab uses it on the
  VM, the debugger and the live theme.
- `src/app.odin`: menus, Ctrl+P command palette with fuzzy filter, per-tab shortcuts (F5 run,
  F10 step, F9 breakpoint, Ctrl+R reset, Ctrl+T theme), and the status bar's build+layout time.
- `pane` and `tab_bar` are scoped widgets written in application code with `@(deferred_in_out)`,
  the same way the library writes its own.

## Not done (yet)

- System clipboard: copy/paste use an internal buffer unless `State.set_clipboard` /
  `get_clipboard` are set. Wayland needs `wl_data_device`. Windows' API is available but
  not wired.
- Icons: the font is ASCII-only, so arrows are drawn from rects. An icon font would go
  through the Slug glyph path.
- Background blur, docking/panels/tabs, multi-line text, IME, drag and drop, Unicode text
  rendering.
- RAD's per-box text runs, fuzzy-match highlighting and its full focus-navigation model.

## Attribution

Architectural reference, consulted 2026-10-24:

- https://github.com/EpicGamesExt/raddebugger/blob/master/src/ui/ui_core.h
- https://github.com/EpicGamesExt/raddebugger/blob/master/src/ui/ui_core.c
- https://github.com/EpicGamesExt/raddebugger/blob/master/src/ui/ui_basic_widgets.c

RAD Debugger is copyright (c) Epic Games Tools, MIT license, reproduced in
`third_party/raddebugger/LICENSE`. This code adapts its box, cache, stack, signal and layout
design. It is not a line-by-line translation.
