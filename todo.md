# Text and renderer split

- [ ] Move instance-array allocation and cleanup from `text` into the renderer.
- [ ] Store the renderer's allocator so its state can be freed correctly.
- [ ] Import `text` in the renderer; qualify text types and constants.
- [ ] Remove obsolete renderer references and the unused platform import from `text`.
- [ ] Split `push_string`: keep glyph placement in `text`, and shader-instance packing in the renderer.
- [ ] Pass font/layout data explicitly instead of accessing `t_state` from the renderer.
- [ ] Connect renderer initialization and cleanup to `text_init` / `text_deinit`.
- [ ] Expose a renderer operation for uploading a loaded font.
- [ ] Add renderer `flush`: upload instances, draw, then clear the instance array.
- [ ] Update `main` to initialize the renderer, upload the font, submit text, flush, and clean up.
- [ ] Run a compiler check, then verify the same text still renders.
