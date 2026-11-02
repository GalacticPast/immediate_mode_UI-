# immediate_mode_UI-

Run `./build.sh` on Linux or `build.bat` on Windows to build and then run the
headless regression tests. A failed build or test returns a nonzero exit code.
The UI uses global state, so tests run on one thread.

To run the tests without building the app:

```sh
odin test src -all-packages -define:ODIN_TEST_THREADS=1 -out:bin/ui_tests
```

These tests cover layout calculations and simulated input without creating a
window. They do not verify the appearance of rendered pixels or real platform
events. Some dropdown and input regression checks currently fail; their output
identifies the existing issues.
