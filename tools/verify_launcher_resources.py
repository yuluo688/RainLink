"""Verify the standalone launcher identity and original ICO payloads on Windows."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile

from embed_launcher_resources import MARKER, launcher_version, read_resources
from package_windows import digest

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "app/build/windows/x64/runner/Release"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", default="docs/verification/app-update-recovery/launcher-evidence.json",
                        help="Report path relative to the repository, or an absolute path")
    args = parser.parse_args()
    launcher = RELEASE / "rainlink.exe"
    ui = RELEASE / "rainlink-ui.exe"
    resources = read_resources(launcher)
    icons = {key: value for key, value in resources.items() if key[0] in (3, 14)}
    assert icons == read_resources(ui, (3, 14)), "Launcher differs from the original UI icon"
    assert resources[(10, 301, 0x409)] == MARKER
    assert resources[(16, 1, 0x409)] == launcher_version()
    ico = (ROOT / "app/windows/runner/resources/app_icon.ico").read_bytes()
    reserved, kind, count = struct.unpack_from("<HHH", ico)
    assert reserved == 0 and kind == 1 and count == 9
    source_hashes = []
    for index in range(count):
        size, offset = struct.unpack_from("<II", ico, 6 + index * 16 + 8)
        assert size > 0 and offset >= 6 + count * 16 and offset + size <= len(ico)
        source_hashes.append(hashlib.sha256(ico[offset:offset + size]).hexdigest())
    embedded_hashes = [hashlib.sha256(data).hexdigest() for key, data in icons.items() if key[0] == 3]
    assert sorted(source_hashes) == sorted(embedded_hashes), "Compiled icon image payloads differ"
    with tempfile.TemporaryDirectory(prefix="rainlink-standalone-", dir=ROOT / "build") as name:
        copied = Path(name) / "rainlink.exe"
        shutil.copy2(launcher, copied)
        result = subprocess.run([str(copied), "--repair"], capture_output=True,
                                timeout=15, creationflags=subprocess.CREATE_NO_WINDOW)
        assert result.returncode == 0, "Launcher cannot run without Flutter DLLs"
        assert json.loads(result.stdout)["recovered"] is False
        assert sorted(path.name for path in Path(name).iterdir()) == ["rainlink.exe"]
    report = {"launcherSha256": digest(launcher), "uiSha256": digest(ui),
              "bootstrapVersion": "1.0.0.0", "schema": 2,
              "nativeIconImages": count, "figmaIcoPayloadsIdentical": True,
              "launcherAndUiIconResourcesIdentical": True,
              "explicitBootstrapIdentityVerified": True,
              "standaloneWithoutFlutterDll": True, "startupWritesNoLockFile": True}
    destination = ROOT / args.output
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
