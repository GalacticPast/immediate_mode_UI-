# Scrolling architecture: RAD Debugger and the `rad` branch

This guide follows the current RAD Debugger source and compares it with this project's local `rad` branch. The branch paths below refer to files on `rad`, which you can read from the current branch with `git show rad:src/ui/layout.odin` (substitute the path you want).

## The moving parts

A scrollable region has a **viewport**: a rectangle showing part of its contents. The contents have their own size, which can be larger than the viewport. A **view offset** says how far into those contents the viewport is looking. A clip prevents content outside the viewport from being drawn.

```text
Wheel / scrollbar / programmatic change
                  │
                  ▼
           view_off_target   desired position, in content coordinates
                  │  clamp; optionally animate
                  ▼
              view_off       current position
                  │  subtract from child positions during layout
                  ▼
           shifted children ──► clip to viewport ──► draw
                  ▲
       layout measures view_bounds
```

In RAD Debugger these three two-dimensional fields live on [`UI_Box`](https://github.com/EpicGames/raddebugger/blob/master/src/ui/ui_core.h#L423):

| Field | Role |
|---|---|
| `view_bounds` | Extent measured from the box's children during layout. |
| `view_off_target` | Desired offset, changed by scrolling or other code. |
| `view_off` | Current offset used by layout; it can ease toward the target. |

The same fields appear in `rad:src/ui/ui.odin:114`. The cached box preserves them across builds (`rad:src/ui/core.odin:156`). The interface is rebuilt each frame, but a stable box identity lets its scroll state survive.

## What happens when you scroll

1. **Measure the content.** During layout, RAD Debugger adds up normal child sizes along the layout axis and takes the maximum size across the other axis. Floating children do not contribute in that pass. It records the result in `view_bounds`. See [the layout pass](https://github.com/EpicGames/raddebugger/blob/master/src/ui/ui_core.c#L1851). The branch follows the same approach in `rad:src/ui/layout.odin:135`.
2. **Update the target.** A scroll event can change the target offset on enabled axes. RAD Debugger's [event handling](https://github.com/EpicGames/raddebugger/blob/master/src/ui/ui_core.c#L2950) handles axis flags and modifier behavior; the branch handles events in `rad:src/ui/core.odin:297`.
3. **Clamp and animate.** Where view clamping is enabled, the maximum offset on an axis is `max(0, content extent − viewport extent)`. RAD Debugger clamps the target and moves the current offset towards it ([source](https://github.com/EpicGames/raddebugger/blob/master/src/ui/ui_core.c#L1454)). The branch does the same in `clamp_view` and its end-of-build animation pass (`rad:src/ui/core.odin:342` and `:615`).
4. **Position children.** Layout subtracts the parent's current offset from child positions. Moving the view down therefore makes the content appear to move up. Both implementations have per-axis flags that let a child skip this subtraction. See [RAD Debugger's positioning](https://github.com/EpicGames/raddebugger/blob/master/src/ui/ui_core.c#L1877) and `rad:src/ui/layout.odin:163`.
5. **Clip.** The view's clip limits which parts of the shifted children are visible. The branch propagates intersections of clipping ancestors in `rad:src/ui/layout.odin:172`.

For a 100-pixel viewport with 300 pixels of content, the offset ranges from 0 to 200. At offset 200, the final 100 pixels are visible. If the content is only 80 pixels tall, the maximum becomes 0.

**Frame timing matters.** In the branch, input and scrollbar construction use cached box geometry from an earlier layout; animation and new layout happen at the end of the build. On first appearance, resize, or content changes, bounds and scrollbar visibility can therefore settle across frames. See `rad:src/ui/popups.odin:369` and `rad:src/ui/core.odin:615`. Think about what happens when content shrinks while the offset is near the old maximum.

## The scrollbar in the `rad` branch

The branch's `scroll_region` builds an outer container, a row, and a clipped view box. The user content goes inside the view; vertical and horizontal bars are built outside the view, so they do not move with its contents. See `rad:src/ui/popups.odin:335`.

Its `scroll_bar` (`rad:src/ui/popups.odin:382`) translates between content and track coordinates:

- **Thumb size:** proportional to visible size divided by content size, with a minimum size.
- **Thumb position:** proportional to the current offset divided by the maximum offset, across the track length remaining after subtracting the thumb length.
- **Dragging:** converts pointer movement along the track into a content offset. It sets both the target and current offset, so the thumb follows the drag directly.
- **Track click:** moves the target by roughly one viewport length. Normal animation can then move the current offset toward it.
- **Visibility:** a bar is created when the cached content extent exceeds the cached viewport extent on that axis.

## Differences from RAD Debugger

The common box-level model does **not** mean the higher-level widgets are identical:

| Topic | RAD Debugger | Local `rad` branch |
|---|---|---|
| Clamping | Controlled by view-clamp flags, including per-axis flags. | `clamp_view` clamps both axes; its end-of-build call is gated by view-scroll flags. |
| Scrollbars | Its [`ui_scroll_bar`](https://github.com/EpicGames/raddebugger/blob/master/src/ui/ui_basic_widgets.c#L1258) takes and returns a `UI_ScrollPt` and operates on an **index range**. Its scroll-list helper combines that with a view box. | The region's bar directly controls the view box's pixel offset and derives thumb geometry from measured content and viewport sizes. |
| Large lists | The [scroll-list helper](https://github.com/EpicGames/raddebugger/blob/master/src/ui/ui_basic_widgets.c#L1500) works with row indices and a fractional offset, suitable for constructing a visible portion of a list. | `scroll_region` measures the children built inside its view; it is not the same indexed scroll-list abstraction. |
| Thumb drag | Behavior depends on the indexed `UI_ScrollPt` widget and its mapping. | Dragging explicitly synchronizes `view_off` and `view_off_target`; track clicks change the target. |

RAD Debugger has several scrolling uses, so the indexed scroll list is an example of its higher-level architecture, not a claim that every RAD Debugger scrollable box uses that widget.

## Questions to trace in the source

1. What would happen to the child's screen position if the layout added the view offset instead of subtracting it?
2. Why does the scrollbar map over **track length minus thumb length** rather than the whole track length?
3. Which values are from the previous layout when a scrollbar is first built, and how does that affect a region whose contents change size?
4. If a floating child does not contribute to `view_bounds`, what does that imply for content that must be reachable by scrolling?

Useful branch test: `rad:src/ui/ui_test.odin:139` checks a 300-pixel content extent and a clamped target of 200 pixels.
