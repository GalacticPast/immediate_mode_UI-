# immediate_mode_UI

Run `./build.sh` on Linux or `build.bat` on Windows, then run the app from
the project root with `./bin/app` or `bin\app.exe`.

The app includes visual checks for layout and input. Open each dropdown and
click its item where it overlaps the button underneath. The status shows which
button received the click; repeat for both build orders. Try hovering, holding,
right-clicking, and dragging into the buttons. Move the pointer over a button
and press Space to send a left press and release in the same frame. The colored
layout examples show horizontal and vertical stacking and parent percentages.

These are manual checks: they do not automatically assert results, expose
private UI state such as box identity or event-list cleanup, or guarantee
pixel-perfect geometry. The existing dropdown and input bugs may be visible.
