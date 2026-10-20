"""Exercise real APK validation and system consent on RainLink_Update_QA only."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sqlite3
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

from setup_mobile_core import ROOT, sdk_from_properties

PACKAGE = "dev.rainlink.rainlink"
AVD = "RainLink_Update_QA"
TEST_CLASS = PACKAGE + ".updates.AndroidUpdateInstallerTest"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--java-home", required=True)
    parser.add_argument("--serial", default="127.0.0.1:5591")
    parser.add_argument("--adb-server-port", default=5047, type=int)
    parser.add_argument("--stage", choices=["provision", "safety", "permission", "cancel", "install"], required=True)
    parser.add_argument("--attempt", help="Candidate attempt created by build_android_update_fixture.py")
    args = parser.parse_args()
    sdk = sdk_from_properties()
    adb = [str(sdk / "platform-tools/adb.exe"), "-P", str(args.adb_server_port), "-s", args.serial]

    def run(*command, timeout=30):
        return subprocess.check_output(adb + list(command), timeout=timeout)

    if run("shell", "getprop", "ro.boot.qemu.avd_name").decode().strip() != AVD:
        raise RuntimeError("Refusing to modify a device outside the disposable update AVD")
    work = ROOT / "build/qa/android-app-update"
    out = ROOT / "docs/verification/android-app-update/android"
    out.mkdir(parents=True, exist_ok=True)
    attempt = work
    if args.attempt:
        if not re.fullmatch(r"[a-z0-9][a-z0-9-]{0,31}", args.attempt):
            raise RuntimeError("Invalid QA attempt name")
        attempt /= "attempt-" + args.attempt
    candidate = json.loads((attempt / "candidate-build.json").read_text(encoding="utf-8"))
    apk = ROOT / candidate["apk"]
    if candidate["versionCode"] != 5 or hashlib.sha256(apk.read_bytes()).hexdigest() != candidate["sha256"]:
        raise RuntimeError("Unexpected QA candidate version or bytes")
    normal = ROOT / "app/build/app/outputs/apk/debug/app-debug.apk"
    test_apk = ROOT / "app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk"
    build_tools = sdk / "build-tools/35.0.0"

    def external(command):
        return subprocess.check_output([str(c) for c in command], timeout=120, stderr=subprocess.STDOUT)

    def installed_code():
        raw = run("shell", "dumpsys", "package", PACKAGE).decode()
        match = re.search(r"\bversionCode=(\d+)\b", raw)
        return int(match.group(1)) if match else None

    def reset_source_consent():
        # Drop any inherited UID override before resetting the package grant.
        # A UID deny would also override a subsequent grant in system settings.
        run("shell", "cmd", "appops", "set", "--uid", PACKAGE, "REQUEST_INSTALL_PACKAGES", "default")
        run("shell", "cmd", "appops", "set", PACKAGE, "REQUEST_INSTALL_PACKAGES", "deny")

    def hierarchy():
        for _ in range(5):
            status = run("shell", "uiautomator", "dump", "/sdcard/rainlink-update.xml")
            if b"dumped to" in status:
                raw = run("shell", "cat", "/sdcard/rainlink-update.xml")
                return raw, ET.fromstring(raw)
            time.sleep(.3)
        raise RuntimeError("Accessibility root remained unavailable")

    def label(node):
        return node.get("text") or node.get("content-desc") or node.get("hint") or ""

    def wait(text, timeout=40):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            raw, tree = hierarchy()
            if any(text in label(n) for n in tree.iter("node")):
                return raw, tree
        capture("failed-" + args.stage)
        raise RuntimeError("Expected UI state did not appear: " + text)

    def tap(text):
        _, tree = wait(text)
        parents = {child: parent for parent in tree.iter() for child in parent}
        matches = [n for n in tree.iter("node") if text in label(n)]
        matches.sort(key=lambda n: label(n) != text)
        nodes = []
        for match in matches:
            node = match
            # Android's Compose settings exposes a labeled TextView inside the
            # clickable switch row. Use its nearest enabled ancestor only.
            while node is not None and node.tag == "node":
                if node.get("clickable") == "true" and node.get("enabled") == "true":
                    nodes.append(node)
                    break
                node = parents.get(node)
        if not nodes:
            raise RuntimeError("No enabled clickable control: " + text)
        bounds = list(map(int, re.findall(r"\d+", nodes[0].get("bounds", ""))))
        run("shell", "input", "tap", str((bounds[0] + bounds[2]) // 2), str((bounds[1] + bounds[3]) // 2))

    def capture(name):
        (out / (name + ".png")).write_bytes(run("exec-out", "screencap", "-p"))
        raw, _ = hierarchy()
        (out / (name + ".xml")).write_bytes(raw)

    def database_projection(name):
        candidates = run("shell", "run-as", PACKAGE, "find", "files", "-name", "rainlink.sqlite").decode().splitlines()
        if len(candidates) != 1 or not candidates[0].startswith("files/"):
            raise RuntimeError("Expected one database inside the QA app")
        relative = candidates[0]
        scratch = work / "native-data"
        scratch.mkdir(parents=True, exist_ok=True)
        target = Path(tempfile.mkdtemp(prefix=name + "-", dir=scratch))
        for suffix in ["", "-wal", "-shm"]:
            exists = subprocess.run(adb + ["shell", "run-as", PACKAGE, "test", "-f", relative + suffix], timeout=10).returncode == 0
            if exists:
                (target / ("rainlink.sqlite" + suffix)).write_bytes(run("exec-out", "run-as", PACKAGE, "cat", relative + suffix))
        with sqlite3.connect(target / "rainlink.sqlite") as database:
            database.row_factory = sqlite3.Row
            result = {table: [dict(row) for row in database.execute("SELECT * FROM " + table + " ORDER BY 1")]
                      for table in ["nodes", "node_groups", "node_overrides", "preferences"]}
            result["schema"] = database.execute("PRAGMA user_version").fetchone()[0]
        return result

    def seed_data():
        # Ordinary UI writes one fictitious node and a preference. Never inject
        # database rows or expose a fixture-only production configuration flag.
        run("shell", "am", "force-stop", PACKAGE)
        baseline = database_projection("seed-baseline")
        rows = baseline["nodes"]
        if rows and (len(rows) != 1 or rows[0]["name"] != "QAUpdateNode"):
            raise RuntimeError("Unexpected data in the disposable update app")
        run("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
        tap("节点")
        if not rows:
            tap("添加")
            for field, value in [("节点名称", "QAUpdateNode"),
                                 ("服务器地址", "proxy.example.test"), ("端口", "8080")]:
                tap(field)
                run("shell", "input", "text", value)
                run("shell", "input", "keyevent", "KEYCODE_BACK")
            tap("保存节点")
        wait("QAUpdateNode")
        capture("before-upgrade-node")
        tap("设置")
        tap("外观")
        if not any(row["key"] == "appearance.theme" and row["value"] == "light" for row in baseline["preferences"]):
            tap("浅色")
            wait("外观设置已保存")
        run("shell", "am", "force-stop", PACKAGE)
        value = database_projection("before-install")
        rows = value["nodes"]
        preferences = {row["key"]: row["value"] for row in value["preferences"]}
        if len(rows) != 1 or (rows[0]["name"], rows[0]["server"], rows[0]["port"], rows[0]["group_id"]) != (
                "QAUpdateNode", "proxy.example.test", 8080, None) or preferences.get("appearance.theme") != "light":
            raise RuntimeError("Ordinary UI did not save the expected node and theme")
        return value

    if args.stage == "provision":
        badging = external([build_tools / "aapt.exe", "dump", "badging", normal]).decode()
        if f"package: name='{PACKAGE}' versionCode='4'" not in badging:
            raise RuntimeError("Normal QA app must be the current build 4")
        run("install", "-r", "-d", "-t", str(normal), timeout=120)
        run("install", "-r", "-t", str(test_apk), timeout=120)
        if run("shell", "pm", "clear", PACKAGE).strip() != b"Success":
            raise RuntimeError("Unable to reset the disposable update app")
        reset_source_consent()
        fixtures = work / "apk-fixtures"
        fixtures.mkdir(exist_ok=True)
        key = fixtures / "fixture.jks"
        if not key.exists():
            external([Path(args.java_home) / "bin/keytool.exe", "-genkeypair", "-keystore", key,
                      "-alias", "fixture", "-storepass", "fixture-password", "-keypass", "fixture-password",
                      "-dname", "CN=RainLink Untrusted QA Fixture", "-keyalg", "RSA", "-validity", "30"])
        manifest = fixtures / "AndroidManifest.xml"
        manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android" '
                            'package="dev.rainlink.fixture" android:versionCode="5" android:versionName="0.1.0">'
                            '<uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/>'
                            '<application android:label="RainLink QA Fixture"/></manifest>', encoding="utf-8")
        unsigned = fixtures / "wrong-package-unsigned.apk"
        external([build_tools / "aapt2.exe", "link", "--manifest", manifest, "-I",
                  sdk / "platforms/android-35/android.jar", "-o", unsigned])
        for source, output in [(unsigned, fixtures / "wrong-package.apk"), (apk, fixtures / "wrong-signer.apk")]:
            external([build_tools / "apksigner.bat", "sign", "--ks", key, "--ks-key-alias", "fixture",
                      "--ks-pass", "pass:fixture-password", "--key-pass", "pass:fixture-password", "--out", output, source])
            external([build_tools / "apksigner.bat", "verify", output])
        targets = [(apk, "updates/download-fixture/" + apk.name),
                   (normal, "updates/download-fixture/RainLink-0.1.0+4-android-universal.apk"),
                   (apk, "updates/download-fixture/RainLink-0.1.0+6-android-universal.apk"),
                   (fixtures / "wrong-package.apk", "update-fixtures/wrong-package.apk"),
                   (fixtures / "wrong-signer.apk", "update-fixtures/wrong-signer.apk")]
        for index, (source, target) in enumerate(targets):
            remote = f"/data/local/tmp/rainlink-update-fixture-{index}.apk"
            run("push", str(source), remote, timeout=120)
            run("shell", "run-as", PACKAGE, "mkdir", "-p", "cache/" + target.rsplit("/", 1)[0])
            run("shell", "run-as", PACKAGE, "cp", remote, "cache/" + target, timeout=60)
            run("shell", "rm", remote)
        print("provisioned_only_disposable_update_avd", flush=True)
        return

    if installed_code() != 4:
        raise RuntimeError("Acceptance must begin with the ordinary build 4")
    if args.stage in ("permission", "cancel"):
        reset_source_consent()
    if args.stage == "safety":
        methods = ["validatesActualPackageAndPrivateCopyBeforeConsent",
                   "rejectsWrongDigestVersionPackageSignatureAndPath", "cancelledPreparationDoesNotLeaveAPackage"]
        result = run("shell", "am", "instrument", "-w", "-r", "-e", "class",
                     ",".join(TEST_CLASS + "#" + m for m in methods),
                     PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner", timeout=240).decode()
        (out / "native-safety.log").write_text(result, encoding="utf-8")
        if "OK (3 tests)" not in result:
            raise RuntimeError("Real native safety suite did not pass; inspect native-safety.log")
        print("native_real_apk_safety_3_passed", flush=True)
        return

    if args.stage == "install":
        # A failed rerun must never leave a previous success as its result.
        (out / "install-evidence.json").unlink(missing_ok=True)
    before = seed_data() if args.stage == "install" else None
    expected = "permission_denied" if args.stage == "permission" else "cancelled"
    log = out / ("system-" + args.stage + ".log")
    with log.open("wb") as stream:
        command = adb + ["shell", "am", "instrument", "-w", "-r", "-e", "class",
                    TEST_CLASS + "#systemConsent", "-e", "expectedOutcome", expected,
                    ]
        if args.stage == "install":
            command += ["-e", "expectedLightSystemBars", "true"]
        command += [PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner"]
        process = subprocess.Popen(command, stdout=stream, stderr=subprocess.STDOUT)
        try:
            if args.stage == "permission":
                wait("Allow from this source")
                capture("install-source-permission")
                run("shell", "input", "keyevent", "KEYCODE_BACK")
            else:
                # The cancelled attempt also exercises granting the real source
                # setting, rather than replacing permission with a fake reply.
                raw, tree = hierarchy()
                if args.stage == "cancel":
                    wait("Allow from this source")
                    tap("Allow from this source")
                    run("shell", "input", "keyevent", "KEYCODE_BACK")
                wait("Update")
                capture("installer-" + args.stage)
                tap("Cancel" if args.stage == "cancel" else "Update")
            if args.stage == "install":
                deadline = time.monotonic() + 120
                while time.monotonic() < deadline and installed_code() != 5:
                    time.sleep(.5)
                if installed_code() != 5:
                    capture("failed-install")
                    raise RuntimeError("The system did not replace the package with build 5")
                run("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
                wait("首页")
                tap("设置")
                tap("更新")
                wait("RainLink 0.1.0+5")
                wait("上次更新已安装")
                capture("reopened-updated-app")
                run("shell", "am", "force-stop", PACKAGE)
                after = database_projection("after-install")
                if before != after:
                    raise RuntimeError("The real system upgrade changed saved nodes or preferences")
                run("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
                tap("节点")
                wait("QAUpdateNode")
                capture("reopened-preserved-node")
                result = {"passed": True, "avd": AVD, "realDevice": False,
                          "systemPackageVersionCode": installed_code(), "candidateSha256": candidate["sha256"],
                          "normalAppReopenedVersion": "0.1.0+5", "productionReleasePublished": False,
                          "nativeInstalledReceiptDisplayed": True, "databaseSchema": after["schema"],
                          "fictitiousNodesPreserved": len(after["nodes"]), "themePreserved": "light",
                          "controlledUserDataUnchanged": True,
                          "lightSystemBarContrastVerified": True,
                          "controlledUserDataSha256": hashlib.sha256(json.dumps(after, sort_keys=True).encode()).hexdigest()}
                (out / "install-evidence.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
                print(json.dumps(result), flush=True)
            else:
                process.wait(timeout=90)
                if "OK (1 test)" not in log.read_text(encoding="utf-8") or installed_code() != 4:
                    raise RuntimeError("System consent rejection/cancellation did not preserve the old version")
                print("system_" + args.stage + "_preserves_build_4", flush=True)
        finally:
            if process.poll() is None:
                # am instrument is ours, on the attested disposable AVD only.
                run("shell", "am", "force-stop", PACKAGE)
                process.wait(timeout=15)


if __name__ == "__main__":
    main()
