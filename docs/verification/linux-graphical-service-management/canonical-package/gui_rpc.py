"""Local-only control of the explicitly identified disposable GUI VM."""
import base64
import json
from pathlib import Path
import subprocess
import sys
import time

sys.stdout.reconfigure(encoding="utf-8")

QA = Path(__file__).resolve().parent
CONTROL = "/mnt/host/c/Users/FalingFliff/Documents/ChatGPT/RainLink/build/qa/linux-manage/vm-graphical-20261020-02/qga-control.sh"


def request(value):
    (QA / "qga-request.json").write_text(json.dumps(value) + "\n", encoding="utf-8")
    result = subprocess.run(["wsl.exe", "-d", "docker-desktop", "-u", "root", "--exec", "/bin/sh", CONTROL], capture_output=True, timeout=40)
    if result.returncode:
        raise RuntimeError(result.stderr.decode("utf-8", errors="replace"))
    response = json.loads(result.stdout.decode("utf-8"))
    if "error" in response:
        raise RuntimeError(response["error"])
    return response["return"]


mode = sys.argv[1]
if mode in {"exec", "run"}:
    script = Path(sys.argv[2]).read_text(encoding="utf-8")
    result = request({"execute": "guest-exec", "arguments": {"path": "/bin/bash", "arg": ["-lc", script], "capture-output": True}})
    if mode == "run":
        pid = result["pid"]
        deadline = time.monotonic() + 25
        while time.monotonic() < deadline:
            result = request({"execute": "guest-exec-status", "arguments": {"pid": pid}})
            if result.get("exited"):
                break
            time.sleep(0.5)
        for key in ("out-data", "err-data"):
            if key in result:
                result[key] = base64.b64decode(result[key]).decode("utf-8", errors="replace")
        result["pid"] = pid
    print(json.dumps(result, ensure_ascii=False))
elif mode == "status":
    result = request({"execute": "guest-exec-status", "arguments": {"pid": int(sys.argv[2])}})
    for key in ("out-data", "err-data"):
        if key in result:
            result[key] = base64.b64decode(result[key]).decode("utf-8", errors="replace")
    print(json.dumps(result, ensure_ascii=False, indent=2))
elif mode == "write":
    source = Path(sys.argv[2])
    handle = request({"execute": "guest-file-open", "arguments": {"path": sys.argv[3], "mode": "w"}})
    try:
        with source.open("rb") as stream:
            while chunk := stream.read(256 * 1024):
                result = request({"execute": "guest-file-write", "arguments": {"handle": handle, "buf-b64": base64.b64encode(chunk).decode("ascii")}})
                if result["count"] != len(chunk):
                    raise RuntimeError("Guest file write was incomplete")
        print(json.dumps({"uploaded": str(source), "bytes": source.stat().st_size}))
    finally:
        request({"execute": "guest-file-close", "arguments": {"handle": handle}})
elif mode == "read":
    handle = request({"execute": "guest-file-open", "arguments": {"path": sys.argv[2], "mode": "r"}})
    try:
        chunks = []
        while True:
            result = request({"execute": "guest-file-read", "arguments": {"handle": handle, "count": 1024 * 1024}})
            chunks.append(base64.b64decode(result["buf-b64"]))
            if result["eof"]:
                break
        path = Path(sys.argv[3])
        path.write_bytes(b"".join(chunks))
        print(json.dumps({"saved": str(path), "bytes": path.stat().st_size}))
    finally:
        request({"execute": "guest-file-close", "arguments": {"handle": handle}})
else:
    raise SystemExit("Expected exec, status or read")
