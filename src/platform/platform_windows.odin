package platform

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:reflect"
import win "core:sys/windows"
import "core:time"
import gl "vendor:OpenGL"

platform_windows_state :: struct {
    h_instance:     win.HINSTANCE,
    hwnd:           win.HWND,
    hdc:            win.HDC,
    opengl_context: win.HGLRC,

    // logical size, the framebuffer is width * display_scale by height * display_scale
    width:          i32,
    height:         i32,
    display_scale:  f32,
    deadline:       time.Tick,
}
@(private = "file")
p_w_state: platform_windows_state

@(private = "file")
WINDOW_CLASS_NAME :: "imgui_odin"
// fixed size window, same as min size == max size on wayland
@(private = "file")
WINDOW_STYLE :: win.WS_OVERLAPPEDWINDOW & ~(win.WS_THICKFRAME | win.WS_MAXIMIZEBOX)

// Windows calls this from inside PeekMessage / DispatchMessage, which only happen in dispatch(),
// so get_events has already stashed its context. CreateWindow and SetWindowPos in startup also
// send messages straight here, at that point there is no list so those events are dropped.
@(private = "file")
window_proc :: proc "system" (hwnd: win.HWND, msg: win.UINT, w_param: win.WPARAM, l_param: win.LPARAM) -> win.LRESULT {
    context = p_state.t_context != nil ? p_state.t_context^ : runtime.default_context()

    switch msg {
        case win.WM_ERASEBKGND:
            // opengl draws the whole client area, letting GDI erase it first only flickers
            return 1
        case win.WM_PAINT:
            // nothing to paint with GDI, but the region has to be validated or WM_PAINT keeps coming
            win.ValidateRect(hwnd, nil)
            return 0
        case win.WM_CLOSE:
            // DefWindowProc would destroy the window, let the app decide like on wayland
            push_window_event({type = .WINDOW_CLOSE})
            return 0
        case win.WM_DESTROY:
            win.PostQuitMessage(0)
            return 0
        case win.WM_SIZE:
            if w_param == win.SIZE_MINIMIZED {
                break
            }
            r: win.RECT
            win.GetClientRect(hwnd, &r)
            p_w_state.width = i32(f32(r.right - r.left) / p_w_state.display_scale)
            p_w_state.height = i32(f32(r.bottom - r.top) / p_w_state.display_scale)
            return 0
        case win.WM_DPICHANGED:
            // moved to a monitor with a different scale. w_param holds the new dpi and l_param a
            // suggested window rect that keeps the same logical size at that dpi
            p_w_state.display_scale = f32(win.HIWORD(w_param)) / 96.0

            suggested := cast(^win.RECT)uintptr(l_param)
            win.SetWindowPos(
                hwnd,
                nil,
                suggested.left,
                suggested.top,
                suggested.right - suggested.left,
                suggested.bottom - suggested.top,
                win.SWP_NOZORDER | win.SWP_NOACTIVATE,
            )
            // SetWindowPos sends WM_SIZE, which recomputes the logical size with the new scale
            return 0
        // still fall through to DefWindowProc, alt+f4 and the alt menu go through the SYSKEY messages
        case win.WM_KEYDOWN, win.WM_SYSKEYDOWN, win.WM_KEYUP, win.WM_SYSKEYUP:
            e: event = {
                key = translate_key_code(w_param),
            }
            if msg == win.WM_KEYUP || msg == win.WM_SYSKEYUP {
                e.type = .KEY_RELEASE
            } else {
                // bit 30 is the previous key state, already down means this is auto repeat
                was_down := (l_param & (1 << 30)) != 0
                e.type = was_down ? .KEY_REPEAT : .KEY_PRESS
            }
            push_window_event(e)
        case win.WM_MOUSEMOVE:
            push_window_event(
                {
                    type = .MOUSE_MOVE,
                    // logical pixels
                    pos  = {
                        cast(i32)math.floor(f32(win.GET_X_LPARAM(l_param)) / p_w_state.display_scale),
                        cast(i32)math.floor(f32(win.GET_Y_LPARAM(l_param)) / p_w_state.display_scale),
                    },
                },
            )
            return 0
    }

    return win.DefWindowProcW(hwnd, msg, w_param, l_param)
}

