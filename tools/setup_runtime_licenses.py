"""Copy verified Wintun and native IPC notices into the distributable and UI."""
import hashlib
import json
from pathlib import Path
import subprocess
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parent.parent


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    lock = json.loads((ROOT / "tools/runtime-licenses.lock.json").read_text(encoding="utf-8"))
    wintun = lock["wintun"]
    archive = ROOT / ("build/wintun-" + wintun["version"] + ".zip")
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists() or sha256(archive.read_bytes()) != wintun["archiveSha256"]:
        request = urllib.request.Request(wintun["url"], headers={"User-Agent": "RainLink-build/0.1"})
        with urllib.request.urlopen(request, timeout=45) as response:
            payload = response.read(4 << 20)
        if sha256(payload) != wintun["archiveSha256"]:
            raise RuntimeError("Wintun archive checksum mismatch")
        archive.write_bytes(payload)
    with zipfile.ZipFile(archive) as bundle:
        license_bytes = bundle.read("wintun/LICENSE.txt")
        if sha256(license_bytes) != wintun["licenseSha256"] or sha256(bundle.read("wintun/bin/amd64/wintun.dll")) != wintun["amd64Sha256"]:
            raise RuntimeError("Wintun binary or license checksum mismatch")
    winio = lock["goWinio"]
    # `go list -m` reads the existing locked dependency and validates its version.
    result = subprocess.run(["go", "list", "-m", "-json", winio["module"]],
                            cwd=ROOT / "native/host", check=True, capture_output=True, text=True, timeout=30)
    module = json.loads(result.stdout)
    if module["Version"] != winio["version"] or not module.get("Dir"):
        raise RuntimeError("Native IPC dependency does not match the license lock")
    notices = {
        # Normalize the archive's CRCRLF for a readable, verbatim text notice.
        "wintun-LICENSE.txt": license_bytes.decode("utf-8").replace("\r\r\n", "\n").replace("\r\n", "\n").encode("utf-8"),
        "go-winio-LICENSE.txt": (Path(module["Dir"]) / "LICENSE").read_bytes(),
    }
    for directory in (ROOT / "build/host", ROOT / "app/assets/licenses"):
        directory.mkdir(parents=True, exist_ok=True)
        for name, content in notices.items():
            (directory / name).write_bytes(content)
    print("Verified runtime licenses: Wintun " + wintun["version"] + ", go-winio " + winio["version"])


if __name__ == "__main__":
    main()
