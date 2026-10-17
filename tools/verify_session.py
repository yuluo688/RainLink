"""Exercise the Windows host/core and durable proxy recovery with local fixtures.

Run after tools/dev.ps1 prepare. This temporarily enables the current user's
system proxy and verifies that every scenario restores the exact original values.
--egress additionally checks public IP/latency through a local forwarding proxy;
it does not represent testing a third-party remote node.
"""
import argparse
import ctypes
from ctypes import wintypes
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import queue
import select
import socket
import subprocess
import threading
import time
import winreg


ROOT = Path(__file__).resolve().parent.parent
PROXY_KEY = r"Software\Microsoft\Windows\CurrentVersion\Internet Settings"
PROXY_NAMES = ("ProxyEnable", "ProxyServer", "ProxyOverride", "AutoConfigURL", "AutoDetect")


def proxy_snapshot():
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, PROXY_KEY) as key:
        result = {}
        for name in PROXY_NAMES:
            try:
                result[name] = winreg.QueryValueEx(key, name)
            except FileNotFoundError:
                result[name] = None
        return result


def eventually(check, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if check():
            return
        time.sleep(0.1)
    raise AssertionError("Timed out waiting for the expected runtime state")


class Host:
    def __init__(self, executable, *, isolated=False):
        self.process = subprocess.Popen(
            [str(executable), "serve-test" if isolated else "serve"], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL, text=True, encoding="utf-8",
            creationflags=subprocess.CREATE_NO_WINDOW,
        )
        self.replies = queue.Queue()
        self.next_id = 0

        def read():
            for line in self.process.stdout:
                self.replies.put(json.loads(line))

        threading.Thread(target=read, daemon=True).start()

    def request(self, method, payload=None):
        self.next_id += 1
        self.process.stdin.write(json.dumps({"id": self.next_id, "method": method, "payload": payload or {}}) + "\n")
        self.process.stdin.flush()
        reply = self.replies.get(timeout=25)
        assert reply["id"] == self.next_id, "Host response ID mismatch"
        if "error" in reply:
            raise RuntimeError(reply["error"]["code"])
        return reply.get("result")

    def close(self):
        if self.process.poll() is None:
            self.process.stdin.close()
            try:
                self.process.wait(timeout=8)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=3)
                raise
        self.process.stdout.close()


def core_pid(parent_pid):
    """Find only the sing-box process owned by this particular test host."""
    class Entry(ctypes.Structure):
        _fields_ = [
            ("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
            ("th32ProcessID", wintypes.DWORD), ("th32DefaultHeapID", ctypes.c_size_t),
            ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
            ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", wintypes.LONG),
            ("dwFlags", wintypes.DWORD), ("szExeFile", wintypes.WCHAR * 260),
        ]
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    kernel.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    handle = kernel.CreateToolhelp32Snapshot(2, 0)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        entry = Entry()
        entry.dwSize = ctypes.sizeof(entry)
        valid = kernel.Process32FirstW(handle, ctypes.byref(entry))
        while valid:
            if entry.th32ParentProcessID == parent_pid and entry.szExeFile.lower() == "sing-box.exe":
                return entry.th32ProcessID
            valid = kernel.Process32NextW(handle, ctypes.byref(entry))
    finally:
        kernel.CloseHandle(handle)
    raise AssertionError("Owned core process not found")


def terminate(pid):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(1, False, pid)
    if not handle:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        if not kernel.TerminateProcess(handle, 1):
            raise ctypes.WinError(ctypes.get_last_error())
    finally:
        kernel.CloseHandle(handle)


def listener_closed(port):
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=0.2):
            return False
    except OSError:
        return True


