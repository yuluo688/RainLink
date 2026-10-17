"""Verify the complete Android preview APK, including every native library."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
import zipfile

from setup_mobile_core import ROOT, sdk_from_properties, verify_elf_alignment


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", default="app/build/app/outputs/apk/debug/app-debug.apk")
    args = parser.parse_args()
    apk = ROOT / args.apk
    build_tools = sdk_from_properties() / "build-tools/35.0.0"
    report = {"apk": str(apk.relative_to(ROOT)), "bytes": apk.stat().st_size,
              "sha256": hashlib.sha256(apk.read_bytes()).hexdigest(),
              "scope": "local debug preview; not a production signed release", "libraries": {}}
    core = json.loads((ROOT / "build/mobile/core-build.json").read_text(encoding="utf-8"))
    if core.get("diagnosticOnly") or "cgo" not in core:
        raise RuntimeError("Build the normal core with the verified cgo alignment recipe before packaging")
    report["coreBuild"] = core
    aar = ROOT / "app/android/app/libs/rainlink-core.aar"
    if hashlib.sha256(aar.read_bytes()).hexdigest() != core["aarSha256"]:
        raise RuntimeError("Embedded core AAR does not match the build record")
    strip_tool = (sdk_from_properties() / "ndk" / core["recipe"]["ndkVersion"] /
                  "toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-strip.exe")
    expected_core = {}
    # AGP strips even an already Go-stripped library (its ELF header changes).
    # Reproduce that transformation from the verified AAR instead of trusting
    # a Gradle intermediate or accepting an unrelated but aligned library.
    with zipfile.ZipFile(aar) as archive:
        for name, data in core["libraries"].items():
            raw = archive.read(name)
            if hashlib.sha256(raw).hexdigest() != data["sha256"]:
                raise RuntimeError("AAR library does not match the build record")
            with tempfile.NamedTemporaryFile(suffix=".so", prefix="core-verify-", delete=False) as temporary:
                temporary.write(raw)
                temporary_path = temporary.name
            try:
                subprocess.run([str(strip_tool), "--strip-unneeded", temporary_path],
                               check=True, timeout=30, capture_output=True)
                with open(temporary_path, "rb") as stripped:
                    expected_core[name.replace("jni/", "lib/", 1)] = hashlib.sha256(stripped.read()).hexdigest()
            finally:
                Path(temporary_path).unlink(missing_ok=True)
    report["strippedCoreSha256"] = expected_core
    report["stripToolSha256"] = hashlib.sha256(strip_tool.read_bytes()).hexdigest()
    with zipfile.ZipFile(apk) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("APK CRC verification failed")
        for entry in archive.infolist():
            if entry.filename.endswith(".so"):
                raw = archive.read(entry)
                report["libraries"][entry.filename] = {
                    "sha256": hashlib.sha256(raw).hexdigest(),
                    "loadAlignments": verify_elf_alignment(raw),
                    "compressed": entry.compress_type != zipfile.ZIP_STORED}
    if any(report["libraries"].get(name, {}).get("sha256") != expected
           for name, expected in expected_core.items()):
        raise RuntimeError("APK is missing a requested ABI or contains a different embedded core")
    report["embeddedCoreMatchesBuild"] = True
    if not report["libraries"]:
        raise RuntimeError("APK has no native libraries")
    subprocess.run([str(build_tools / "zipalign.exe"), "-c", "-P", "16", "4", str(apk)],
                   check=True, timeout=60, capture_output=True)
    signature = subprocess.run([str(build_tools / "apksigner.bat"), "verify", "--verbose", "--print-certs", str(apk)],
                               check=True, timeout=60, capture_output=True, text=True).stdout
    badging = subprocess.run([str(build_tools / "aapt.exe"), "dump", "badging", str(apk)],
                            check=True, timeout=60, capture_output=True, text=True).stdout
    if "package: name='dev.rainlink.rainlink'" not in badging:
        raise RuntimeError("Unexpected Android package identity")
    declared = re.search(r"^version:\s*([^\s]+)", (ROOT / "app/pubspec.yaml").read_text(encoding="utf-8"), re.M)
    observed = re.search(r"^package: .*versionCode='(\d+)' versionName='([^']+)'", badging, re.M)
    if not declared or not observed or declared.group(1) != observed.group(2) + "+" + observed.group(1):
        raise RuntimeError("APK version does not match pubspec.yaml")
    report.update(versionName=observed.group(2), versionCode=int(observed.group(1)))
    report.update(crcVerified=True, zip16KBAligned=True, allLibraries16KBAligned=True,
                  signatureVerified=True, debugSigned="CN=Android Debug" in signature,
                  debuggable="application-debuggable" in badging, passed=True)
    if not report["debugSigned"] or not report["debuggable"]:
        raise RuntimeError("This verifier expects an explicitly labelled debug preview")
    output = ROOT / "docs/verification/android/package-evidence.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
