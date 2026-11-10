# immediate_mode_UI

Run `./build.sh` on Linux or `build.bat` on Windows, then run the app from
the project root with `./bin/app` or `bin\app.exe`.

The app includes visual checks for layout and input. Open each dropdown and
click its item where it overlaps the button underneath. The status shows which
button received the click; repeat for both build orders. Try hovering, holding,
right-clicking, and dragging into the buttons. Move the pointer over a button
and press Space to send a left press and release in the same frame. The colored
layout examples show horizontal and vertical stacking and parent percentages.

Press `C` to open the clipping checks, and press `C` again to return. Each
example has a green button that extends into a red area outside a clipping
ancestor. Hover and click the green portion: it should turn yellow and report
the target. Press `R` to reset the result, then hover and click within the red
area at the same height: the target should neither turn yellow nor register a
click. The examples cover a floating child, a normal row overflowing its parent,
and a child clipped by its grandparent. A failure may show up as the green
portion turning yellow or the click result changing while the pointer is red.

These are manual checks: they do not automatically assert results, expose
private UI state such as box identity or event-list cleanup, or guarantee
pixel-perfect geometry. The existing dropdown and input bugs may be visible.
