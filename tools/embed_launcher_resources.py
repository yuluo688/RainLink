"""Keep the standalone recovery entry's Figma icon and stable identity.

The bootstrap has its own version. Changing its bytes requires a full manual
upgrade; ordinary application releases must reuse this exact entry point.
"""
import argparse
import ctypes
from ctypes import wintypes
from pathlib import Path
import struct

MARKER = b"RainLink.Bootstrap.Schema2\0"


def kernel_api():
    api = ctypes.WinDLL("kernel32", use_last_error=True)
    api.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    api.LoadLibraryExW.restype = wintypes.HMODULE
    api.FreeLibrary.argtypes = [wintypes.HMODULE]
    api.FindResourceExW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p, wintypes.WORD]
    api.FindResourceExW.restype = wintypes.HANDLE
    api.LoadResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
    api.LoadResource.restype = wintypes.HANDLE
    api.LockResource.argtypes = [wintypes.HANDLE]
    api.LockResource.restype = ctypes.c_void_p
    api.SizeofResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
    api.SizeofResource.restype = wintypes.DWORD
    api.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    api.BeginUpdateResourceW.restype = wintypes.HANDLE
    api.UpdateResourceW.argtypes = [wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
                                    wintypes.WORD, ctypes.c_void_p, wintypes.DWORD]
    api.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    return api


def read_resources(executable, kinds=(3, 14, 16, 10)):
    api = kernel_api()
    module = api.LoadLibraryExW(str(Path(executable).resolve()), None, 0x22)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())
    result = {}
    failures = []
    name_callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE,
                                            ctypes.c_void_p, ctypes.c_void_p, ctypes.c_ssize_t)
    language_callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HMODULE,
                                                ctypes.c_void_p, ctypes.c_void_p,
                                                wintypes.WORD, ctypes.c_ssize_t)
    api.EnumResourceNamesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p,
                                       name_callback_type, ctypes.c_ssize_t]
    api.EnumResourceLanguagesW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p,
                                           language_callback_type, ctypes.c_ssize_t]

    def languages(module, kind, name, language, _):
        if name is None or name > 65535:
            failures.append("Only numbered bootstrap resources are supported")
            return False
        resource = api.FindResourceExW(module, kind, name, language)
        size = api.SizeofResource(module, resource)
        loaded = api.LoadResource(module, resource)
        pointer = api.LockResource(loaded)
        if not pointer or not size or size > 1024**2 or len(result) >= 256:
            failures.append("Invalid bootstrap resource")
            return False
        result[(kind, name, language)] = ctypes.string_at(pointer, size)
        return True

    language_callback = language_callback_type(languages)

    def names(module, kind, name, _):
        if not api.EnumResourceLanguagesW(module, kind, name, language_callback, 0):
            failures.append("Cannot enumerate bootstrap resource languages")
            return False
        return True

    name_callback = name_callback_type(names)
    try:
        for kind in kinds:
            if not api.EnumResourceNamesW(module, kind, name_callback, 0):
                error = ctypes.get_last_error()
                if error not in (1812, 1813, 1814):
                    raise ctypes.WinError(error)
        if failures:
            raise ValueError(failures[0])
        return result
    finally:
        api.FreeLibrary(module)


def write_resources(executable, resources):
    api = kernel_api()
    handle = api.BeginUpdateResourceW(str(Path(executable).resolve()), False)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        for (kind, name, language), data in resources.items():
            buffer = ctypes.create_string_buffer(data)
            if not api.UpdateResourceW(handle, kind, name, language, buffer, len(data)):
                raise ctypes.WinError(ctypes.get_last_error())
    except BaseException:
        api.EndUpdateResourceW(handle, True)
        raise
    if not api.EndUpdateResourceW(handle, False):
        raise ctypes.WinError(ctypes.get_last_error())


def version_block(key, value=b"", children=(), text=False):
    content = bytearray(b"\0" * 6 + (key + "\0").encode("utf-16-le"))
    content.extend(b"\0" * (-len(content) % 4))
    content.extend(value)
    for child in children:
        content.extend(b"\0" * (-len(content) % 4))
        content.extend(child)
    struct.pack_into("<HHH", content, 0, len(content), len(value) // (2 if text else 1), int(text))
    return bytes(content)


def launcher_version():
    strings = {
        "CompanyName": "dev.rainlink", "FileDescription": "RainLink Launcher",
        "FileVersion": "1.0.0.0", "InternalName": "rainlink-launcher",
        "LegalCopyright": "Copyright (C) 2026 dev.rainlink. All rights reserved.",
        "OriginalFilename": "rainlink.exe", "ProductName": "RainLink",
        "ProductVersion": "1.0.0.0",
    }
    values = [version_block(key, (value + "\0").encode("utf-16-le"), text=True)
              for key, value in strings.items()]
    fixed = struct.pack("<13I", 0xFEEF04BD, 0x10000, 0x10000, 0, 0x10000, 0,
                        0x3F, 0, 0x40004, 1, 0, 0, 0)
    return version_block("VS_VERSION_INFO", fixed, [
        version_block("StringFileInfo", text=True, children=[version_block("040904e4", children=values, text=True)]),
        version_block("VarFileInfo", text=True, children=[version_block("Translation", struct.pack("<HH", 0x409, 1252))]),
    ])


def embed(launcher, ui):
    icons = read_resources(ui, (3, 14))
    if not any(key[0] == 3 for key in icons) or not any(key[0] == 14 for key in icons):
        raise ValueError("The Flutter UI must contain the original RainLink icon")
    expected = dict(icons)
    expected[(16, 1, 0x409)] = launcher_version()
    expected[(10, 301, 0x409)] = MARKER
    write_resources(launcher, expected)
    if read_resources(launcher) != expected:
        raise ValueError("Embedded launcher resources differ from the source icon or identity")
    return {"iconResources": len(icons), "figmaUiIconBytesIdentical": True,
            "bootstrapVersion": "1.0.0.0", "schema": 2}


def main():
    import json
    parser = argparse.ArgumentParser()
    parser.add_argument("--launcher", type=Path, required=True)
    parser.add_argument("--ui", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(embed(args.launcher, args.ui), indent=2))


if __name__ == "__main__":
    main()
