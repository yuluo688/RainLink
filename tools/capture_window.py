"""Capture the client area of a visible RainLink verification process."""
import argparse
import ctypes
from ctypes import wintypes
from pathlib import Path
import time
from PIL import ImageGrab


def capture(pid, output, activate=True):
    user = ctypes.WinDLL("user32", use_last_error=True)
    user.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user.IsWindowVisible.argtypes = [wintypes.HWND]
    user.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
    user.SetForegroundWindow.argtypes = [wintypes.HWND]
    user.ShowWindow.argtypes = [wintypes.HWND, ctypes.c_int]
    user.SetWindowPos.argtypes = [wintypes.HWND, wintypes.HWND, ctypes.c_int,
                                  ctypes.c_int, ctypes.c_int, ctypes.c_int, wintypes.UINT]
    callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
    matches = []

    @callback
    def collect(handle, unused):
        process = wintypes.DWORD()
        user.GetWindowThreadProcessId(handle, ctypes.byref(process))
        name = ctypes.create_unicode_buffer(256)
        user.GetClassNameW(handle, name, len(name))
        if (process.value == pid and user.IsWindowVisible(handle)
                and name.value == 'FLUTTER_RUNNER_WIN32_WINDOW'):
            matches.append(handle)
        return True

    user.EnumWindows(collect, 0)
    if not matches:
        raise RuntimeError("Visible window for requested process not found")
    handle = matches[0]
    if activate:
        user.ShowWindow(handle, 9)
        user.SetWindowPos(handle, wintypes.HWND(-1), 0, 0, 0, 0, 3)
        user.SetForegroundWindow(handle)
    try:
        time.sleep(0.3)
        rect = wintypes.RECT()
        origin = wintypes.POINT()
        if not user.GetClientRect(handle, ctypes.byref(rect)) or not user.ClientToScreen(handle, ctypes.byref(origin)):
            raise ctypes.WinError(ctypes.get_last_error())
        bounds = (origin.x, origin.y, origin.x + rect.right, origin.y + rect.bottom)
        output.parent.mkdir(parents=True, exist_ok=True)
        ImageGrab.grab(bbox=bounds, all_screens=True).save(output)
    finally:
        if activate:
            user.SetWindowPos(handle, wintypes.HWND(-2), 0, 0, 0, 0, 3)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--no-activate", action="store_true")
    options = parser.parse_args()
    capture(options.pid, options.output, activate=not options.no_activate)
