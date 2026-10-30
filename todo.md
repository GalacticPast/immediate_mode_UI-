# Text and renderer split

- [x] Move instance-array allocation and cleanup from `text` into the renderer.
- [x] Initialize renderer arrays with the supplied allocator and release them in `deinit`.
- [x] Import `text` in the renderer; qualify text types and constants.
- [x] Remove obsolete renderer references and the unused platform import from `text`.
- [ ] Split `push_string`: keep glyph placement in `text`, and shader-instance packing in the renderer.
- [x] Access font data through the text package instead of accessing `t_state` from the renderer.
- [x] Initialize and clean up text and renderer state in `main`.
- [x] Expose a renderer operation for uploading a loaded font.
- [x] Upload instances, draw, and clear the instance arrays via `end_command` and `render`.
- [x] Update `main` to initialize the renderer, upload the font, submit text, render, and clean up.
- [x] Run a compiler check.
- [ ] Verify the text still renders correctly.

# UI

- [x] Restore scoped `if` calls for builds, panels, rows, columns, and boxes.
- [x] Add a checkbox with custom drawing and caller-owned state.
- [ ] Check checkbox and text alignment visually using the actual font metrics.
- [ ] Handle a click on release after a press on the same widget, with cancellation when released outside.
- [ ] Preserve quick press-and-release interactions when both events arrive in the same build; test with a deliberately slow build loop.
- [ ] Review hit testing against previous-frame geometry when widgets move or first appear.
- [ ] Add layout and interaction tests, including sibling sizes and repeated builds.
- [ ] fix the checkbox text alignement

# Wayland cursor follow-ups

- [ ] Handle repeated seat capability events without creating duplicate pointers or cursor-shape devices.
- [ ] Destroy the cursor-shape device and release the pointer when pointer capability disappears; recreate them when it returns.
- [ ] Create the cursor-shape device if its manager becomes available after the pointer.
- [ ] Track pointer focus separately from the enter serial, including when the pointer is removed.
- [ ] Allow hiding the cursor with `.NONE` when the optional cursor-shape protocol is unavailable.
- [ ] Move Wayland-specific cursor shape values out of the shared `Pointer_Type` enum.
