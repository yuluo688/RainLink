"""Build the normal Android debug app and tests; run native unit tests and lint."""
import argparse
import os
import re
import subprocess

from setup_mobile_core import ROOT


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java-home", default=os.environ.get("JAVA_HOME"))
    parser.add_argument("--use-maven-mirror", action="store_true")
    args = parser.parse_args()
    if not args.java_home:
        raise RuntimeError("Set JAVA_HOME to a Java 17 installation")
    # Flutter 3.27 writes Windows drive colons unescaped. Fix only its generated
    # local file; Android lint must remain enabled without a PropertyEscape rule exception.
    properties = ROOT / "app/android/local.properties"
    lines = []
    for line in properties.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if key in ("sdk.dir", "flutter.sdk") and re.match(r"^[A-Za-z]:", value):
            value = value[:1] + r"\:" + value[2:]
        lines.append(key + separator + value)
    properties.write_text("\n".join(lines) + "\n", encoding="utf-8")
    env = os.environ.copy()
    env["JAVA_HOME"] = args.java_home
    env["PATH"] = args.java_home + os.sep + "bin" + os.pathsep + env["PATH"]
    command = [str(ROOT / "app/android/gradlew.bat"), ":app:assembleDebug",
               ":app:assembleDebugAndroidTest", ":app:testDebugUnitTest", ":app:lintDebug", "--console=plain", "-Ptarget=lib/main.dart"]
    if args.use_maven_mirror:
        command += ["-PuseMavenMirror=true", "--init-script", str(ROOT / "tools/android-mirrors.init.gradle")]
    subprocess.run(command, cwd=ROOT / "app/android", env=env, check=True, timeout=1200)


if __name__ == "__main__":
    main()
