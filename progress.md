# UI architecture reference and rewrite progress

Reviewed on 2026-10-25. Reference branch: `rad`, commit
`952c0f70d761c96bd2e69d8d92605f05218d57f9`.

This file preserves the architecture of the finished prototype for the user's
independent rewrite on `main`. It describes the implementation at that commit;
it is not a requirement to reproduce every feature or design choice.

## Handoff and current workspace

- The user wants to write the implementation themselves and understand it.
  Use this reference to explain decisions and review their work. Do not silently
  copy the `rad` implementation into `main`.
- At review time the workspace was already on `main` at `23a460c`.
  `src/ui/ui.odin` contained the user's uncommitted starting types: `Action_Type`,
  `Action_Types`, `Size_Type`, `Size`, `Box`, and a placeholder `window` procedure.
  Those changes were left untouched.
- `rad` was inspected and built from a temporary archive. No branch switch or
  implementation changes were made during this review.
- The earlier explicit `mentor off` applied during this conversation. Follow
  `AGENTS.md` and `SKILL.md` for subsequent mentoring, including their session and
  mode rules. This document does not override them.
- Most paths below exist on `rad`, not yet on `main`. Read them without switching:
  `git show rad:src/ui/core.odin`. For the exact reviewed version, substitute the
  commit above for `rad`.

## What the prototype contains

The UI library has a cached box tree, property stacks, layout, input signals,
keyboard focus, animation, clipping, scrolling, widgets, single-line text editing,
tooltips, menus, and movable/resizable windows. The application demonstrates it
with a widget gallery and a debugger for a toy virtual machine. It does not debug
native programs.

The design is an Odin adaptation of RAD Debugger's box/cache/stack/signal/layout
architecture, not a complete translation of RAD Debugger. The branch's
`docs/ui.md` provides API notes and upstream references;
`third_party/raddebugger/LICENSE` records the MIT attribution.

## Layer boundaries and source map

```text
Platform events -> ui_bridge.ui_events -> UI events
                                         |
Application state -> app_build -> boxes + signals -> application mutations
                                         |
                          end_build: layout + drawing
                                         |
                                  draw commands
                                         |
                           ui_bridge.ui_render
                                         |
                         renderer -> OpenGL shaders
```

The `ui` package imports neither the platform nor the renderer. A text measurement
callback is injected at initialization. UI positions are logical pixels; the
backend handles display scaling and framebuffer coordinates.

| File on `rad` | Responsibility / useful entry points |
| --- | --- |
| `src/ui/ui.odin` | Shared types: `Box`, `State`, `Size`, flags, events, signals, draw commands |
| `src/ui/core.odin` | Initialization, identity/cache, `build_box`, `signal_from_box`, frame lifecycle, focus, animation |
| `src/ui/stacks.odin` | Generic `Stack(T)` and property-specific push/pop/set-next/scoped APIs |
| `src/ui/layout.odin` | Five passes per axis, absolute rectangles, inherited clips |
| `src/ui/draw.odin` | Tree traversal, visual effects, custom drawing, command generation |
| `src/ui/theme.odin` | `Palette`, `Theme`, dark and light themes |
| `src/ui/widgets.odin` | Layout helpers, labels, buttons, toggles, sliders, progress, color swatches, line edit |
| `src/ui/text_edit.odin` | Event-to-`Text_Op` conversion and buffer edits, independently testable |
| `src/ui/popups.odin` | Tooltips, context menus, menu bars, combo boxes, windows, scroll regions/bars |
| `src/ui_bridge.odin` | Event conversion, draw payload dispatch, scissor changes, cursor enum agreement |
| `src/renderer/draw.odin`, `opengl.odin` | Ordered instance batching, text measurement/drawing, GPU buffers |
| `assets/shaders/text_*.glsl` | Glyph and rounded-box rendering through the shared instance format |
| `src/main.odin` | Startup, event/build/render loop, cursor, animation deadlines, shutdown |
| `src/app.odin` | Application shell, menus, shortcuts, command palette, status bar |
| `src/demo.odin` | Widget gallery |
| `src/debugger.odin` | Debugger panels, splitters, tabs, watches, plot, execution controls |
| `src/vm.odin` | Toy machine, program, instruction execution, output and write timestamps |
| `src/inspector.odin` | Recursive editors built from Odin runtime type information |
| `src/ui/ui_test.odin`, `src/smoke.odin` | Headless tests and scripted rendered smoke run |

