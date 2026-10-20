"""Verify actual closed-flow accounting on the disposable RainLink_Traffic_QA AVD.

Reuses the local authenticated proxy and shell-UID client of verify_android.
No user subscription, credentials, devices, or production database are used.
"""
import argparse
import hashlib
import json
import os
import re
import secrets
import sqlite3
import subprocess
import time

from setup_mobile_core import ROOT, sdk_from_properties
from verify_android import Fixtures, MARKER, PACKAGE

AVD = "RainLink_Traffic_QA"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="127.0.0.1:5593")
    parser.add_argument("--adb-server-port", default=5047, type=int)
    parser.add_argument("--java-home", required=True)
    parser.add_argument("--apk", required=True,
                        help="Ordinary main.dart Debug APK, not a previous Flutter drive fixture")
    parser.add_argument("--attempt", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,31}", args.attempt):
        parser.error("Attempt must be a short lowercase name")
    sdk = sdk_from_properties()
    adb = [str(sdk / "platform-tools/adb.exe"), "-P", str(args.adb_server_port),
           "-s", args.serial]

    def run(*command, timeout=30, check=True, input=None):
        return subprocess.run(adb + list(command), capture_output=True,
                              timeout=timeout, check=check, input=input)

    if run("shell", "getprop", "ro.boot.qemu.avd_name").stdout.strip() != AVD.encode():
        raise RuntimeError("Refusing to change anything outside the isolated traffic AVD")
    output = ROOT / "docs/verification/android-traffic-accounting" / args.attempt
    # A failed retry must never inherit a success report or screenshots.
    output.mkdir(parents=True, exist_ok=False)
    normal = ROOT / args.apk
    test = ROOT / "app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
    for apk in (normal, test):
        if not apk.is_file():
            raise RuntimeError("Build the ordinary Android app and native test APKs first")
        result = run("install", "-r", str(apk), timeout=120)
        if b"Success" not in result.stdout:
            raise RuntimeError("QA APK installation failed")
    test_apk_digest = hashlib.sha256(test.read_bytes()).hexdigest()
    run("shell", "appops", "set", PACKAGE, "ACTIVATE_VPN", "allow")
    run("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
    request_script = ROOT / "tools/fixtures/android_request.sh"
    run("push", str(request_script), "/data/local/tmp/rainlink-qa-request.sh")
    fixtures = Fixtures()
    attempt = secrets.token_hex(8)
    relative = "cache/traffic-accounting-qa/" + attempt
    env = os.environ.copy()
    env["JAVA_HOME"] = args.java_home
    env["PATH"] = os.pathsep.join([args.java_home + os.sep + "bin",
                                  str(sdk / "platform-tools"), env["PATH"]])
    sdk_home = os.environ.get("ANDROID_SDK_HOME")
    if sdk_home:
        emulator_key = os.path.join(sdk_home, ".android", "adbkey")
        if os.path.isfile(emulator_key):
            env["ADB_VENDOR_KEYS"] = emulator_key
    env["ADB_SERVER_SOCKET"] = "tcp:localhost:" + str(args.adb_server_port)
    env["ANDROID_ADB_SERVER_PORT"] = str(args.adb_server_port)
    env["RAINLINK_QA_OUTPUT"] = str(output)
    flutter = ROOT / ".toolchains/flutter/bin/flutter.bat"
    command = [str(flutter), "drive", "--no-pub", "-d", args.serial,
               "--driver=test_driver/android_traffic_accounting_driver.dart",
               "--target=integration_test/android_traffic_accounting_test.dart",
               "--dart-define=RAINLINK_TRAFFIC_QA_RUN=" + attempt,
               "--dart-define=RAINLINK_TRAFFIC_QA_PROXY_PORT=" + str(fixtures.proxy.server_port)]
    report = {"passed": False, "avd": AVD, "run": attempt,
              "scope": "Local fixtures on dedicated AVD; no real upstream accounts or user data",
              "flows": {}, "testApkSha256": test_apk_digest,
              "requestScriptSha256": hashlib.sha256(request_script.read_bytes()).hexdigest(),
              "sourceSha256": {name: hashlib.sha256((ROOT / name).read_bytes()).hexdigest()
                               for name in ("app/integration_test/android_traffic_accounting_test.dart",
                                            "app/test_driver/android_traffic_accounting_driver.dart",
                                            "app/android/app/src/androidTest/java/dev/rainlink/rainlink/core/TunnelRequest.java",
                                            "tools/verify_android_traffic.py", "tools/verify_android.py")}}
    child = None
    try:
        with (output / "flutter-drive.log").open("wb") as log:
            child = subprocess.Popen(command, cwd=ROOT / "app", env=env,
                                     stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 720
            while child.poll() is None:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Android traffic acceptance timed out")
                # shell v2 propagates a missing file's exit code; exec-out
                # may report success while emitting cat's diagnostic text.
                result = run("shell", "run-as", PACKAGE, "cat", relative + "/state.json", check=False)
                if result.returncode != 0:
                    time.sleep(.5)
                    continue
                state = json.loads(result.stdout)
                if state.get("run") != attempt:
                    raise RuntimeError("Unexpected test handshake identity")
                stage = state.get("stage")
                if stage in ("global", "direct", "rule") and stage not in report["flows"]:
                    address = "10.0.2.2" if stage == "direct" else "198.51.100.42"
                    port = fixtures.target.server_port if stage == "direct" else 18080
                    received = 0
                    for _ in range(12):
                        # Windows ADB shell rewrites newlines even with -T.
                        # exec-out preserves the client's original HTTP bytes;
                        # status/header/body assertions detect client failure.
                        response = run("exec-out", "sh", "/data/local/tmp/rainlink-qa-request.sh",
                                       address, "5", "/traffic-accounting", str(port), timeout=15)
                        expected = MARKER + b"\n" + b"x" * 32768
                        try:
                            receipt = json.loads(response.stdout)
                        except (ValueError, UnicodeError):
                            receipt = {}
                        if receipt != {"bytes": len(expected), "sha256": hashlib.sha256(expected).hexdigest()}:
                            report["failedResponse"] = {
                                "stage": stage, "bytes": len(response.stdout),
                                "prefix": response.stdout[:512].decode("utf-8", errors="replace"),
                                "stderr": response.stderr[:512].decode("utf-8", errors="replace")}
                            raise RuntimeError("Actual " + stage + " tunnel response mismatch")
                        received += receipt["bytes"]
                    report["flows"][stage] = {"completedRequests": 12, "payloadBytes": received}
                    # Only the app-private, unique test directory is writable.
                    run("exec-in", "run-as", PACKAGE, "tee",
                        relative + "/" + stage + ".done", input=b"12")
                    print(stage + ": 12 actual closed responses verified", flush=True)
                elif stage == "failed":
                    raise RuntimeError("The Flutter accounting assertions failed")
                elif stage == "finished" and not report.get("nativeDataCopied"):
                    for name in ("verified.csv", "ledger.sqlite"):
                        content = run("exec-out", "run-as", PACKAGE, "cat", relative + "/" + name).stdout
                        (output / name).write_bytes(content)
                    report["nativeDataCopied"] = True
                    run("exec-in", "run-as", PACKAGE, "tee",
                        relative + "/finished.done", input=b"collected")
                time.sleep(.2)
            if child.returncode != 0:
                raise RuntimeError("Flutter drive failed; inspect flutter-drive.log")
        native = json.loads((output / "flutter-evidence.json").read_text(encoding="utf-8"))
        if native.get("run") != attempt or len(report["flows"]) != 3:
            raise RuntimeError("Incomplete native evidence or external flow counts")
        if (fixtures.target_requests != 36 or len(fixtures.targets) != 24 or
                fixtures.accounting_acknowledgements != 36):
            raise RuntimeError("Independent target/proxy counts disagree with the three modes")
        csv = (output / "verified.csv").read_bytes()
        if b"com.android.shell" not in csv or "周期应用归属".encode() not in csv:
            raise RuntimeError("Actual persisted CSV is missing its application partition")
        # Copy the closed database rather than accepting only in-process reads.
        database = (output / "ledger.sqlite").read_bytes()
        with sqlite3.connect(output / "ledger.sqlite") as connection:
            if connection.execute("PRAGMA quick_check").fetchone() != ("ok",):
                raise RuntimeError("Copied SQLite failed its independent integrity check")
            if connection.execute("PRAGMA user_version").fetchone() != (8,):
                raise RuntimeError("Unexpected accounting database schema")
            totals = connection.execute("SELECT SUM(upload), SUM(download) FROM traffic_buckets").fetchone()
            if totals != (native["upload"], native["download"]):
                raise RuntimeError("Native SQLite totals differ from Flutter's reopened database")
            for application in (True, False):
                partition = connection.execute(
                    "SELECT SUM(upload), SUM(download) FROM traffic_sources WHERE (kind = 'application') = ?",
                    (int(application),)).fetchone()
                if partition != totals:
                    raise RuntimeError("Copied SQLite partition does not conserve its totals")
        report.update(passed=True, targetRequests=fixtures.target_requests,
                      proxyRequests=len(fixtures.targets), sqliteSha256=hashlib.sha256(database).hexdigest(),
                      csvSha256=hashlib.sha256(csv).hexdigest(), flutterEvidence="flutter-evidence.json",
                      independentSqliteCheck=True, completeBodyAcknowledgements=fixtures.accounting_acknowledgements)
    finally:
        if child is not None and child.poll() is None:
            # Windows batch launchers have descendants. Kill this one owned
            # verification process tree, never a global Flutter/Dart process.
            subprocess.run(["taskkill", "/PID", str(child.pid), "/T", "/F"],
                           capture_output=True, timeout=15, check=False)
        run("shell", "am", "force-stop", PACKAGE, check=False)
        fixtures.close()
        report["fixtureTargetRequests"] = fixtures.target_requests
        report["fixtureProxyRequests"] = len(fixtures.targets)
        report["completedAt"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        (output / "native-evidence.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not report["passed"]:
        raise RuntimeError("Android accounting verification did not pass")
    print("Android traffic accounting passed", flush=True)


if __name__ == "__main__":
    main()
