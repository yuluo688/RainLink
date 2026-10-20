"""Create a complete, hash-bound installable bundle without publishing it."""
import argparse
import hashlib
import json
import os
import re
import shutil
import zipfile
from pathlib import Path

from package_common import app_version, digest

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = "rainlink-bundle.json"
REQUIRED = (
    "rainlink.exe", "rainlink-ui.exe", "rainlink-host.exe", "rainlink-updater.exe", "sing-box.exe",
    "flutter_windows.dll", "data/app.so",
    "sing-box-source.zip", "sing-box-LICENSE.txt", "wintun-LICENSE.txt", "go-winio-LICENSE.txt",
)


def verify_runtime(release, flutter_root):
    core_lock = json.loads((ROOT / "tools/core.lock.json").read_text(encoding="utf-8"))
    engine = flutter_root / "bin/cache/artifacts/engine/windows-x64-release/flutter_windows.dll"
    checks = {
        "coreSha256": digest(release / "sing-box.exe"),
        "engineSha256": digest(release / "flutter_windows.dll"),
        "hostSha256": digest(release / "rainlink-host.exe"),
        "updaterSha256": digest(release / "rainlink-updater.exe"),
        "launcherSha256": digest(release / "rainlink.exe"),
    }
    if checks["coreSha256"] != core_lock["binarySha256"]:
        raise ValueError("Release core differs from the locked binary")
    if checks["engineSha256"] != digest(engine):
        raise ValueError("Release engine differs from the SDK release engine")
    for name, key in (("rainlink-host.exe", "hostSha256"),
                      ("rainlink-updater.exe", "updaterSha256"),
                      ("rainlink.exe", "launcherSha256")):
        if checks[key] != digest(ROOT / "build/host" / name):
            raise ValueError(f"Release {name} differs from the current native build")
    checks.update({"releaseEngineVerified": True, "coreVersion": core_lock["version"],
                   "applicationSha256": digest(release / "rainlink-ui.exe"),
                   "aotSha256": digest(release / "data/app.so")})
    return checks


def package(release, output=None):
    version = app_version(ROOT)
    files = sorted(path for path in release.rglob("*")
                   if path.is_file() and path.name != MANIFEST)
    if any(path.is_symlink() for path in release.rglob("*")):
        raise ValueError("Release contains a linked path")
    names = {path.relative_to(release).as_posix() for path in files}
    if not set(REQUIRED) <= names:
        raise ValueError("Incomplete release runtime")
    allowed_roots = {
        "rainlink.exe", "rainlink-ui.exe", "rainlink-host.exe", "rainlink-updater.exe",
        "sing-box.exe", "sing-box-source.zip", "native_assets.yaml",
    }
    for path in files:
        name = path.relative_to(release).as_posix()
        if "/" in name and not name.startswith("data/"):
            raise ValueError(f"Unexpected release directory: {name}")
        if path.suffix.lower() in {".sqlite", ".db", ".key", ".pem", ".jks", ".p12"}:
            raise ValueError("Release includes local data or credentials")
        if "/" not in name and not (
            name in allowed_roots or name.endswith(".dll")
            or name.endswith("-LICENSE.txt")
        ):
            raise ValueError(f"Unexpected release root: {name}")
    manifest = {
        "schema": 2, "product": "RainLink", "platform": "windows-x64",
        "version": version,
        "files": [
            {"path": path.relative_to(release).as_posix(),
             "bytes": path.stat().st_size, "sha256": digest(path)}
            for path in files
        ],
    }
    if len(files) > 4096 or sum(file["bytes"] for file in manifest["files"]) > 1024**3:
        raise ValueError("Expanded release exceeds updater limits")
    manifest_path = release / MANIFEST
    manifest_text = json.dumps(manifest, indent=2) + "\n"
    if not manifest_path.exists() or manifest_path.read_text(encoding="utf-8") != manifest_text:
        manifest_path.write_text(manifest_text, encoding="utf-8")
    if output is None:
        return {"version": version, "manifest": str(manifest_path), "entries": len(files) + 1}
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in [*files, manifest_path]:
            archive.write(path, path.relative_to(release).as_posix())
    with zipfile.ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("ZIP CRC verification failed")
        for file in manifest["files"]:
            if hashlib.sha256(archive.read(file["path"])).hexdigest() != file["sha256"]:
                raise ValueError("Packaged file digest differs")
    if output.stat().st_size > 300 * 1024**2:
        raise ValueError("Compressed release exceeds updater limit")
    return {
        "version": version, "archive": output.relative_to(ROOT).as_posix(),
        "entries": len(files) + 1, "bytes": output.stat().st_size,
        "sha256": digest(output), "zipCrcVerified": True,
        "perFileDigestVerified": True, "userDatabaseIncluded": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest-only", action="store_true")
    parser.add_argument("--label", default="updates-preview")
    parser.add_argument("--release-asset", action="store_true")
    parser.add_argument("--flutter-root", type=Path,
                        default=os.environ.get("FLUTTER_ROOT"))
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9-]{1,48}", args.label):
        parser.error("label must be a short lowercase slug")
    release = ROOT / "app/build/windows/x64/runner/Release"
    flutter_root = args.flutter_root
    if flutter_root is None:
        flutter = shutil.which("flutter")
        if flutter:
            flutter_root = Path(flutter).resolve().parent.parent
    if flutter_root is None:
        parser.error("Set --flutter-root or FLUTTER_ROOT to verify the release engine")
    runtime = verify_runtime(release, Path(flutter_root))
    version = app_version(ROOT)
    output = None if args.manifest_only else ROOT / (
        f"build/RainLink-{version}-windows-x64.zip" if args.release_asset
        else f"build/RainLink-windows-x64-{args.label}.zip"
    )
    result = package(release, output)
    result.update(runtime)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