## Box model: common mechanisms, composed widgets

`Box` represents a node with independent traits. It has no button/slider/checkbox
tag and no union of every widget's state. A slider is a procedure that builds a
box, reads its signal, changes the caller's value, and attaches custom drawing.

The fields fall into these groups:

| Group | Contents and lifetime |
| --- | --- |
| Tree | `first`, `last`, `next`, `prev`, `parent`, `child_count`; rebuilt each frame |
| Identity | `key`, first/last touched build numbers |
| Build parameters | Flags, preferred sizes, child layout axis, text/style, custom draw callback/data; rebuilt |
| Geometry | `fixed_size`, `fixed_position`, absolute `rect`, inherited `clip`; geometry survives long enough for next-frame input |
| Persistent UI state | Animated position, scroll offsets/bounds, hot/active/disabled/focus animation values, text cursor/mark |

Application data stays outside the box: slider values, checkbox values, selected
tabs, expanded inspector nodes, text buffers, and VM state belong to callers.
`State` owns shared UI mechanisms such as active keys, focus, windows and menus.

Widget-specific drawing data such as `Fill_Draw` and `Line_Edit_Draw` is allocated
in the build arena and reached through `custom_data: rawptr` plus `custom_draw`.
The callback determines the payload type; this pair is not a checked tagged union.
The drawing output *does* use a tagged union: `Draw_Payload` contains `Rect_Draw`
or `Text_Draw`. The renderer bridge switches on that union.

## Identity and allocation

`State.cache` maps `Key` to persistent `^Box`. Keys use a parent-seeded FNV-1a hash
of the name. The seed comes from the nearest keyed ancestor on the parent stack.
The same local name can therefore appear in different containers.

- `Label##id`: display `Label`, hash the entire name.
- `Label###id`: display `Label`, hash only the suffix starting at `###`.
  Changing the visible label preserves identity under the same keyed ancestor.
- Empty names produce key zero and transient boxes. Their signals do not interact.
- A duplicate key within one build becomes transient. It does not steal the first
  box's persistent state, but the duplicate widget will not be interactive.
- Reparenting under a different keyed ancestor changes identity. List indices also
  change identity when items reorder; stable application IDs matter.

Persistent boxes use the state's allocator. Boxes absent from a build are removed
from the cache and placed on `free_boxes` for reuse; associated active/focus keys
are cleared. Do not retain box pointers as long-term application identifiers.

There are **two build arenas**, selected by `build_index % 2`. Beginning a build
resets the arena from two builds ago. The previous build's transient boxes and
strings remain valid while input is routed through its tree. Text supplied to
`build_box`/`set_text` is copied into the build arena.

`State` must remain at a stable address after `init`. `deinit` releases its caches,
arrays and arenas. Temporary allocator scratch is cleared by the main loop after
rendering. Draw commands are frame output and should be consumed before rebuilding.

## One frame, in order

1. Poll platform events and convert them to UI events. Obtain viewport and delta time.
2. `begin_build` advances the build number, rotates the arena, and copies events.
   It hit-tests presses and scrolling against the **previous** tree and draw order,
   storing target keys and ancestor chains. It handles global focus/menu input,
   resets property stacks, and creates the root and overlay roots.
3. Application procedures read current application data and build boxes. Widgets
   call `signal_from_box` to consume relevant events using preserved geometry.
   Those signals change application data directly. Shortcuts consume events too;
   the app handles them before building widgets to give them priority.
4. `end_build` checks balanced scopes, handles remaining input, prunes stale state,
   orders windows, updates animations/scroll offsets, lays out X then Y, computes
   clips, brings menus/tooltips into the viewport, and generates drawing output.
5. Render commands, set the platform cursor, and swap buffers. Schedule another
   frame while animating or dragging; otherwise wait for events. VM execution
   also requests continued updates through the UI's animation scheduling.

Previous-frame geometry is deliberate: immediate widget calls can return input
results before current-frame layout has finished. Newly appearing or moved widgets
need particular care because the hit-test geometry is one build behind.

