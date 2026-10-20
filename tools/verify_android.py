"""Verify native Android capture using a dedicated QA AVD and local fixtures.

The authenticated proxy/DNS servers contain only public fixture credentials.
No user subscription or real upstream account is imported into the emulator.
"""
import argparse
import hashlib
import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import select
import shutil
import socket
import struct
import subprocess
import threading
import time

from setup_mobile_core import sdk_from_properties

ROOT = Path(__file__).resolve().parent.parent
PACKAGE = "dev.rainlink.rainlink"
MARKER = b"RainLink Android tunnel fixture"
AUTH = "Basic " + base64.b64encode(b"fixture-user:fixture-password").decode()


class Fixtures:
    def __init__(self):
        self.lock = threading.Lock()
        self.targets = []
        self.dns_queries = 0
        self.target_requests = 0
        self.forward_upload = 0
        self.forward_download = 0
        self.held_requests = 0
        self.held_closed = 0
        self.delayed_connects = 0
        self.accounting_acknowledgements = 0
        owner = self

        class Target(BaseHTTPRequestHandler):
            def do_GET(self):
                with owner.lock:
                    owner.target_requests += 1
                payload = MARKER + b"\n" + b"x" * 32768
                self.send_response(200)
                held = self.path == "/hold"
                self.send_header("Content-Length", str(64 * 1024 * 1024 if held else len(payload)))
                self.send_header("Connection", "close")
                self.end_headers()
                self.wfile.write(payload)
                self.wfile.flush()
                if self.path == "/traffic-accounting":
                    # Wait for a complete-body receipt before closing this
                    # Windows/QEMU socket. Immediate close can truncate the
                    # final bytes in the emulator's host-network bridge.
                    self.connection.settimeout(5)
                    if self.rfile.read(1) != b"R":
                        return
                    with owner.lock:
                        owner.accounting_acknowledgements += 1
                if held:
                    with owner.lock:
                        owner.held_requests += 1
                    # The incomplete body keeps the actual TCP stream alive.
                    # EOF here proves that a native close reached the target.
                    self.connection.settimeout(30)
                    try:
                        while self.connection.recv(1024):
                            pass
                        with owner.lock:
                            owner.held_closed += 1
                    except (OSError, TimeoutError):
                        pass

            def log_message(self, *args):
                pass

        class Proxy(BaseHTTPRequestHandler):
            # CONNECT changes this connection to a byte tunnel. Buffered header
            # reads must not consume the beginning of a pipelined TCP payload.
            rbufsize = 0
            def do_CONNECT(self):
                from urllib.parse import urlsplit
                target = urlsplit("//" + self.path)
                if self.headers.get("Proxy-Authorization") != AUTH:
                    self.send_error(407)
                    return
                if target.hostname not in ("198.51.100.42", "2001:db8::42", "rainlink.test") or target.port not in (18080, 18081):
                    self.send_error(502)
                    return
                with owner.lock:
                    owner.targets.append(target.hostname)
                if target.port == 18081:
                    # Make startup recovery exercise a delayed proxy handshake,
                    # rather than depending on an unrealistically instant LAN.
                    with owner.lock:
                        owner.delayed_connects += 1
                    time.sleep(1.5)
                upstream = socket.create_connection(owner.target.server_address, timeout=5)
                self.connection.settimeout(10)
                upstream.settimeout(10)
                self.send_response(200, "Connection Established")
                self.end_headers()
                self.wfile.flush()
                try:
                    deadline = time.monotonic() + 45
                    readers = [self.connection, upstream]
                    while time.monotonic() < deadline:
                        readable, _, _ = select.select(readers, [], [], 1)
                        for source in readable:
                            data = source.recv(65536)
                            if not data:
                                if source is upstream:
                                    return
                                readers.remove(source)
                                upstream.shutdown(socket.SHUT_WR)
                                continue
                            with owner.lock:
                                if source is self.connection:
                                    owner.forward_upload += len(data)
                                else:
                                    owner.forward_download += len(data)
                            (upstream if source is self.connection else self.connection).sendall(data)
                except (OSError, TimeoutError):
                    return
                finally:
                    upstream.close()
                    self.close_connection = True

            def log_message(self, *args):
                pass

        self.target = ThreadingHTTPServer(("127.0.0.1", 0), Target)
        self.proxy = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
        self.dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.dns.bind(("127.0.0.1", 0))
        self.dns.settimeout(0.5)
        self.stopped = threading.Event()
        self.threads = [threading.Thread(target=server.serve_forever, daemon=True) for server in (self.target, self.proxy)]
        self.threads.append(threading.Thread(target=self.serve_dns, daemon=True))
        for thread in self.threads:
            thread.start()

    def serve_dns(self):
        while not self.stopped.is_set():
            try:
                query, peer = self.dns.recvfrom(4096)
                position = 12
                while position < len(query) and query[position]:
                    position += query[position] + 1
                position += 1
                question = query[12:position + 4]
                kind = struct.unpack_from("!H", query, position)[0]
                record = b""
                if kind in (1, 28):
                    address = socket.inet_pton(socket.AF_INET if kind == 1 else socket.AF_INET6,
                                               "198.51.100.42" if kind == 1 else "2001:db8::42")
                    record = b"\xc0\x0c" + struct.pack("!HHIH", kind, 1, 30, len(address)) + address
                response = query[:2] + struct.pack("!HHHHH", 0x8180, 1, 1 if record else 0, 0, 0) + question + record
                self.dns.sendto(response, peer)
                with self.lock:
                    self.dns_queries += 1
            except socket.timeout:
                continue
            except OSError:
                return
            except (IndexError, struct.error):
                continue

    def close(self):
        self.stopped.set()
        self.dns.close()
        for server in (self.proxy, self.target):
            server.shutdown()
            server.server_close()
        for thread in self.threads:
            thread.join(timeout=3)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--serial", required=True)
    parser.add_argument("--ui", action="store_true", help="Run Flutter UI and telemetry verification after the QA permission setup")
    parser.add_argument("--ui-suite", choices=("primary", "configuration"), default="primary",
                        help="Select the primary visual/telemetry suite or actual chain/configuration flows")
    parser.add_argument("--handover", action="store_true",
                        help="Also verify Wi-Fi, cellular and offline recovery on the named QA AVD")
    parser.add_argument("--flutter-root", default=os.environ.get("FLUTTER_ROOT"))
    args = parser.parse_args()
    if args.ui_suite != "primary" and not args.ui:
        parser.error("--ui-suite requires --ui")
    if args.handover and args.ui:
        parser.error("--handover runs with native verification, without --ui")
    adb = sdk_from_properties() / "platform-tools/adb.exe"

    def run(*command, timeout=120, check=True):
        result = subprocess.run([str(adb), "-s", args.serial, *command], capture_output=True,
                                text=True, encoding="utf-8", errors="replace", timeout=timeout)
        if check and result.returncode:
            raise RuntimeError("adb failed: " + result.stdout + result.stderr)
        return result.stdout + result.stderr

    name = run("shell", "getprop", "ro.boot.qemu.avd_name").strip()
    if name != "RainLink_QA":
        raise RuntimeError("Native fixture verification is restricted to the RainLink_QA AVD")
    for apk, package in ((ROOT / "app/build/app/outputs/apk/debug/app-debug.apk", PACKAGE),
                         (ROOT / "app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk", PACKAGE + ".test")):
        if not apk.exists():
            raise RuntimeError("Build the native debug and instrumentation APKs first: " + str(apk))
        result = run("install", "-r", str(apk), check=False)
        if "INSTALL_FAILED_UPDATE_INCOMPATIBLE" in result:
            # Only this isolated AVD is allowed above. A changed local debug
            # key must not make the fixture silently run an older QA binary.
            print(run("uninstall", package))
            result = run("install", str(apk))
        if "Success" not in result:
            raise RuntimeError("QA APK installation failed: " + result)
        print(result, flush=True)
    run("shell", "appops", "set", PACKAGE, "ACTIVATE_VPN", "allow")
    run("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
    if args.ui:
        flutter = str(Path(args.flutter_root) / "bin/flutter.bat") if args.flutter_root else shutil.which("flutter")
        if not flutter:
            raise RuntimeError("Set FLUTTER_ROOT or --flutter-root for Android UI verification")
        # Flutter drive removes its test app on exit. Reinstall and grant only
        # on this named QA AVD before every run; never automate a user's consent.
        suite = "android_ui" if args.ui_suite == "primary" else "android_configuration"
        try:
            subprocess.run([flutter, "drive", "--no-pub", "--driver=test_driver/" + suite + "_driver.dart",
                            "--target=integration_test/" + suite + "_test.dart", "-d", args.serial],
                           cwd=ROOT / "app", check=True, timeout=600)
        finally:
            run("shell", "am", "force-stop", PACKAGE, check=False)
        return
    run("shell", "run-as", PACKAGE, "rm", "-f", "cache/native-qa-stderr.log")
    request_script = ROOT / "tools/fixtures/android_request.sh"
    run("push", str(request_script), "/data/local/tmp/rainlink-qa-request.sh")
    script_sha = hashlib.sha256(request_script.read_bytes()).hexdigest()
    if run("shell", "sha256sum", "/data/local/tmp/rainlink-qa-request.sh").split()[0] != script_sha:
        raise RuntimeError("QA request client script checksum mismatch")
    fixtures = Fixtures()
    report = {"device": name, "serial": args.serial, "androidApi": run("shell", "getprop", "ro.build.version.sdk").strip(),
              "scope": "isolated emulator; authenticated local proxy; no real subscription", "passed": False}
    report["apkSha256"] = hashlib.sha256((ROOT / "app/build/app/outputs/apk/debug/app-debug.apk").read_bytes()).hexdigest()
    report["testApkSha256"] = hashlib.sha256((ROOT / "app/build/app/outputs/apk/androidTest/debug/app-debug-androidTest.apk").read_bytes()).hexdigest()
    report["memoryPressureTransferRounds"] = 12
    report["telemetryScope"] = "stable connection paging; session-scoped single/all close; persistent in-process sanitized logs"
    report["documentScope"] = "actual ACTION_CREATE_DOCUMENT save and byte readback; cancel; invalid source; busy; activity disposal while picker is open"
    report["startupRecoveryScope"] = "three occupied-port startup failures; cleanup returns idle; each subsequent system-registered tunnel carries traffic through a 1.5 second delayed proxy handshake"
    report["requestClientScope"] = "shell UID app_process Socket client; write side stays open until response completion; bounded connect and read waits"
    report["requestScriptSha256"] = script_sha
    report["notificationScope"] = "runtime notification permission revoked before a separate instrumentation process; count-only expiry notification; real PendingIntent opens Flutter groups; connected and disconnected alerts; optional alerts disabled without removing foreground notice"
    report["coreBuild"] = json.loads((ROOT / "build/mobile/core-build.json").read_text(encoding="utf-8"))
    output = ROOT / "docs/verification/android"
    output.mkdir(parents=True, exist_ok=True)
    try:
        print("Verifying five core cases in an isolated test process...", flush=True)
        result = run("shell", "am", "instrument", "-w", "-r", "-e", "proxyPort", str(fixtures.proxy.server_port),
                     "-e", "dnsPort", str(fixtures.dns.getsockname()[1]), "-e", "class",
                     PACKAGE + ".core.AndroidCoreTest",
                     PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner", timeout=420)
        (output / "instrumentation-core.txt").write_text(result, encoding="utf-8")
        # Release lifecycle-test Flutter engines before testing the external
        # system picker. Assertions and the actual save/cancel/dispose paths
        # remain unchanged; long same-process stress is recorded separately.
        run("shell", "am", "force-stop", PACKAGE)
        print("Verifying two system document cases...", flush=True)
        documents = run("shell", "am", "instrument", "-w", "-r", "-e", "class",
                        PACKAGE + ".export.AndroidDocumentExportTest",
                        PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner", timeout=180)
        (output / "instrumentation-documents.txt").write_text(documents, encoding="utf-8")
        # Notification clicks deliberately exercise a cold ordinary UI rather
        # than reusing the many Flutter engines created by lifecycle tests.
        run("shell", "am", "force-stop", PACKAGE)
        print("Verifying the actual notification cold-start destination...", flush=True)
        notifications = run("shell", "am", "instrument", "-w", "-r", "-e", "class",
                            PACKAGE + ".notifications.AndroidNotificationsTest",
                            PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner", timeout=120)
        (output / "instrumentation-notifications.txt").write_text(notifications, encoding="utf-8")
        # On Android 13+, notification permission is separate from legacy
        # AppOps. Revoking it kills this UID, so start a fresh test process
        # after revocation instead of invalidating an in-flight runner.
        run("shell", "am", "force-stop", PACKAGE)
        run("shell", "pm", "revoke", PACKAGE, "android.permission.POST_NOTIFICATIONS")
        print("Verifying actual notification runtime permission denial...", flush=True)
        try:
            denied = run("shell", "am", "instrument", "-w", "-r", "-e", "class",
                         PACKAGE + ".notifications.AndroidNotificationPermissionTest",
                         PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner", timeout=60)
        finally:
            run("shell", "pm", "grant", PACKAGE, "android.permission.POST_NOTIFICATIONS")
        (output / "instrumentation-notification-denied.txt").write_text(denied, encoding="utf-8")
        core_passed = bool(re.search(r"OK \(5 tests\)", result))
        documents_passed = bool(re.search(r"OK \(2 tests\)", documents))
        notifications_passed = bool(re.search(r"OK \(1 test\)", notifications))
        denied_passed = bool(re.search(r"OK \(1 test\)", denied))
        report["instrumentationRuns"] = {"core": {"tests": 5, "passed": core_passed},
                                         "documents": {"tests": 2, "passed": documents_passed},
                                         "notificationColdStart": {"tests": 1, "passed": notifications_passed},
                                         "notificationPermissionDenied": {"tests": 1, "passed": denied_passed}}
        result += "\nSystem documents:\n" + documents + "\nNotification cold start:\n" + notifications + "\nRuntime notification permission denied:\n" + denied
        handover_passed = True
        if args.handover:
            run("shell", "am", "force-stop", PACKAGE)
            wifi = run("shell", "settings", "get", "global", "wifi_on").strip()
            mobile_data = run("shell", "settings", "get", "global", "mobile_data").strip()
            if wifi not in ("0", "1") or mobile_data not in ("0", "1"):
                raise RuntimeError("Cannot determine the QA AVD's original radio state")
            print("Verifying Wi-Fi/cellular/offline recovery and manual disconnect...", flush=True)
            try:
                handover = run("shell", "am", "instrument", "-w", "-r", "-e", "proxyPort", str(fixtures.proxy.server_port),
                               "-e", "dnsPort", str(fixtures.dns.getsockname()[1]), "-e", "class",
                               PACKAGE + ".core.AndroidNetworkHandoverTest",
                               PACKAGE + ".test/androidx.test.runner.AndroidJUnitRunner", timeout=300)
            finally:
                run("shell", "am", "force-stop", PACKAGE, check=False)
                run("shell", "svc", "wifi", "enable" if wifi == "1" else "disable")
                run("shell", "svc", "data", "enable" if mobile_data == "1" else "disable")
                restored_radios = {"wifi": run("shell", "settings", "get", "global", "wifi_on").strip(),
                                   "mobileData": run("shell", "settings", "get", "global", "mobile_data").strip()}
            (output / "instrumentation-network-handover.txt").write_text(handover, encoding="utf-8")
            match = re.search(r"INSTRUMENTATION_STATUS: rainlinkNetworkFlow=(\{[^\r\n]+\})", handover)
            journey = json.loads(match.group(1)) if match else {}
            handover_passed = (restored_radios == {"wifi": wifi, "mobileData": mobile_data} and
                               bool(re.search(r"OK \(1 test\)", handover)) and
                               journey.get("actualTransfers") == 3 and journey.get("sameSystemTunnelSurvived") is True and
                               journey.get("manualStopPreventedLateReconnect") is True and
                               [stage.get("stage") for stage in journey.get("stages", [])] == ["wifi", "cellular", "offline", "wifi-restored"])
            report["instrumentationRuns"]["networkHandover"] = {"tests": 1, "passed": handover_passed}
            report["networkHandover"] = journey
            report["networkHandoverOriginalRadios"] = {"wifi": wifi, "mobileData": mobile_data}
            report["networkHandoverRestoredRadios"] = restored_radios
            result += "\nNetwork handover:\n" + handover
        (output / "instrumentation.txt").write_text(result, encoding="utf-8")
        print(result)
        report.update(authenticatedConnects=len(fixtures.targets),
                      ipv6Connects=fixtures.targets.count("2001:db8::42"), dnsQueries=fixtures.dns_queries,
                      targetRequests=fixtures.target_requests, forwardUpload=fixtures.forward_upload,
                      forwardDownload=fixtures.forward_download, heldRequests=fixtures.held_requests,
                      heldConnectionsClosed=fixtures.held_closed, delayedProxyHandshakes=fixtures.delayed_connects)
        report["passed"] = (core_passed and documents_passed and notifications_passed and denied_passed and handover_passed and report["ipv6Connects"] > 0
                            and report["dnsQueries"] > 0 and report["heldRequests"] >= 3
                            and report["heldConnectionsClosed"] >= 3 and report["delayedProxyHandshakes"] == 3)
    finally:
        run("shell", "am", "force-stop", PACKAGE, check=False)
        if not report["passed"]:
            crash = run("shell", "run-as", PACKAGE, "cat", "cache/native-qa-stderr.log", check=False)
            if "fatal error:" in crash or "panic:" in crash:
                (output / "native-crash.txt").write_text(crash[:2 * 1024 * 1024], encoding="utf-8")
                report["crashDiagnostic"] = "native-crash.txt"
        fixtures.close()
        report["at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
        (output / "native-evidence.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not report["passed"]:
        raise RuntimeError("Android native verification did not pass; inspect instrumentation.txt")


if __name__ == "__main__":
    main()
