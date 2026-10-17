"""Send a tray activation only to the explicitly selected RainLink test process."""
import argparse
import ctypes
from ctypes import wintypes
import json
import time


class Guid(ctypes.Structure):
    _fields_ = [('data1', wintypes.DWORD), ('data2', wintypes.WORD),
                ('data3', wintypes.WORD), ('data4', ctypes.c_ubyte * 8)]


class NotifyIconIdentifier(ctypes.Structure):
    _fields_ = [('size', wintypes.DWORD), ('window', wintypes.HWND),
                ('icon_id', wintypes.UINT), ('guid', Guid)]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', type=int, required=True)
    parser.add_argument('--restore-from-tray', action='store_true')
    parser.add_argument('--assert-tray', action='store_true')
    parser.add_argument('--open-tray-menu', action='store_true')
    parser.add_argument('--activate-notification', action='store_true')
    args = parser.parse_args()
    user = ctypes.WinDLL('user32', use_last_error=True)
    user.SetProcessDpiAwarenessContext(ctypes.c_void_p(-4))
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user.IsWindowVisible.argtypes = [wintypes.HWND]
    user.GetClientRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user.ClientToScreen.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.POINT)]
    windows = []
    callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    @callback
    def collect(handle, _):
        process = wintypes.DWORD()
        user.GetWindowThreadProcessId(handle, ctypes.byref(process))
        name = ctypes.create_unicode_buffer(256)
        user.GetClassNameW(handle, name, len(name))
        if process.value == args.pid and name.value == 'FLUTTER_RUNNER_WIN32_WINDOW':
            windows.append(handle)
        return True

    user.EnumWindows(collect, 0)
    if len(windows) != 1:
        raise RuntimeError('Expected one RainLink runner window for selected PID')
    if args.assert_tray:
        shell = ctypes.WinDLL('shell32', use_last_error=True)
        shell.Shell_NotifyIconGetRect.argtypes = [ctypes.POINTER(NotifyIconIdentifier),
                                                ctypes.POINTER(wintypes.RECT)]
        shell.Shell_NotifyIconGetRect.restype = ctypes.c_long
        identifier = NotifyIconIdentifier()
        identifier.size = ctypes.sizeof(identifier)
        identifier.window = windows[0]
        identifier.icon_id = 1
        bounds = wintypes.RECT()
        if shell.Shell_NotifyIconGetRect(ctypes.byref(identifier), ctypes.byref(bounds)) != 0:
            raise RuntimeError('Shell did not confirm the RainLink tray icon')
        if bounds.right <= bounds.left or bounds.bottom <= bounds.top:
            raise RuntimeError('Shell returned invalid tray icon bounds')
    if args.restore_from_tray:
        if user.IsWindowVisible(windows[0]):
            raise RuntimeError('Window must be hidden before native tray restore')
        # Notification callback used by Shell_NotifyIcon VERSION_4 activation.
        if not user.PostMessageW(windows[0], 0x8000 + 100, 0, (1 << 16) | 0x400):
            raise ctypes.WinError(ctypes.get_last_error())
        deadline = time.monotonic() + 3
        while not user.IsWindowVisible(windows[0]) and time.monotonic() < deadline:
            time.sleep(0.05)
        if not user.IsWindowVisible(windows[0]):
            raise RuntimeError('Native tray callback did not restore the window')
    if args.open_tray_menu:
        if not user.IsWindowVisible(windows[0]):
            raise RuntimeError('Window must be visible for menu capture')
        bounds = wintypes.RECT()
        origin = wintypes.POINT()
        if not user.GetClientRect(windows[0], ctypes.byref(bounds)) or not user.ClientToScreen(windows[0], ctypes.byref(origin)):
            raise ctypes.WinError(ctypes.get_last_error())
        user.SetCursorPos(origin.x + bounds.right * 2 // 3,
                          origin.y + bounds.bottom * 2 // 3)
        if not user.PostMessageW(windows[0], 0x8000 + 100, 0, (1 << 16) | 0x7B):
            raise ctypes.WinError(ctypes.get_last_error())
        time.sleep(0.2)
    if args.activate_notification:
        # Deliberately simulate the documented Shell callback for this PID.
        # This proves routing, not display or a human click on an OS banner.
        if not user.PostMessageW(windows[0], 0x8000 + 100, 0, (1 << 16) | 0x405):
            raise ctypes.WinError(ctypes.get_last_error())
        time.sleep(0.1)
    print(json.dumps({'runnerFound': True, 'visible': bool(user.IsWindowVisible(windows[0]))}))


if __name__ == '__main__':
    main()
