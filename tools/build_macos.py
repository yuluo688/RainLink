"""Prepare and assemble a locally signed macOS development app.

This is not Developer ID signing, notarization or a DMG publisher. Unsigned core
bytes remain source-locked; the host pins the exact locally signed copy at build
time. The Keychain helper is only compiled here, never executed by this script.
"""

import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import shutil
import struct
import subprocess
import sys
import tempfile

from package_common import digest


ROOT = Path(__file__).resolve().parent.parent
MINIMUM_MACOS = "13.0"
CPU_TYPES = {"amd64": 0x01000007, "arm64": 0x0100000C}
IDENTIFIERS = {
    "sing-box": "dev.rainlink.rainlink.core",
    "rainlink-keychain": "dev.rainlink.rainlink.keychain",
    "rainlink-host": "dev.rainlink.rainlink.host",
}
RESOURCES = ("sing-box-source.zip", "sing-box-LICENSE.txt")


def run(arguments, *, cwd=None, env=None, timeout=300):
    return subprocess.run(
        [str(value) for value in arguments], cwd=cwd, env=env, check=True,
        capture_output=True, text=True, timeout=timeout,
    )


def require_macos():
    if platform.system() != "Darwin":
        raise ValueError("Native Swift compilation and signing require a Mac with Xcode")


def source_inputs():
    paths = [ROOT / "tools/build_macos.py", ROOT / "tools/core.lock.json",
             ROOT / "native/macos/keychain/main.swift",
             ROOT / "app/macos/Runner/Release.entitlements",
             ROOT / "native/host/go.mod", ROOT / "native/host/go.sum"]
    paths.extend(path for path in (ROOT / "native/host").rglob("*.go")
                 if not path.name.endswith("_test.go"))
    return {path.relative_to(ROOT).as_posix(): digest(path) for path in sorted(paths)}