## Property stacks and Odin scopes

Each property has its own stack. `build_box_from_key` reads their tops, combines
explicit flags with stacked flags, inherits disabled state, and consumes one-shot
stack entries.

- `push_*` / `pop_*` bracket several boxes.
- `set_next_*` supplies an override for the next box only.
- Scoped procedures use `@(deferred_in)` or `@(deferred_in_out)` to pair entry
  with cleanup. Conditional containers use the returned bool to decide cleanup.

The scope containing the call controls when the deferred procedure runs. The
reference uses `if ui.row(...) { ... }` or an explicit enclosing block. An early
guard such as `if !ui.panel(...) do return` ends its scope before later content.
`end_build` asserts balanced stacks and closed window/scroll scopes.

## Layout: five passes for each axis

`layout_root` runs these passes for X, then repeats them for Y:

1. **Standalone sizes:** resolve pixel and measured-text sizes.
2. **Upwards dependencies:** percentages use the nearest ancestor with an
   independently resolved size, skipping ancestors sized from their children.
3. **Downwards dependencies:** `children_sum` sums children along the parent's
   layout axis and takes the largest child across it. Floating children are excluded.
4. **Constraints:** shrink overflowing children within their permitted flexibility.
   Along the layout axis, weights are `child_size * (1 - strictness)`; across it,
   each child is constrained separately. Fixed sizes are protected. Overflow flags
   permit content to exceed its viewport.
5. **Positions:** advance a cursor along the layout axis, apply floating positions,
   subtract the parent's scroll offset, and compute absolute rectangles/content bounds.

`Size` contains kind, value, and strictness. `px`/`text_dim`/`children_sum` default
to strictness 1. `fill()` is `pct(1, 0)`, not a separate flex-grow algorithm: fills
initially request the ancestor size and shrink to share remaining space.
Strict children can still overflow when no shrink capacity remains.

`fixed_size` and `fixed_position` are inputs for fixed/floating boxes and layout
outputs otherwise. `Floating_X/Y` removes a box from normal flow on that axis;
`Fixed_Width/Height` protects its explicit dimensions from size resolution/shrinkage.

There is no CSS grid solver, row-span property, or general padding/gap field.
Spacing is composed with spacer boxes and nested row/column/panel helpers.
For the original RGB example, the tree can be:

```text
row
  column (three slider heights plus spacing)
    red slider
    spacer
    green slider
    spacer
    blue slider
  spacer
  preview (same explicit total height)
```

The preview is a sibling of the entire slider column. It does not need to span
three grid rows. Coordinating more general table columns or arbitrary spans would
need an additional layout policy. Scrolling content should use child-based sizing
along the scrolling axis rather than being shrunk to viewport height.

## Input, clipping and stacking

Signals report presses, releases, clicks, dragging, hover, multi-clicks, keyboard
activation and text commit. `State.active` stores a captured key per mouse button;
releasing inside the captured box produces a click. Keyboard navigation separates
`focus_hot` (focused control) from `focus_active` (control owning text input).

Hit testing scans the previous painter order backwards, finds the front surface,
and walks its ancestor chain to find a clickable/scrollable target. Event targets
are established before rebuilding, so the order of widget signal calls does not
choose which overlapping surface receives a press. Consumed events are skipped.

Only background, mouse-clickable or scroll surfaces enter pointer hit testing.
Invisible layout containers and plain labels allow underlying surfaces to receive
input. Disabled surfaces can block input; tooltips are excluded from hit testing.

**Earlier siblings draw on top.** Drawing visits children from `last` toward
`first`. Context-menu, tooltip and window roots are created before normal content,
placing those layers above it. Window order is stored separately and used to
relink window siblings; presses on a window's descendant chain raise the window.

Each box's `clip` is the intersection of clipping *ancestors*. A box with `.Clip`
intersects its own rectangle into the clip passed to children and its own content.
Hit tests use the box rectangle intersected with this inherited clip.

Scrolling separates `view_off_target` from animated `view_off`; `view_bounds`
records content size. Scrollbars are ordinary composed boxes. Their thumbs use
the viewport/content ratio and drag state to update the target offset.

## Drawing and text

