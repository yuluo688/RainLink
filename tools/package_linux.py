"""Verify and package a relocatable Linux x64 release, without publishing it."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import tarfile
import tempfile
import zipfile

from package_common import app_version, digest


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = "rainlink-bundle.json"
ICON = "data/icons/hicolor/512x512/apps/dev.rainlink.rainlink.png"
DESKTOP = "dev.rainlink.rainlink.desktop"
EXECUTABLES = {"rainlink", "rainlink-host", "sing-box", "rainlink-kde-proxy"}
REQUIRED = {
    "rainlink", "rainlink-host", "rainlink-kde-proxy", "sing-box", "sing-box-source.zip",
    "sing-box-LICENSE.txt", "lib/libflutter_linux_gtk.so", "lib/libapp.so",
    "data/icudtl.dat", "data/flutter_assets/AssetManifest.bin",
    "data/flutter_assets/FontManifest.json", ICON, DESKTOP,
}
MAX_FILES = 4096
MAX_EXPANDED_BYTES = 1024**3
MAX_ARCHIVE_BYTES = 300 * 1024**2


def release_files(release: Path) -> list[Path]:
    if release.is_symlink() or not release.is_dir():
        raise ValueError("Release must be a real directory")
    files = []
    roots = EXECUTABLES | {"sing-box-source.zip", "sing-box-LICENSE.txt", DESKTOP}
    for path in sorted(release.rglob("*")):
        if path.is_symlink():
            raise ValueError("Release contains a linked path")
        if path.is_dir():
            if path.relative_to(release).parts[0] not in {"data", "lib"}:
                raise ValueError("Unexpected release directory")
            continue
        if not path.is_file():
            raise ValueError("Release contains a special file")
        name = path.relative_to(release).as_posix()
        if name == MANIFEST:
            continue
        if path.suffix.lower() in {".sqlite", ".sqlite3", ".db", ".key", ".pem", ".jks", ".p12"}:
            raise ValueError("Release includes local data or credentials")
        if "/" not in name and name not in roots:
            raise ValueError(f"Unexpected release root: {name}")
        if "/" in name and not name.startswith(("data/", "lib/")):
            raise ValueError(f"Unexpected release directory: {name}")
        files.append(path)
    if not REQUIRED <= {p.relative_to(release).as_posix() for p in files}:
        raise ValueError("Incomplete Linux release runtime")
    if len(files) > MAX_FILES or sum(p.stat().st_size for p in files) > MAX_EXPANDED_BYTES:
        raise ValueError("Expanded release exceeds distribution limits")
    return files


def verify_elf(path: Path) -> None:
    with path.open("rb") as stream:
        header = stream.read(20)
    if (len(header) != 20 or header[:6] != b"\x7fELF\x02\x01"
            or int.from_bytes(header[16:18], "little") not in (2, 3)
            or int.from_bytes(header[18:20], "little") != 62):
        raise ValueError(f"Expected a Linux x64 ELF binary: {path.name}")


def verify_runtime(release: Path, flutter_root: Path) -> dict:
    files = release_files(release)
    lock = json.loads((ROOT / "tools/core.lock.json").read_text(encoding="utf-8"))
    core = lock["additionalPlatforms"]["linux-amd64"]
    native = ROOT / "build/host/linux-amd64"
    sdk_engine = flutter_root / "bin/cache/artifacts/engine/linux-x64-release/libflutter_linux_gtk.so"
    if digest(release / "sing-box") != core["binarySha256"]:
        raise ValueError("Release core differs from the locked Linux binary")
    if digest(release / "lib/libflutter_linux_gtk.so") != digest(sdk_engine):
        raise ValueError("Release engine differs from the SDK release engine")
    for name in EXECUTABLES - {"rainlink"}:
        if (release / name).exists() and digest(release / name) != digest(native / name):
            raise ValueError(f"Release {name} differs from the current native build")
    for name in ("sing-box-source.zip", "sing-box-LICENSE.txt"):
        if digest(release / name) != digest(native / name):
            raise ValueError(f"Release {name} differs from the core build")
    with zipfile.ZipFile(release / "sing-box-source.zip") as source:
        if not source.namelist() or source.testzip() is not None:
            raise ValueError("Core source archive failed verification")
    artwork = {
        ICON: ROOT / "app/linux/runner/resources/rainlink.png",
        DESKTOP: ROOT / "app/linux/packaging" / DESKTOP,
    }
    for folder in ("icons", "flags", "brand", "fonts", "licenses"):
        for path in (ROOT / "app/assets" / folder).rglob("*"):
            if path.is_file():
                artwork["data/flutter_assets/assets/" + folder + "/" + path.relative_to(ROOT / "app/assets" / folder).as_posix()] = path
    for name, source in artwork.items():
        if not (release / name).is_file() or digest(release / name) != digest(source):
            raise ValueError(f"Missing or stale packaged asset: {name}")
    for path in files:
        if path.name in EXECUTABLES or path.name.endswith(".so"):
            verify_elf(path)
            if path.name in EXECUTABLES and not os.access(path, os.X_OK):
                raise ValueError(f"Executable permission is missing: {path.name}")
    return {
        "coreVersion": core["version"], "coreSha256": digest(release / "sing-box"),
        "hostSha256": digest(release / "rainlink-host"),
        "applicationSha256": digest(release / "rainlink"),
        "aotSha256": digest(release / "lib/libapp.so"),
        "engineSha256": digest(release / "lib/libflutter_linux_gtk.so"),
        "releaseEngineVerified": True, "packagedAssetsVerified": len(artwork),
        "kdeHelperIncluded": (release / "rainlink-kde-proxy").is_file(),
    }


def package(release: Path, flutter_root: Path, output: Path | None = None) -> dict:
    # Validate everything before writing a manifest or opening an output file.
    runtime = verify_runtime(release, flutter_root)
    files = release_files(release)
    version = app_version(ROOT)
    manifest = {
        "schema": 1, "product": "RainLink", "platform": "linux-x64", "version": version,
        "files": [{
            "path": p.relative_to(release).as_posix(), "bytes": p.stat().st_size,
            "sha256": digest(p),
            "mode": "0755" if p.name in EXECUTABLES else "0644",
        } for p in files],
    }
    if output is not None:
        if output.is_symlink() or output.resolve().is_relative_to(release.resolve()):
            raise ValueError("Archive output must be outside the release")
        if not output.name.endswith(".tar.xz"):
            raise ValueError("Linux archive must use .tar.xz")
    manifest_path = release / MANIFEST
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    result = {"version": version, "manifest": str(manifest_path), "entries": len(files) + 1, **runtime}
    if output is None:
        return result
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".tar.xz", delete=False) as stream:
            temporary = Path(stream.name)
        with tarfile.open(temporary, "w:xz", preset=6) as archive:
            for path in [*files, manifest_path]:
                info = archive.gettarinfo(str(path), "RainLink/" + path.relative_to(release).as_posix())
                info.uid = info.gid = info.mtime = 0
                info.uname = info.gname = ""
                info.mode = 0o755 if path.name in EXECUTABLES else 0o644
                with path.open("rb") as stream:
                    archive.addfile(info, stream)
        with tarfile.open(temporary, "r:xz") as archive:
            members = archive.getmembers()
            expected = {"RainLink/" + item["path"] for item in manifest["files"]} | {"RainLink/" + MANIFEST}
            if len(members) != len(expected) or {m.name for m in members} != expected:
                raise ValueError("Packaged file list differs")
            for item in manifest["files"]:
                member = archive.getmember("RainLink/" + item["path"])
                with archive.extractfile(member) as stream:
                    value = hashlib.sha256()
                    for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                        value.update(chunk)
                if value.hexdigest() != item["sha256"] or member.mode != int(item["mode"], 8):
                    raise ValueError("Packaged bytes or permissions differ")
        if temporary.stat().st_size > MAX_ARCHIVE_BYTES:
            raise ValueError("Compressed release exceeds distribution limits")
        temporary.replace(output)
        return {**result, "archive": str(output), "bytes": output.stat().st_size,
                "sha256": digest(output), "perFileDigestVerified": True,
                "permissionsVerified": True, "userDatabaseIncluded": False}
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest-only", action="store_true")
    parser.add_argument("--label", default="preview")
    parser.add_argument("--flutter-root", type=Path, default=os.environ.get("FLUTTER_ROOT"))
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9-]{1,48}", args.label):
        parser.error("label must be a short lowercase slug")
    sdk = args.flutter_root
    if sdk is None and shutil.which("flutter"):
        sdk = Path(shutil.which("flutter")).resolve().parent.parent
    if sdk is None:
        parser.error("Set --flutter-root or FLUTTER_ROOT to verify the release engine")
    output = None if args.manifest_only else ROOT / f"build/RainLink-linux-x64-{args.label}.tar.xz"
    result = package(ROOT / "app/build/linux/x64/release/bundle", Path(sdk), output)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