def macho_architectures(path):
    """Read Mach-O CPU headers without executing foreign-architecture code."""
    with path.open("rb") as stream:
        header = stream.read(32)
        if len(header) < 8:
            raise ValueError("Truncated Mach-O executable: " + path.name)
        if header[:4] in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
            endian = "<" if header[:4] == b"\xcf\xfa\xed\xfe" else ">"
            if len(header) != 32 or struct.unpack(endian + "I", header[12:16])[0] != 2:
                raise ValueError("Expected a Mach-O executable: " + path.name)
            return {struct.unpack(endian + "I", header[4:8])[0]}
        if header[:4] not in (b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf"):
            raise ValueError("Expected a Mach-O executable: " + path.name)
        count = struct.unpack(">I", header[4:8])[0]
        if not 1 <= count <= 8:
            raise ValueError("Invalid universal Mach-O architecture count")
        record_size = 32 if header[:4] == b"\xca\xfe\xba\xbf" else 20
        stream.seek(8)
        records = stream.read(record_size * count)
        if len(records) != record_size * count:
            raise ValueError("Truncated universal Mach-O executable")
        return {struct.unpack_from(">I", records, index * record_size)[0]
                for index in range(count)}


def verify_architecture(path, arch):
    if CPU_TYPES[arch] not in macho_architectures(path):
        raise ValueError("Wrong Mach-O architecture: " + path.name)


def sign(path, identifier, *, entitlements=None):
    arguments = ["/usr/bin/codesign", "--force", "--sign", "-", "--timestamp=none",
                 "--identifier", identifier]
    if entitlements is not None:
        arguments.extend(["--entitlements", entitlements])
    run([*arguments, path])
    run(["/usr/bin/codesign", "--verify", "--strict", path])


def prepare_runtime(arch):
    require_macos()
    lock = json.loads((ROOT / "tools/core.lock.json").read_text(encoding="utf-8"))
    target = "darwin-" + arch
    entry = lock["additionalPlatforms"].get(target)
    if not entry:
        raise ValueError("Missing reviewed core lock for " + target)
    run([sys.executable, ROOT / "tools/setup_core.py", "--platform", target], timeout=900)
    native = ROOT / "build/host" / target
    if digest(native / "sing-box") != entry["binarySha256"]:
        raise ValueError("Unsigned core differs from its reviewed source lock")
    verify_architecture(native / "sing-box", arch)
    sdk = run(["/usr/bin/xcrun", "--sdk", "macosx", "--show-sdk-path"]).stdout.strip()
    if not sdk:
        raise ValueError("Xcode did not return a macOS SDK")
    build = ROOT / "build/macos" / arch
    runtime = build / "runtime"
    build.mkdir(parents=True, exist_ok=True)
    if build.is_symlink() or runtime.is_symlink():
        raise ValueError("The native build directory must not be a symlink")
    env = {**os.environ, "GOTOOLCHAIN": lock["goVersion"], "GOOS": "darwin",
           "GOARCH": arch, "CGO_ENABLED": "0"}
    with tempfile.TemporaryDirectory(prefix="native-", dir=build) as temporary:
        staged = Path(temporary)
        shutil.copyfile(native / "sing-box", staged / "sing-box")
        (staged / "sing-box").chmod(0o755)
        sign(staged / "sing-box", IDENTIFIERS["sing-box"])
        signed_core = digest(staged / "sing-box")
        swift_arch = "x86_64" if arch == "amd64" else "arm64"
        run(["/usr/bin/xcrun", "--sdk", "macosx", "swiftc", "-O", "-sdk", sdk,
             "-target", swift_arch + "-apple-macosx" + MINIMUM_MACOS,
             "-framework", "Security", "-framework", "Foundation",
             ROOT / "native/macos/keychain/main.swift", "-o", staged / "rainlink-keychain"])
        # Signing must precede host compilation. This variable is compiled into
        # the host, never read from a writable sidecar at runtime.
        run(["go", "build", "-trimpath", "-buildvcs=false", "-ldflags",
             "-X rainlink.local/host/internal/coreprocess.signedDarwinCoreSHA256=" + signed_core,
             "-o", staged / "rainlink-host", "./cmd/rainlink-host"],
            cwd=ROOT / "native/host", env=env, timeout=600)
        for name in ("rainlink-keychain", "rainlink-host"):
            verify_architecture(staged / name, arch)
            sign(staged / name, IDENTIFIERS[name])
        for name in RESOURCES:
            shutil.copyfile(native / name, staged / name)
        evidence = {
            "schema": 1, "platform": target, "minimumMacOS": MINIMUM_MACOS,
            "signing": "local-ad-hoc", "notarized": False,
            "unsignedCoreSha256": entry["binarySha256"],
            "signedCoreSha256": signed_core,
            "files": {name: digest(staged / name) for name in (*IDENTIFIERS, *RESOURCES)},
            "inputs": source_inputs(),
            "keychainExecuted": False,
        }
        runtime.mkdir(exist_ok=True)
        for name in (*IDENTIFIERS, *RESOURCES):
            (staged / name).replace(runtime / name)
        # A partial failure leaves no matching evidence; bundle assembly refuses it.
        evidence_path = build / "native-build.json"
        evidence_path.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    return {"host": str(runtime / "rainlink-host"), "evidence": str(evidence_path), **evidence}


def validate_runtime(arch):
    build = ROOT / "build/macos" / arch
    runtime = build / "runtime"
    evidence = json.loads((build / "native-build.json").read_text(encoding="utf-8"))
    lock = json.loads((ROOT / "tools/core.lock.json").read_text(encoding="utf-8"))
    expected_files = set(IDENTIFIERS) | set(RESOURCES)
    if (evidence.get("schema") != 1 or evidence.get("platform") != "darwin-" + arch
            or evidence.get("signing") != "local-ad-hoc"
            or evidence.get("notarized") is not False
            or evidence.get("inputs") != source_inputs()
            or evidence.get("unsignedCoreSha256") != lock["additionalPlatforms"]["darwin-" + arch]["binarySha256"]
            or set(evidence.get("files", {})) != expected_files
            or evidence.get("signedCoreSha256") != evidence["files"].get("sing-box")):
        raise ValueError("Native macOS inputs changed; prepare the runtime again")
    for name, expected in evidence["files"].items():
        if (runtime / name).is_symlink() or digest(runtime / name) != expected:
            raise ValueError("Native macOS runtime changed: " + name)
        if name in IDENTIFIERS:
            verify_architecture(runtime / name, arch)
            run(["/usr/bin/codesign", "--verify", "--strict", runtime / name])
    return runtime, evidence


def assemble_bundle(arch, app):
    require_macos()
    products = (ROOT / "app/build/macos/Build/Products").resolve()
    if app.is_symlink() or not app.resolve().is_relative_to(products) or not app.is_dir():
        raise ValueError("Only a generated Flutter macOS app may be assembled")
    runtime, evidence = validate_runtime(arch)
    contents = app / "Contents"
    info = plistlib.loads((contents / "Info.plist").read_bytes())
    if (info.get("CFBundleIdentifier") != "dev.rainlink.rainlink"
            or info.get("CFBundleExecutable") != "RainLink"
            or tuple(int(part) for part in info.get("LSMinimumSystemVersion", "0").split(".")) < (13, 0)):
        raise ValueError("Unexpected RainLink application identity or deployment target")
    verify_architecture(contents / "MacOS/RainLink", arch)
    assets = contents / "Frameworks/App.framework/Resources/flutter_assets/assets"
    asset_count = 0
    for folder in ("brand", "flags", "icons", "fonts", "licenses"):
        for source in (ROOT / "app/assets" / folder).rglob("*"):
            if source.is_file():
                target = assets / folder / source.relative_to(ROOT / "app/assets" / folder)
                if not target.is_file() or digest(target) != digest(source):
                    raise ValueError("Missing or stale packaged macOS asset: " + source.name)
                asset_count += 1
    resources = contents / "Resources/RainLinkCore"
    resources.mkdir(parents=True, exist_ok=True)
    for name in IDENTIFIERS:
        target = contents / "MacOS" / name
        shutil.copyfile(runtime / name, target)
        target.chmod(0o755)
    for name in RESOURCES:
        shutil.copyfile(runtime / name, resources / name)
    # Flutter/Xcode has already signed its frameworks. Sign the outer bundle
    # only, preserving the exact signed core bytes pinned in rainlink-host.
    sign(app, "dev.rainlink.rainlink", entitlements=ROOT / "app/macos/Runner/Release.entitlements")
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    for name, expected in evidence["files"].items():
        target = contents / "MacOS" / name if name in IDENTIFIERS else resources / name
        if digest(target) != expected:
            raise ValueError("Bundle signing changed the pinned runtime: " + name)
    result = {**evidence, "app": str(app), "packagedAssetsVerified": asset_count,
              "nativeSignaturesVerified": True, "applicationSignatureVerified": True,
              "nativeExecutionVerified": False, "keychainAuthorizationVerified": False}
    output = ROOT / "build/macos" / arch / "bundle-build.json"
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    return {"evidence": str(output), **result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("stage", choices=["prepare", "bundle"])
    parser.add_argument("--arch", required=True, choices=CPU_TYPES)
    parser.add_argument("--app", type=Path, default=ROOT / "app/build/macos/Build/Products/Release/RainLink.app")
    args = parser.parse_args()
    try:
        result = prepare_runtime(args.arch) if args.stage == "prepare" else assemble_bundle(args.arch, args.app)
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print("macOS build failed: " + str(error), file=sys.stderr)
        if isinstance(error, subprocess.CalledProcessError) and error.stderr:
            print(error.stderr[-4096:], file=sys.stderr)
        raise SystemExit(1) from None
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
