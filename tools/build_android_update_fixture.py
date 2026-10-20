"""Build an unpublished update candidate in an isolated copy, without editing app sources."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java-home", default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--attempt", help="Preserve each candidate in a separate named QA attempt")
    args = parser.parse_args()
    if not args.java_home:
        raise RuntimeError("A Java 17 installation is required")
    parent = ROOT / "build/qa/android-app-update"
    if args.attempt:
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,31}", args.attempt):
            raise RuntimeError("Invalid QA attempt name")
        parent /= "attempt-" + args.attempt
    parent.mkdir(parents=True, exist_ok=True)
    target = parent / "candidate-source"
    if target.exists():
        raise RuntimeError("Candidate source already exists; preserve the previous QA attempt")
    target.mkdir()
    manifest = []
    app = target / "app"
    app.mkdir()
    for name in ["lib", "assets", "android", "tool"]:
        shutil.copytree(ROOT / "app" / name, app / name,
                        ignore=shutil.ignore_patterns("build", ".gradle", ".cxx", ".symlinks"))
    for name in ["pubspec.yaml", "pubspec.lock", "analysis_options.yaml", ".metadata"]:
        if (ROOT / "app" / name).is_file():
            shutil.copy2(ROOT / "app" / name, app / name)
            original = hashlib.sha256((ROOT / "app" / name).read_bytes()).hexdigest()
            if hashlib.sha256((app / name).read_bytes()).hexdigest() != original:
                raise RuntimeError("QA dependency input does not match product input")
            manifest.append({"path": name, "sha256": original})
    for name in ["lib", "assets", "android", "tool"]:
        for source in (ROOT / "app" / name).rglob("*"):
            relative = source.relative_to(ROOT / "app")
            copied = app / relative
            if source.is_file() and copied.is_file():
                original = hashlib.sha256(source.read_bytes()).hexdigest()
                if hashlib.sha256(copied.read_bytes()).hexdigest() != original:
                    raise RuntimeError("QA copy does not match product input")
                manifest.append({"path": relative.as_posix(), "sha256": original})
    text = (app / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(r"^version: (\d+\.\d+\.\d+)\+(\d+)$", text, re.M)
    if not match:
        raise RuntimeError("Expected a numbered app build")
    name = match.group(1)
    code = int(match.group(2)) + 1
    version = f"{name}+{code}"
    (app / "pubspec.yaml").write_text(text[:match.start()] + "version: " + version +
                                      text[match.end():], encoding="utf-8")
    env = os.environ.copy()
    env["JAVA_HOME"] = args.java_home
    env["PATH"] = args.java_home + os.sep + "bin" + os.pathsep + env["PATH"]
    flutter = ROOT / ".toolchains/flutter/bin/flutter.bat"
    dart = ROOT / ".toolchains/flutter/bin/dart.bat"
    subprocess.run([str(flutter), "pub", "get", "--offline"], cwd=app, env=env, check=True, timeout=120)
    subprocess.run([str(dart), "run", "tool/generate_build_info.dart"], cwd=app, env=env, check=True, timeout=120)
    properties = app / "android/local.properties"
    old = properties.read_text(encoding="utf-8").splitlines()
    values = {"flutter.versionName": name, "flutter.versionCode": str(code)}
    lines = []
    for line in old:
        key, separator, value = line.partition("=")
        if key in values:
            value = values.pop(key)
        if key in ("sdk.dir", "flutter.sdk") and re.match(r"^[A-Za-z]:", value):
            value = value[:1] + r"\:" + value[2:]
        lines.append(key + separator + value)
    lines.extend(k + "=" + v for k, v in values.items())
    properties.write_text("\n".join(lines) + "\n", encoding="utf-8")
    subprocess.run([str(app / "android/gradlew.bat"), ":app:assembleDebug", "--console=plain",
                    "-Ptarget=lib/main.dart", "-PuseMavenMirror=true", "--init-script",
                    str(ROOT / "tools/android-mirrors.init.gradle")],
                   cwd=app / "android", env=env, check=True, timeout=1200)
    apk = app / "build/app/outputs/apk/debug/app-debug.apk"
    output = parent / f"RainLink-{version}-android-universal.apk"
    if output.exists():
        raise RuntimeError("Refusing to overwrite a previous candidate")
    shutil.copy2(apk, output)
    evidence = {"scope": "Unpublished QA-only full normal app, copied inputs; version increment only",
                "versionName": name, "versionCode": code,
                "apk": output.relative_to(ROOT).as_posix(), "bytes": output.stat().st_size,
                "sha256": hashlib.sha256(output.read_bytes()).hexdigest(), "copiedInputs": manifest}
    (parent / "candidate-build.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({k: v for k, v in evidence.items() if k != "copiedInputs"}))


if __name__ == "__main__":
    main()
