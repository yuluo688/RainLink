"""Build the pinned Android libbox and RainLink bindings without desktop changes."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import struct
import subprocess
import zipfile

from setup_core import ROOT, digest, prepare_sources
from mobile_cgo_alignment import prepare_cgo


def sdk_from_properties():
    for line in (ROOT / "app/android/local.properties").read_text(encoding="utf-8").splitlines():
        if line.startswith("sdk.dir="):
            return Path(line.split("=", 1)[1].replace("\\\\", "\\").replace("\\:", ":"))
    raise RuntimeError("Android SDK is missing from android/local.properties")


def verify_elf_alignment(data):
    if data[:5] != b"\x7fELF\x02":
        raise RuntimeError("Expected a 64-bit Android ELF")
    phoff = struct.unpack_from("<Q", data, 32)[0]
    phsize, count = struct.unpack_from("<HH", data, 54)
    alignments = []
    for index in range(count):
        offset = phoff + index * phsize
        if struct.unpack_from("<I", data, offset)[0] == 1:
            file_offset, virtual = struct.unpack_from("<QQ", data, offset + 8)
            alignment = struct.unpack_from("<Q", data, offset + 48)[0]
            if alignment < 16384 or file_offset % 16384 != virtual % 16384:
                raise RuntimeError("Android core does not support 16 KB pages")
            alignments.append(alignment)
    if not alignments:
        raise RuntimeError("ELF has no loadable segments")
    return alignments


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java-home", default=os.environ.get("JAVA_HOME"))
    args = parser.parse_args()
    base = json.loads((ROOT / "tools/core.lock.json").read_text(encoding="utf-8"))
    lock = json.loads((ROOT / "tools/mobile-core.lock.json").read_text(encoding="utf-8"))
    sdk = sdk_from_properties()
    ndk = sdk / "ndk" / lock["ndkVersion"]
    if not (ndk / "source.properties").exists() or not args.java_home:
        raise RuntimeError("The pinned NDK and a Java 17 JAVA_HOME are required")
    target = ROOT / "build/mobile"
    target.mkdir(parents=True, exist_ok=True)
    tool_bin = ROOT / "build/toolchains/mobile/bin"
    tool_bin.mkdir(parents=True, exist_ok=True)
    env = os.environ.copy()
    env.update(GOTOOLCHAIN=base["goVersion"], ANDROID_HOME=str(sdk), ANDROID_NDK_HOME=str(ndk),
               JAVA_HOME=args.java_home, GOBIN=str(tool_bin))
    env["PATH"] = str(Path(args.java_home) / "bin") + os.pathsep + str(tool_bin) + os.pathsep + env["PATH"]
    cgo_tool, cgo_evidence = prepare_cgo(env, lock["cgoAlignment"], target)
    module = json.loads(subprocess.run(
        ["go", "mod", "download", "-json", "github.com/sagernet/gomobile@" + lock["gomobileVersion"]],
        env=env, check=True, capture_output=True, text=True, timeout=120).stdout)
    if module.get("Sum") != lock["gomobileSum"]:
        raise RuntimeError("gomobile source checksum mismatch")
    for tool in ("gomobile", "gobind"):
        subprocess.run(["go", "install", "github.com/sagernet/gomobile/cmd/" + tool + "@" + lock["gomobileVersion"]],
                       env=env, check=True, timeout=180)
    source, source_dir, overlay, replacements = prepare_sources(base, env)
    env["GOFLAGS"] = ('-mod=readonly -buildvcs=false "-overlay=' + str(overlay) +
                      '" "-toolexec=' + str(cgo_tool) + '"')
    aar = target / "rainlink-core.aar"
    command = [str(tool_bin / ("gomobile.exe" if os.name == "nt" else "gomobile")), "bind",
               "-target", ",".join(lock["targets"]), "-androidapi", str(lock["androidApi"]),
               "-javapkg", "dev.rainlink.core", "-libname", "rainlink", "-trimpath",
               "-tags", ",".join(lock["tags"]), "-ldflags",
               "-s -w -buildid= -checklinkname=0 -extldflags=-Wl,-z,max-page-size=16384 -X github.com/sagernet/sing-box/constant.Version=" + base["version"],
               "-o", str(aar), "./", "github.com/sagernet/sing-box/experimental/libbox"]
    subprocess.run(command, cwd=ROOT / "native/mobile", env=env, check=True, timeout=1800)
    native = {}
    with zipfile.ZipFile(aar) as archive:
        for name in archive.namelist():
            if name.endswith(".so"):
                raw = archive.read(name)
                native[name] = {"sha256": digest(raw), "loadAlignments": verify_elf_alignment(raw)}
    if len(native) != len(lock["targets"]):
        raise RuntimeError("Android AAR is missing a requested ABI")
    libraries = ROOT / "app/android/app/libs"
    libraries.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(aar, libraries / aar.name)
    assets = ROOT / "app/android/app/src/main/assets/licenses"
    assets.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source_dir / "LICENSE", assets / "sing-box.txt")
    # Preserve the corresponding reviewed core source for local distribution.
    with zipfile.ZipFile(target / "sing-box-source.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for item in sorted(source_dir.rglob("*")):
            if item.is_file():
                archive.write(replacements.get(str(item), item), str(item.relative_to(source_dir)))
        for original, modified in replacements.items():
            if not Path(original).exists():
                archive.write(modified, str(Path(original).relative_to(source_dir)))
    evidence = {"coreVersion": base["version"], "sourceSum": source["Sum"], "toolchain": base["goVersion"],
                "recipe": lock, "cgo": cgo_evidence, "aarSha256": digest(aar.read_bytes()), "libraries": native}
    (target / "core-build.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(evidence, indent=2))


if __name__ == "__main__":
    main()