@(private = "file")
push_window_event :: proc(e: event) {
    if p_state.t_context == nil {
        return
    }
    node: ^event = new(event)
    node^ = e
    push_event(node)
}

startup :: proc(width, height: i32) -> (ok: bool) {
    p_w_state.width = width
    p_w_state.height = height
    p_w_state.display_scale = 1.0

    // without this windows bitmap stretches the window on high dpi monitors and everything is blurry
    win.SetProcessDpiAwarenessContext(win.DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)

    p_w_state.h_instance = win.HINSTANCE(win.GetModuleHandleW(nil))

    wc: win.WNDCLASSEXW = {
        cbSize        = size_of(win.WNDCLASSEXW),
        // the window keeps one DC for its whole life, the GL context is bound to it
        style         = win.CS_OWNDC,
        lpfnWndProc   = window_proc,
        hInstance     = p_w_state.h_instance,
        hIcon         = win.LoadIconA(nil, win.IDI_APPLICATION),
        hCursor       = win.LoadCursorA(nil, win.IDC_ARROW),
        // no background brush, opengl paints everything
        hbrBackground = nil,
        lpszClassName = win.L(WINDOW_CLASS_NAME),
    }
    if win.RegisterClassExW(&wc) == 0 {
        fmt.eprintln("Error: Failed to register the window class:", win.GetLastError())
        return false
    }

    p_w_state.hwnd = win.CreateWindowExW(
        0,
        win.L(WINDOW_CLASS_NAME),
        win.L("odin odin odin"),
        WINDOW_STYLE,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        win.CW_USEDEFAULT,
        nil,
        nil,
        p_w_state.h_instance,
        nil,
    )
    if p_w_state.hwnd == nil {
        fmt.eprintln("Error: Failed to create the window:", win.GetLastError())
        return false
    }

    // only now do we know which monitor the window landed on, so size the client area for its dpi
    dpi: win.UINT = win.GetDpiForWindow(p_w_state.hwnd)
    p_w_state.display_scale = f32(dpi) / 96.0

    rect: win.RECT = {
        right  = i32(f32(width) * p_w_state.display_scale),
        bottom = i32(f32(height) * p_w_state.display_scale),
    }
    win.AdjustWindowRectExForDpi(&rect, WINDOW_STYLE, false, 0, dpi)
    win.SetWindowPos(
        p_w_state.hwnd,
        nil,
        0,
        0,
        rect.right - rect.left,
        rect.bottom - rect.top,
        win.SWP_NOMOVE | win.SWP_NOZORDER | win.SWP_NOACTIVATE,
    )

    // opengl

    p_w_state.hdc = win.GetDC(p_w_state.hwnd)
    if p_w_state.hdc == nil {
        fmt.eprintln("Error: Failed to get the window DC")
        return false
    }

    pfd: win.PIXELFORMATDESCRIPTOR = {
        nSize        = size_of(win.PIXELFORMATDESCRIPTOR),
        nVersion     = 1,
        dwFlags      = win.PFD_DRAW_TO_WINDOW | win.PFD_SUPPORT_OPENGL | win.PFD_DOUBLEBUFFER,
        iPixelType   = win.PFD_TYPE_RGBA,
        cColorBits   = 32,
        cDepthBits   = 24,
        cStencilBits = 8,
        iLayerType   = win.PFD_MAIN_PLANE,
    }
    pixel_format: i32 = win.ChoosePixelFormat(p_w_state.hdc, &pfd)
    if pixel_format == 0 {
        fmt.eprintln("Error: No matching pixel format:", win.GetLastError())
        return false
    }
    // a window's pixel format can only be set once
    if !win.SetPixelFormat(p_w_state.hdc, pixel_format, &pfd) {
        fmt.eprintln("Error: Failed to set the pixel format:", win.GetLastError())
        return false
    }

    // wglCreateContextAttribsARB is an extension, and extensions can only be looked up
    // while some context is current. So make a legacy one first, just to load it.
    dummy_context: win.HGLRC = win.wglCreateContext(p_w_state.hdc)
    if dummy_context == nil {
        fmt.eprintln("Error: Failed to create the dummy OpenGL context:", win.GetLastError())
        return false
    }
    win.wglMakeCurrent(p_w_state.hdc, dummy_context)

    win.wglCreateContextAttribsARB = cast(win.CreateContextAttribsARBType)win.wglGetProcAddress(
        "wglCreateContextAttribsARB",
    )
    win.wglSwapIntervalEXT = cast(win.SwapIntervalEXTType)win.wglGetProcAddress("wglSwapIntervalEXT")

    if win.wglCreateContextAttribsARB != nil {
        context_attributes: []i32 = {
            win.WGL_CONTEXT_MAJOR_VERSION_ARB,
            4,
            win.WGL_CONTEXT_MINOR_VERSION_ARB,
            5,
            win.WGL_CONTEXT_PROFILE_MASK_ARB,
            win.WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
            0,
        }
        p_w_state.opengl_context = win.wglCreateContextAttribsARB(p_w_state.hdc, nil, raw_data(context_attributes))
    }

    win.wglMakeCurrent(nil, nil)
    win.wglDeleteContext(dummy_context)

    if p_w_state.opengl_context == nil {
        fmt.eprintln("Cannot create the OpenGL context, OpenGL 4.5 not supported?")
        return false
    }
    if !win.wglMakeCurrent(p_w_state.hdc, p_w_state.opengl_context) {
        fmt.eprintln("Failed to make context current")
        return false
    }

    // vsync, egl swaps with an interval of 1 by default too
    if win.wglSwapIntervalEXT != nil {
        win.wglSwapIntervalEXT(1)
    }

    gl.load_up_to(4, 5, win.gl_set_proc_address)

    fmt.println("Opengl initialization sucessful.")

    win.ShowWindow(p_w_state.hwnd, win.SW_SHOW)
    return true
}

