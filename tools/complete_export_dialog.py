"""Complete only a native Save dialog owned by the requested test process."""

import argparse
import ctypes
from ctypes import wintypes
from pathlib import Path
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pid', required=True, type=int)
    parser.add_argument('--path', required=True)
    args = parser.parse_args()
    target = Path(args.path).resolve()
    intended = (Path(__file__).resolve().parents[1] / 'docs' / 'verification').resolve()
    try:
        target.relative_to(intended)
    except ValueError:
        raise RuntimeError('Expected a path under docs/verification')
    if target.suffix.lower() not in ('.csv', '.yaml', '.json') or target.exists():
        raise RuntimeError('Expected a new CSV/YAML/JSON under docs/verification')
    target.parent.mkdir(parents=True, exist_ok=True)
    user = ctypes.WinDLL('user32', use_last_error=True)
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user.IsWindowVisible.argtypes = [wintypes.HWND]
    user.GetWindowRect.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.RECT)]
    user.SendMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    user.SendMessageW.restype = wintypes.LPARAM
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    def class_name(handle):
        buffer = ctypes.create_unicode_buffer(256)
        user.GetClassNameW(handle, buffer, len(buffer))
        return buffer.value

    for _ in range(200):
        dialogs = []

        @callback_type
        def collect(handle, _):
            owner = wintypes.DWORD()
            user.GetWindowThreadProcessId(handle, ctypes.byref(owner))
            if owner.value == args.pid and user.IsWindowVisible(handle) and class_name(handle) == '#32770':
                dialogs.append(handle)
            return True

        user.EnumWindows(collect, 0)
        for dialog in dialogs:
            edits = []

            @callback_type
            def children(handle, _):
                if class_name(handle) == 'Edit' and user.IsWindowVisible(handle):
                    rectangle = wintypes.RECT()
                    user.GetWindowRect(handle, ctypes.byref(rectangle))
                    edits.append((rectangle.top, handle))
                return True

            user.EnumChildWindows(dialog, children, 0)
            if not edits:
                continue
            # The filename editor is below the search/address editors.
            _, editor = max(edits)
            value = ctypes.create_unicode_buffer(str(target))
            user.SendMessageW(editor, 0x000C, 0, ctypes.cast(value, ctypes.c_void_p).value)
            user.SendMessageW(dialog, 0x0111, 1, 0)
            return
        time.sleep(0.1)
    raise RuntimeError('Test-owned Save dialog did not appear')


if __name__ == '__main__':
    main()
