"""Real camera/import acceptance, restricted to the disposable RainLink_QR_QA AVD.

Requires qrcode==8.2 in --qr-library (test-only), a running virtualscene camera,
and a private adb server. No real subscriptions, nodes or devices are used.
"""
import argparse
import base64
import hashlib
import http.server
import json
from pathlib import Path
import re
import socket
import sqlite3
import subprocess
import sys
import threading
import time
import xml.etree.ElementTree as ET

from setup_mobile_core import ROOT, sdk_from_properties

PACKAGE = "dev.rainlink.rainlink"
AVD = "RainLink_QR_QA"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", default="127.0.0.1:5585")
    parser.add_argument("--adb-server-port", type=int, default=5047)
    parser.add_argument("--console-port", type=int, default=5584)
    parser.add_argument("--apk", default="app/build/app/outputs/apk/debug/app-debug.apk")
    parser.add_argument("--qr-library", default="build/qa/qr-import/python")
    args = parser.parse_args()
    sdk = sdk_from_properties()
    adb = [str(sdk / "platform-tools/adb.exe"), "-P", str(args.adb_server_port),
           "-s", args.serial]

    def run(*command, timeout=30):
        return subprocess.check_output(adb + list(command), timeout=timeout)

    # Check before installing, granting/revoking permissions or clearing data.
    if run("shell", "getprop", "ro.boot.qemu.avd_name").decode().strip() != AVD:
        raise RuntimeError("Refusing to change anything outside the isolated QR AVD")
    apk = ROOT / args.apk
    badging = subprocess.check_output([
        str(sdk / "build-tools/35.0.0/aapt.exe"), "dump", "badging", str(apk)],
        timeout=30, text=True)
    if f"package: name='{PACKAGE}'" not in badging:
        raise RuntimeError("Unexpected APK package")
    sys.path.insert(0, str(ROOT / args.qr_library))
    import qrcode

    output = ROOT / "docs/verification/qr-import/android"
    scratch = ROOT / "build/qa/qr-import/native-data"
    output.mkdir(parents=True, exist_ok=True)
    scratch.mkdir(parents=True, exist_ok=True)
    (output / "evidence.json").unlink(missing_ok=True)
    events = []

    def record(event):
        events.append(event)
        print(event, flush=True)

    def hierarchy():
        # UI transitions can temporarily have no accessibility root. Never
        # read the previous dump after that failure and tap stale coordinates.
        for _ in range(5):
            status = run("shell", "uiautomator", "dump", "/sdcard/rainlink-qr-acceptance.xml")
            if b"dumped to" in status:
                raw = run("shell", "cat", "/sdcard/rainlink-qr-acceptance.xml")
                return raw, ET.fromstring(raw)
            time.sleep(.3)
        raise RuntimeError("Android accessibility root remained unavailable")

    def label(node):
        return node.get("text") or node.get("content-desc") or ""

    def wait_for(text, *, absent=False, timeout=45):
        deadline = time.monotonic() + timeout
        while True:
            raw, tree = hierarchy()
            found = [n for n in tree.iter("node") if text in label(n)]
            if bool(found) != absent:
                return raw, tree
            if time.monotonic() >= deadline:
                (output / "failed-state.xml").write_bytes(raw)
                capture("failed-state")
                raise RuntimeError("UI did not reach expected state: " + text)
            time.sleep(.25)

    def tap(text):
        _, tree = wait_for(text)
        matches = [n for n in tree.iter("node") if text in label(n)
                   and n.get("clickable") == "true" and n.get("enabled") == "true"]
        if not matches:
            raise RuntimeError("Expected an enabled clickable control: " + text)
        # Prefer the exact button label over a container or explanatory text.
        def rectangle(node):
            return list(map(int, re.findall(r"\d+", node.get("bounds", ""))))
        matches.sort(key=lambda n: (label(n) != text,
                     (rectangle(n)[2] - rectangle(n)[0]) *
                     (rectangle(n)[3] - rectangle(n)[1])))
        left, top, right, bottom = rectangle(matches[0])
        run("shell", "input", "tap", str((left + right) // 2), str((top + bottom) // 2))

    def capture(name):
        (output / (name + ".png")).write_bytes(run("exec-out", "screencap", "-p"))
        raw, _ = hierarchy()
        (output / (name + ".xml")).write_bytes(raw)

    def console(command):
        with socket.create_connection(("127.0.0.1", args.console_port), timeout=5) as channel:
            channel.settimeout(20)
            def receive():
                data = b""
                while not data.strip().endswith(b"OK"):
                    part = channel.recv(65536)
                    if not part:
                        raise RuntimeError("Emulator console closed early")
                    data += part
                    if b"KO:" in data:
                        raise RuntimeError("Emulator rejected the QA camera command")
                return data
            receive()
            # Authentication goes only to the local emulator, never to a log.
            token = Path.home().joinpath(".emulator_console_auth_token").read_text().strip()
            channel.sendall(("auth " + token + "\n").encode())
            receive()
            channel.sendall((command + "\n").encode())
            receive()

    def poster(name, content):
        path = output / (name + "-code.png")
        qrcode.make(content, box_size=12, border=5).save(path)
        console("virtualscene-image wall " + path.as_posix())

    def camera_released():
        deadline = time.monotonic() + 15
        while True:
            state = run("shell", "cmd", "appops", "get", PACKAGE, "CAMERA").decode()
            if "(running)" not in state:
                return True
            if time.monotonic() > deadline:
                raise RuntimeError("Camera AppOp remained active after leaving scanner")
            time.sleep(.25)

    def database_snapshot(name):
        candidates = run("shell", "run-as", PACKAGE, "find", "files", "-name",
                         "rainlink.sqlite").decode().splitlines()
        if len(candidates) != 1 or not candidates[0].startswith("files/"):
            raise RuntimeError("Expected one QA database inside app files")
        relative = candidates[0]
        target = scratch / name
        target.mkdir(exist_ok=True)
        for suffix in ["", "-wal", "-shm"]:
            exists = subprocess.run(adb + ["shell", "run-as", PACKAGE, "test", "-f",
                                          relative + suffix], timeout=10).returncode == 0
            if exists:
                (target / ("rainlink.sqlite" + suffix)).write_bytes(
                    run("exec-out", "run-as", PACKAGE, "cat", relative + suffix))
        connection = sqlite3.connect(target / "rainlink.sqlite")
        connection.row_factory = sqlite3.Row
        return connection

    requests = []
    class Subscription(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
            body = ("proxies:\n  - {name: QR subscription node, type: socks5, "
                    "server: proxy.example.test, port: 1080, username: fixture-sub-user, "
                    "password: fixture-sub-password}\n").encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/yaml")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("profile-title", "base64:" +
                             base64.b64encode("QR 测试订阅".encode()).decode())
            self.send_header("subscription-userinfo",
                             "upload=1024; download=4096; total=1073741824; expire=1930000000")
            self.end_headers()
            self.wfile.write(body)
        def log_message(self, *_):
            # Request tokens and paths have no place in the verification log.
            pass

    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Subscription)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        print("installing_final_normal_apk_on_disposable_avd", flush=True)
        run("install", "-r", "-t", str(apk), timeout=120)
        run("shell", "am", "force-stop", PACKAGE)
        if run("shell", "pm", "clear", PACKAGE).strip() != b"Success":
            raise RuntimeError("Unable to reset this disposable fixture app")
        poster("invalid", "invalid-qr-fixture")
        run("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
        tap("分组")
        tap("添加订阅")
        capture("add-subscription")
        tap("扫码导入")
        wait_for("Allow RainLink")
        capture("camera-permission")
        tap("Don’t allow")
        wait_for("未获得相机权限")
        capture("camera-denied")
        tap("返回粘贴链接")
        wait_for("未获得相机权限", absent=True)
        wait_for("导入订阅")
        record("native_permission_denied_returns_to_form")

        run("shell", "pm", "grant", PACKAGE, "android.permission.CAMERA")
        tap("扫码导入")
        wait_for("将一个二维码放入取景区域")
        capture("camera-live")
        console("automation play " + (sdk / "emulator/resources/macros/Walk_to_image_room").as_posix())
        wait_for("未识别到支持的订阅地址或节点分享链接")
        capture("camera-invalid")
        record("real_camera_decodes_invalid_qr_with_safe_error")

        run("shell", "input", "keyevent", "KEYCODE_HOME")
        camera_released()
        run("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
        wait_for("将一个二维码放入取景区域")
        record("camera_pauses_in_background_and_resumes")

        poster("http-node", "http://fixture-user:fixture-password@proxy.example.test:80#QR%20HTTP")
        wait_for("已填入节点参数")
        camera_released()
        capture("node-preview")
        with database_snapshot("before-confirm") as database:
            if database.execute("SELECT count(*) FROM nodes").fetchone()[0] != 0:
                raise RuntimeError("Scanner wrote a node before confirmation")
        tap("保存节点")
        wait_for("未分组")
        with database_snapshot("node-saved") as database:
            row = dict(database.execute("SELECT * FROM nodes").fetchone())
            if (row["name"], row["server"], row["port"], row["group_id"]) != (
                    "QR HTTP", "proxy.example.test", 80, None):
                raise RuntimeError("Unexpected saved HTTP node identity or grouping")
            if not row["credential"] or "fixture-password" in row["credential"]:
                raise RuntimeError("Expected protected node credentials")
        record("real_http_qr_previews_then_persists_ungrouped_with_encrypted_credentials")

        source = f"http://10.0.2.2:{server.server_port}/subscription"
        poster("subscription", source)
        tap("添加订阅")
        tap("扫码导入")
        wait_for("已填入订阅地址")
        camera_released()
        if requests:
            raise RuntimeError("Scanner fetched the subscription before confirmation")
        capture("subscription-preview")
        tap("导入订阅")
        wait_for("QR 测试订阅")
        capture("subscription-saved")
        with database_snapshot("subscription-saved") as database:
            group = dict(database.execute("SELECT * FROM node_groups").fetchone())
            if (group["name"], group["uploaded"], group["downloaded"], group["total"],
                    group["expires_at"]) != (
                    "QR 测试订阅", 1024, 4096, 1073741824, 1930000000):
                raise RuntimeError("Subscription metadata did not survive import")
            if database.execute("SELECT count(*) FROM nodes WHERE group_id=?",
                                (group["id"],)).fetchone()[0] != 1:
                raise RuntimeError("Subscription must own its imported node")
        if requests != ["/subscription"]:
            raise RuntimeError("Expected exactly one explicitly confirmed local fetch")
        record("real_subscription_qr_fetches_once_after_confirm_and_retains_metadata")
        run("shell", "am", "force-stop", PACKAGE)
        run("shell", "am", "start", "-W", "-n", PACKAGE + "/.MainActivity")
        tap("分组")
        wait_for("QR 测试订阅")
        capture("reopened")
        camera_released()
        record("normal_app_restart_retains_subscription_and_grouping")
    finally:
        run("shell", "am", "force-stop", PACKAGE)
        server.shutdown()
        thread.join(timeout=5)
        server.server_close()

    evidence = dict(passed=True, avd=AVD, serial=args.serial,
                    apk=args.apk, apkSha256=hashlib.sha256(apk.read_bytes()).hexdigest(),
                    scope="normal main.dart app; actual CameraX/MLKit virtualscene frames; disposable AVD",
                    realDevice=False, events=events, localSubscriptionRequests=len(requests),
                    cameraReleased=camera_released(), applicationStopped=True)
    (output / "evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(evidence, ensure_ascii=False))


if __name__ == "__main__":
    main()
