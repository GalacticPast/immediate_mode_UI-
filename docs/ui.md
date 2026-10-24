# Box UI prototype

This is an Odin adaptation of RAD Debugger's UI architecture, integrated with this
project's existing OpenGL renderer and analytic TrueType text rendering. It is a
working subset for studying and replacing, not a complete port of the debugger.

## Run and test

From the project root:

```sh
./build.sh
./bin/app
odin test src/ui -out:/tmp/odin-ui-tests -vet
```

On Windows, use `build.bat` and `bin\app.exe`.
Linux currently uses Wayland and requires OpenGL 4.5, as before.

The demo includes RGB sliders and a spanning preview, a resizable sidebar,
scrolling material selection, checkboxes, radio controls, collapsible sections,
a floating help window, disabled controls, and a weighted layout stress view.
Tab/Shift-Tab change focus; Enter/Space activate controls; arrows adjust sliders
and the divider; Home/End select slider endpoints. Escape closes the help window.
The window close control exits. Toggle “Show box bounds” to inspect geometry.

## Source map

- `src/ui/ui.odin`: shared types, box data, state, input, and drawing commands.
- `src/ui/core.odin`: keys, box cache, input routing, parent/style stacks,
  sizing, arrangement, and cache reclamation.
- `src/ui/widgets.odin`: small widget functions composed around the box API.
- `src/ui/draw.odin`: box traversal into an ordered drawing-command stream.
- `src/ui_bridge.odin`: platform input conversion and OpenGL drawing adapter.
- `src/demo.odin`: application data and the demonstration interface.
- `src/ui/ui_test.odin`: display-independent layout and interaction tests.

The core imports neither the platform nor the renderer. Text measurement is an
injected procedure, so the tests can use predictable metrics. UI coordinates are
logical pixels; only the rendering adapter converts to framebuffer pixels.

## Frame lifecycle and ownership

1. `begin_build` routes this frame's input through the previous frame's box
   geometry. Pointer capture preserves a drag outside its original rectangle.
2. Build widgets. Each keyed box is looked up in a cache; its hierarchy and
   appearance are replaced, while its old geometry, scroll position, and
   animation values survive. Widget procedures return that frame's `Signal`.
3. `end_build` measures and arranges the new tree, removes unused cached boxes,
   updates animation values, and emits draw commands.
4. The adapter renders the commands in painter order, batching adjacent commands
   with the same clip rectangle. The application then presents the frame.

`State` must remain at a stable address between `init` and `deinit`. It owns the
persistent box allocations, cache, arrays, and a dynamic build arena. Text and
custom drawing data are copied/allocated into that arena and survive until the
next `begin_build`. Draw commands have the same lifetime. Pointers to boxes that
are omitted from a build become invalid at `end_build`; use stable keys for
long-lived references. The application's temporary allocator can be reset
between frames without invalidating UI storage.

Application values (RGB, expansion flags, selected material) remain owned by the
application. They are not fields on every box. Specialized drawing uses a callback
and a build-lifetime payload. This lets the common box stay independent of slider,
checkbox, and radio data.

## Identity and scopes

Nonempty identifiers are hashed with the nearest keyed parent's ID. `##` hides a
suffix from display; `###` also makes the hash independent of the visible prefix.
For example, `Material 01###selection` and `Material 02###selection` identify the
same box in the same parent scope. Duplicate keys in a build assert instead of
silently aliasing. Renaming or reparenting an identifier changes its identity.

An empty identifier creates a transient box. Transient boxes cannot be clickable
or scrollable. Labels and purely visual decorations use them.

Parent scopes are explicit `push_parent`/`pop_parent` pairs. `begin_container` and
`end_container` wrap those calls. Style scopes similarly use
`push_style`/`pop_style`. `end_build` checks balance. Unlike RAD's implicit selected
state and generated C macros, procedures here take an explicit `^State` and the
style stack stores a complete `Style`. Per-box overrides are regular field writes.

## Sizing and layout

- `px(n, strictness)`: requested pixel size; strictness 1 prevents shrinking.
- `text_size(extra)`: measured text plus padding and extra space.
- `children()`: sum along the child layout axis, maximum across it, plus padding.
- `pct(fraction)`: fraction of the immediate parent's inner size.
- `fill(weight)`: share of remaining main-axis space; full cross-axis space.

Measurement runs bottom-up. Arrangement resolves percentages and fill shares
against available parent space, applies proportional shrinkage, and positions
children top-down. Vertical scroll containers preserve overflowing child heights,
clamp scroll offsets, and clip both drawing and hit testing. Floating boxes use
parent-relative offsets and do not contribute to normal flow.

This deliberately simplifies RAD's multi-pass dependency handling: percentages
use the immediate parent, and percentage/fill children contribute zero intrinsic
size when measuring a `children()` parent. Give an ancestor a definite size when
using percentage/fill sizing; this is not a general cyclic constraint solver.
Fill weights, explicit padding, and gaps are conveniences added by this prototype.

## Limits

- Uses previous-layout hit testing, including after resize. New boxes become
  interactive after their first layout. This follows the retained-geometry idea
  in RAD; it does not solve interaction against unknown future geometry.
- Keyboard controls cover focus and activation, not a complete navigation/accessibility
  system. Wayland key repeat is not implemented. Text entry/selection/IME,
  drag-and-drop, docking, and workspace persistence are not implemented.
- The text backend remains ASCII-only. This UI does not add Unicode shaping.
- Nested grids with shared intrinsic tracks, automatic wrapping, and CSS-style
  spans are not implemented. Nested rows/columns support the RGB preview example.
- Appearance uses RGB colors, rounded rectangles, borders, and text. No alpha
  style stack, shadows, blur, or RAD theme language is included.
- Input events supplied to the UI should already belong to the application's UI
  surface. The adapter currently handles left-button UI interaction.
- The renderer now preserves submission order rather than drawing every box
  before every glyph. GPU instance storage grows as needed; clipping flushes a
  batch. This favors correctness over minimizing draw calls.

## Attribution

Architectural reference consulted on 2026-10-24:

- https://github.com/EpicGamesExt/raddebugger/blob/master/src/ui/ui_core.h
- https://github.com/EpicGamesExt/raddebugger/blob/master/src/ui/ui_core.c
- https://github.com/EpicGamesExt/raddebugger/blob/master/src/ui/ui_basic_widgets.c

RAD Debugger is copyright (c) Epic Games Tools, distributed under the MIT license.
Its license is reproduced in `third_party/raddebugger/LICENSE`. The Odin code
adapts its box/cache/signal/layout concepts and is not a verbatim translation of
the complete upstream implementation.
