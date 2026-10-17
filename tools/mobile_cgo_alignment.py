"""Build a source-verified cgo generator with pointer-aligned export frames."""
import json
import os
from pathlib import Path
import subprocess

from setup_core import ROOT, digest, replace_once


def patched_source(raw, expected):
    if digest(raw) != expected:
        raise RuntimeError("Pinned cgo source checksum mismatch")
    source = raw.decode("utf-8")
    # A packed C local has alignment 1. Go's generated return assignments can
    # execute pointer write barriers, requiring the frame itself to be aligned.
    # Keep every field offset intact and strengthen only the local's alignment.
    original = r'fmt.Fprintf(fgcc, "\t_cgo_argtype _cgo_a = _cgo_zero;\n")'
    replacement = r'fmt.Fprintf(fgcc, "\t_cgo_argtype _cgo_a __attribute__((__aligned__(%d))) = _cgo_zero;\n", p.PtrSize)'
    return replace_once(source, original, replacement).encode("utf-8")


def prepare_cgo(env, lock, target):
    goroot = Path(subprocess.run(["go", "env", "GOROOT"], env=env, check=True,
                                capture_output=True, text=True, timeout=30).stdout.strip())
    original = goroot / lock["source"]
    raw = original.read_bytes()
    patched = patched_source(raw, lock["sourceSha256"])
    directory = target / "cgo"
    directory.mkdir(parents=True, exist_ok=True)
    modified = directory / "out.go"
    modified.write_bytes(patched)
    overlay = directory / "overlay.json"
    overlay.write_text(json.dumps({"Replace": {str(original): str(modified)}}), encoding="utf-8")
    suffix = ".exe" if os.name == "nt" else ""
    compiler = directory / ("cgo" + suffix)
    wrapper = directory / ("mobile-cgo-tool" + suffix)
    wrapper_source = ROOT / "tools/mobile_cgo_tool/main.go"
    recipe = {"toolchain": subprocess.run(["go", "env", "GOVERSION"], env=env,
                                         check=True, capture_output=True, text=True, timeout=30).stdout.strip(),
              "sourceSha256": digest(raw), "patchedSourceSha256": digest(patched),
              "wrapperSourceSha256": digest(wrapper_source.read_bytes())}
    marker = directory / "build.json"
    previous = json.loads(marker.read_text(encoding="utf-8")) if marker.exists() else {}
    if (not compiler.exists() or not wrapper.exists() or previous.get("recipe") != recipe
            or previous.get("compilerSha256") != digest(compiler.read_bytes())
            or previous.get("wrapperSha256") != digest(wrapper.read_bytes())):
        clean = env.copy()
        clean.pop("GOFLAGS", None)
        subprocess.run(["go", "build", "-trimpath", "-buildvcs=false", "-overlay", str(overlay),
                        "-o", str(compiler), "cmd/cgo"], env=clean, check=True, timeout=300)
        subprocess.run(["go", "build", "-trimpath", "-buildvcs=false", "-o", str(wrapper),
                        str(wrapper_source)], env=clean, check=True, timeout=120)
        previous = {"recipe": recipe, "compilerSha256": digest(compiler.read_bytes()),
                    "wrapperSha256": digest(wrapper.read_bytes())}
        marker.write_text(json.dumps(previous, indent=2) + "\n", encoding="utf-8")
    return wrapper, previous