class Origin(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b"RainLink real Windows host verification"
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


def run(args):
    before = proxy_snapshot()
    origin = ThreadingHTTPServer(("127.0.0.1", 0), Origin)
    origin_target = f"127.0.0.1:{origin.server_port}"
    traversed = []

    class Forwarder(BaseHTTPRequestHandler):
        def do_CONNECT(self):
            if not args.egress and self.path != origin_target:
                self.send_error(502)
                return
            target = self.path.rsplit(":", 1)
            try:
                with socket.create_connection((target[0].strip("[]"), int(target[1])), timeout=8) as remote:
                    self.send_response(200, "Connection Established")
                    self.end_headers()
                    traversed.append(self.path)
                    deadline = time.monotonic() + 30
                    while time.monotonic() < deadline:
                        ready, _, _ = select.select([self.connection, remote], [], [], 0.5)
                        for source in ready:
                            data = source.recv(65536)
                            if not data:
                                return
                            (remote if source is self.connection else self.connection).sendall(data)
            except OSError:
                # A cancelled probe closes its socket while this fixture relays it.
                return

        def log_message(self, *unused):
            pass

    upstream = ThreadingHTTPServer(("127.0.0.1", 0), Forwarder)
    for server in (origin, upstream):
        threading.Thread(target=server.serve_forever, daemon=True).start()
    reports = []
    try:
        for scenario in ("disconnect", "stdin_eof", "core_crash", "host_crash"):
            host = Host(args.host)
            connected = None
            try:
                hello = host.request("hello")
                assert hello["protocolVersion"] == 2
                cipher = host.request("protect", {"id": "runtime-fixture", "username": "fixture-user", "password": "fixture-password"})["cipher"]
                connected = host.request("connect", {
                    "node": {"id": "runtime-fixture", "name": "Local verification", "revision": 1,
                             "protocol": "http", "server": "127.0.0.1", "port": upstream.server_port,
                             "credential": cipher},
                    "mode": "global", "systemProxy": True,
                })
                assert connected["phase"] == "connected"
                # A second handshake is harmless while a session is running.
                host.request("hello")
                active_proxy = proxy_snapshot()
                assert active_proxy["ProxyEnable"][0] == 1
                assert active_proxy["ProxyServer"][0] == f"127.0.0.1:{connected['proxyPort']}"
                client = http.client.HTTPConnection("127.0.0.1", connected["proxyPort"], timeout=8)
                try:
                    client.request("GET", f"http://{origin_target}/verify")
                    response = client.getresponse()
                    assert response.status == 200
                    assert response.read() == b"RainLink real Windows host verification"
                finally:
                    client.close()
                assert origin_target in traversed
                observed = host.request("snapshot")
                assert observed["telemetry"]["uploadTotal"] > 0
                assert observed["telemetry"]["downloadTotal"] > 0
                report = {"scenario": scenario, "coreVersion": hello["coreVersion"], "realTransfer": True}
                if args.egress and scenario == "disconnect":
                    deadline = time.monotonic() + 28
                    while time.monotonic() < deadline:
                        observed = host.request("snapshot")
                        if observed["telemetry"].get("ip"):
                            break
                        time.sleep(0.4)
                    telemetry = observed["telemetry"]
                    assert telemetry.get("ip"), telemetry.get("probeError")
                    report["publicEgress"] = {
                        "ipObserved": True, "countryCode": telemetry["countryCode"],
                        "latencyMs": telemetry["latency"],
                    }
                if scenario == "disconnect":
                    host.request("disconnect")
                elif scenario == "stdin_eof":
                    host.close()
                elif scenario == "core_crash":
                    terminate(core_pid(host.process.pid))
                    eventually(lambda: host.request("snapshot")["phase"] == "idle")
                else:
                    host.process.kill()
                    host.process.wait(timeout=3)
                eventually(lambda: proxy_snapshot() == before)
                eventually(lambda: listener_closed(connected["proxyPort"]))
                report.update(exactProxyRestoration=True, listenerClosed=True)
                reports.append(report)
                print(json.dumps(report, ensure_ascii=False), flush=True)
            finally:
                host.close()
                eventually(lambda: proxy_snapshot() == before)
                if connected:
                    eventually(lambda: listener_closed(connected["proxyPort"]))
    finally:
        for server in (upstream, origin):
            server.shutdown()
            server.server_close()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps({"scenarios": reports}, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, default=ROOT / "build/host/rainlink-host.exe")
    parser.add_argument("--output", type=Path, default=ROOT / "build/windows-session-verification.json")
    parser.add_argument("--egress", action="store_true")
    run(parser.parse_args())