dispatch :: proc() -> bool {
    defer { p_w_state.deadline = {} }

    msg: win.MSG
    // MsgWaitForMultipleObjects only wakes for messages that arrive after it is called,
    // so only sleep when the queue is already empty
    if !win.PeekMessageW(&msg, nil, 0, 0, win.PM_NOREMOVE) {
        timeout: i32 = poll_timeout_ms(p_w_state.deadline)
        wait_ms: win.DWORD = timeout < 0 ? win.INFINITE : win.DWORD(timeout)

        if win.MsgWaitForMultipleObjects(0, nil, false, wait_ms, win.QS_ALLINPUT) == win.WAIT_FAILED {
            fmt.eprintln("MsgWaitForMultipleObjects failed", win.GetLastError())
            return false
        }
    }

    for win.PeekMessageW(&msg, nil, 0, 0, win.PM_REMOVE) {
        if msg.message == win.WM_QUIT {
            // the window is gone, nothing else is coming
            push_window_event({type = .WINDOW_CLOSE})
            break
        }
        win.TranslateMessage(&msg)
        win.DispatchMessageW(&msg)
    }
    return true
}

request_deadline :: proc(deadline: time.Tick) {
    p_w_state.deadline = deadline
}

swap_buffers :: proc() {
    win.SwapBuffers(p_w_state.hdc)
}

get_display_scale :: proc() -> f32 {
    return p_w_state.display_scale
}

// physical framebuffer size
get_framebuffer_size :: proc() -> (i32, i32) {
    return cast(i32)(cast(f32)p_w_state.width * p_w_state.display_scale),
        cast(i32)(cast(f32)p_w_state.height * p_w_state.display_scale)
}

get_window_size :: proc() -> (i32, i32) {
    return p_w_state.width, p_w_state.height
}

// key_type already uses the windows virtual key codes as its values
translate_key_code :: proc(vk: win.WPARAM) -> key_type {
    k := key_type(vk)
    return reflect.enum_value_has_name(k) ? k : .NONE
}