Drawing emits backgrounds, gradients for hot/active effects, text, custom drawing,
children, borders/focus outlines, and disabled overlays. Theme palettes carry the
surface/text/accent/border colors. Subtree transparency and squish affect drawing.

`ui_render` preserves command order and flushes the instance batch when the clip
changes. It converts logical clips to physical pixels, rounds outward, and flips
the Y coordinate for OpenGL scissoring. Rectangles support RGBA, per-corner colors
and radii, borders and softness. Glyphs and rectangles share the instance buffer;
the shaders interpret fields according to the primitive type.

`line_edit` receives a caller-owned byte buffer and length. Cursor/selection live
on the cached box. `text_op_from_event` produces edit/movement data;
`text_op_apply` performs bounded replacement. The widget adds hit testing,
selection/caret drawing, horizontal scrolling, clipboard access and commit signals.
Text operations understand UTF-8 boundaries in several paths, but the rendering
pipeline is still ASCII-only; this is not full Unicode text support.

## Application examples worth studying later

- `debugger_build` composes disassembly, registers, memory and tools. At 1180
  logical pixels it switches between separate and combined memory/tools panes.
  Splitters modify caller-owned pane widths; this is application layout, not docking.
- Registers and memory derive highlight colors from VM write timestamps. Each
  frame reads the current model directly, without a second synchronized UI model.
- `inspect` walks runtime type information and builds editors for structs, arrays,
  enums, bit sets and numbers. Four `f32` values are treated as a color by convention.
- The command palette is an application-built floating window containing a text
  field and filtered menu items. Its fuzzy filter checks character subsequence order.
- `pane` and `tab_bar` demonstrate that application widgets can use the same
  composition/scoping techniques as library widgets.

## Validation and limits of this reference

Checked this exact snapshot using Odin `dev-2026-10:84bc3fc21`:

- `sh build.sh`: passed, including `-debug -vet`.
- `odin test src/ui -out:/tmp/odin-ui-tests -vet`: all 12 tests passed with memory
  tracking enabled and no reported memory issues.
- Smoke build with `-define:UI_SMOKE_TEST=true -vet`: passed.
- The 76-frame smoke run completed with exit code 0 and no OpenGL assertions.
  It captured frames 28, 48, 56 and 75. Visually reviewed 28, 56 and 75: debugger,
  filtered command palette, and light-theme inspector rendered successfully.

The tests cover fill/strict sizing, child/text measurement, set-next lifetime,
keys/duplicate handling, previous-layout clicks, window occlusion, scroll clamping,
text operations/edit commit, context menu dismissal, tooltip delay and disabling.
This review did not exercise every widget manually or validate Windows.

Boundaries to remember when learning from the prototype:

- No general CSS grid, docking system, multiline editor, IME, drag-and-drop,
  background blur, or full RAD focus-navigation system.
- Application panes/tabs exist, but are not a general dockable workspace engine.
- Clipboard defaults to an internal buffer; system clipboard callbacks are optional
  and platform integration is not wired in this snapshot.
- Drawing squish deliberately does not transform hit-test geometry.
- Focus order is collected during drawing traversal; do not assume it follows
  source/build order or provides modal focus trapping.
- Many geometry-dependent widget decisions use previous-frame sizes, including
  scrollbar visibility. Treat first appearance, resize and content shrink as useful
  cases to test in the rewrite.

## Suggested rewrite checkpoints

These are learning checkpoints, not claims that `main` already implements them.
Update this section as the user completes their own versions.

- [ ] Define a small box tree and establish allocation/ownership rules.
- [ ] Build a frame and draw explicit-position rectangles through the existing renderer.
- [ ] Add rows/columns, pixel sizes and text measurement.
- [ ] Add parent/child size dependencies and constraint handling; verify the RGB layout.
- [ ] Add stable identity and previous-build geometry.
- [ ] Add hit testing, hot/active state, a button, and a draggable slider.
- [ ] Add parent/style scopes only as repetition makes them useful.
- [ ] Add clipping, scrolling and painter-order occlusion.
- [ ] Add keyboard focus, text editing and overlays incrementally.

For future sessions: read this file, inspect the current `git diff`, and establish
which checkpoint the user is working on before suggesting changes. Prefer explaining
the smallest relevant mechanism over bringing the full reference implementation across.
