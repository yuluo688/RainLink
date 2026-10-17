"""Verify Windows TUN capture and cleanup with a controlled local upstream.

Requires an elevated terminal; does not use user nodes/subscriptions or change
their database. The production TUN routes are exercised, so a separate watchdog
terminates only this test's host if the verification process fails or hangs.
"""
import argparse
import ctypes
from ctypes import wintypes
import hashlib
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import socket
import socketserver
import struct
import subprocess
import sys
import threading
import time

from verify_session import Host, ROOT, eventually, proxy_snapshot, terminate


def network_state():
    script = (
        "$ErrorActionPreference='Stop'; [ordered]@{"
        "adapters=@(Get-NetAdapter | Select-Object Name,InterfaceDescription,InterfaceIndex);"
        "routes=@(Get-NetRoute -PolicyStore ActiveStore | Select-Object InterfaceIndex,DestinationPrefix,NextHop,RouteMetric,Protocol);"
        "dns=@(Get-DnsClientServerAddress | Select-Object InterfaceIndex,AddressFamily,ServerAddresses)"
        "} | ConvertTo-Json -Depth 6 -Compress")
    result = subprocess.run(["powershell", "-NoProfile", "-NonInteractive", "-Command", script],
                            check=True, capture_output=True, text=True, encoding="utf-8", timeout=20)
    state = json.loads(result.stdout)
    return {key: sorted(value, key=lambda item: json.dumps(item, sort_keys=True)) for key, value in state.items()}


def fingerprint(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True).encode()).hexdigest()


def children(parent_id):
    class Entry(ctypes.Structure):
        _fields_ = [("dwSize", wintypes.DWORD), ("cntUsage", wintypes.DWORD),
                    ("th32ProcessID", wintypes.DWORD), ("th32DefaultHeapID", ctypes.c_size_t),
                    ("th32ModuleID", wintypes.DWORD), ("cntThreads", wintypes.DWORD),
                    ("th32ParentProcessID", wintypes.DWORD), ("pcPriClassBase", wintypes.LONG),
                    ("dwFlags", wintypes.DWORD), ("szExeFile", wintypes.WCHAR * 260)]
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.CreateToolhelp32Snapshot.restype = wintypes.HANDLE
    kernel.Process32FirstW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    kernel.Process32NextW.argtypes = [wintypes.HANDLE, ctypes.POINTER(Entry)]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.CreateToolhelp32Snapshot(2, 0)
    if handle == ctypes.c_void_p(-1).value:
        raise ctypes.WinError(ctypes.get_last_error())
    found = []
    try:
        entry = Entry()
        entry.dwSize = ctypes.sizeof(entry)
        valid = kernel.Process32FirstW(handle, ctypes.byref(entry))
        while valid:
            if entry.th32ParentProcessID == parent_id:
                found.append((entry.th32ProcessID, entry.szExeFile))
            valid = kernel.Process32NextW(handle, ctypes.byref(entry))
    finally:
        kernel.CloseHandle(handle)
    return found


def verified_process(pid, executable):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    handle = kernel.OpenProcess(0x1000 | 0x100000 | 1, False, pid)
    if not handle:
        return None
    buffer = ctypes.create_unicode_buffer(32768)
    size = wintypes.DWORD(len(buffer))
    if not kernel.QueryFullProcessImageNameW(handle, 0, buffer, ctypes.byref(size)):
        kernel.CloseHandle(handle)
        raise ctypes.WinError(ctypes.get_last_error())
    if Path(buffer.value).resolve() != executable.resolve():
        kernel.CloseHandle(handle)
        raise AssertionError("Watchdog target executable does not match test host")
    return kernel, handle


def watchdog(pid, executable):
    process = verified_process(pid, executable)
    if process is None:
        return
    kernel, handle = process
    try:
        if kernel.WaitForSingleObject(handle, 35000) == 0x102:
            if not kernel.TerminateProcess(handle, 1):
                raise ctypes.WinError(ctypes.get_last_error())
    finally:
        kernel.CloseHandle(handle)


def run(scenarios, executable=None, evidence_path=None):
    if not ctypes.windll.shell32.IsUserAnAdmin():
        raise RuntimeError("Run the controlled TUN verification from an elevated terminal")
    executable = executable or ROOT / "build/host/rainlink-host.exe"
    baseline = network_state()
    proxy_before = proxy_snapshot()
    evidence = {"environment": "Windows elevated local fixture", "realProviderTest": False,
                "before": {"network": fingerprint(baseline), "proxy": fingerprint(proxy_before)}, "scenarios": []}
    hits = []
    udp_hits = []
    dns_hits = []

    relay = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    relay.bind(("127.0.0.1", 0))
    relay.settimeout(0.25)
    dns = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    dns.bind(("127.0.0.1", 0))
    dns.settimeout(0.25)
    stopped = threading.Event()

    def relay_packets():
        while not stopped.is_set():
            try:
                data, address = relay.recvfrom(8192)
                if data[:4] == b"\0\0\0\1" and data[4:10] == socket.inet_aton("198.19.0.81") + struct.pack("!H", 18081):
                    udp_hits.append(time.monotonic())
                    relay.sendto(data[:10] + b"rainlink-udp-captured", address)
            except socket.timeout:
                continue

    def dns_packets():
        while not stopped.is_set():
            try:
                query, address = dns.recvfrom(4096)
                end = 12
                while end < len(query) and query[end]:
                    end += query[end] + 1
                end += 5
                if end > len(query):
                    continue
                answer = bytearray(query[:end])
                answer[2:4] = b"\x81\x80"
                answer[6:12] = b"\0\1\0\0\0\0"
                answer.extend(b"\xc0\x0c\0\1\0\1\0\0\0\x3c\0\4" + socket.inet_aton("203.0.113.88"))
                dns_hits.append(time.monotonic())
                dns.sendto(answer, address)
            except socket.timeout:
                continue

    class Socks(socketserver.StreamRequestHandler):
        def handle(self):
            self.connection.settimeout(10)
            try:
                greeting = self.rfile.read(2)
                if len(greeting) != 2 or greeting[0] != 5:
                    return
                self.rfile.read(greeting[1])
                self.wfile.write(b"\x05\0")
                command = self.rfile.read(4)
                if len(command) != 4:
                    return
                address_length = {1: 4, 4: 16}.get(command[3], 0)
                if command[3] == 3:
                    address_length = self.rfile.read(1)[0]
                self.rfile.read(address_length + 2)
                if command[1] != 3:
                    self.wfile.write(b"\x05\x07\0\x01" + b"\0" * 6)
                    return
                self.wfile.write(b"\x05\0\0\x01" + socket.inet_aton("127.0.0.1") + struct.pack("!H", relay.getsockname()[1]))
                self.wfile.flush()
                self.rfile.read(1)
            except (OSError, IndexError):
                return

    class SocksServer(socketserver.ThreadingTCPServer):
        daemon_threads = True

    socks = SocksServer(("127.0.0.1", 0), Socks)
    threads = [threading.Thread(target=relay_packets), threading.Thread(target=dns_packets),
               threading.Thread(target=socks.serve_forever)]
    for thread in threads:
        thread.start()

    class Proxy(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_CONNECT(self):
            if self.path != "198.19.0.80:18080":
                self.send_error(502)
                return
            self.connection.settimeout(4)
            self.send_response(200)
            self.end_headers()
            request = self.rfile.readline()
            while self.rfile.readline() not in (b"\r\n", b"\n", b""):
                pass
            if request.startswith(b"GET /rainlink-tun"):
                hits.append(time.monotonic())
                body = b"rainlink-tun-captured"
                self.wfile.write(b"HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: " + str(len(body)).encode() + b"\r\n\r\n" + body)
                self.wfile.flush()

    upstream = ThreadingHTTPServer(("127.0.0.1", 0), Proxy)
    threading.Thread(target=upstream.serve_forever, daemon=True).start()
    try:
        for scenario in scenarios:
            host = Host(executable)
            guard = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), "--watchdog", str(host.process.pid), str(executable)],
                                     creationflags=subprocess.CREATE_NO_WINDOW)
            item = {"name": scenario}
            try:
                host.request("hello")
                payload = {
                    "node": {"id": "tun-fixture", "name": "TUN 本机验收", "revision": 1,
                             "protocol": "socks" if scenario == "udp-dns" else "http", "server": "127.0.0.1",
                             "port": socks.server_address[1] if scenario == "udp-dns" else upstream.server_port,
                             "tls": False, "credential": "", "options": {}},
                    "mode": "global", "systemProxy": scenario == "coexist", "tun": True,
                    **({"runtimeSettings": {"proxyPort": 0, "dnsMode": "custom", "resolver": "udp://127.0.0.1:" + str(dns.getsockname()[1]),
                                            "bootstrapDns": "223.5.5.5", "ipv6": False, "logLevel": "info"}} if scenario == "udp-dns" else {})}
                if scenario == "cancel":
                    host.next_id += 2
                    first_id = host.next_id - 1
                    frames = [{"id": first_id, "method": "connect", "payload": payload},
                              {"id": host.next_id, "method": "cancel", "payload": {}}]
                    host.process.stdin.write("".join(json.dumps(frame) + "\n" for frame in frames))
                    host.process.stdin.flush()
                    reply = host.replies.get(timeout=10)
                    assert reply["id"] == first_id and reply.get("error", {}).get("code") == "cancelled"
                    assert host.replies.get(timeout=10)["id"] == host.next_id
                    host.request("disconnect")
                    assert host.request("snapshot")["phase"] == "idle"
                    item["queuedConnectCancelled"] = True
                else:
                    connected = host.request("connect", payload)
                if scenario == "cancel":
                    # The shared finally/restore check below still runs.
                    host.close()
                    guard.wait(timeout=8)
                    after = network_state()
                    assert after == baseline and proxy_snapshot() == proxy_before
                    item.update({"networkRestored": True, "proxyRestored": True})
                    evidence["scenarios"].append(item)
                    print(json.dumps(item, ensure_ascii=False), flush=True)
                    continue
                assert connected["tun"] and connected["tunInterface"].startswith("RainLink-")
                before_hits = len(hits)
                # No HTTP/SOCKS proxy: this socket can reach the synthetic origin
                # only by entering the actual production TUN and selected node.
                if scenario == "udp-dns":
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                        client.settimeout(4)
                        client.sendto(b"rainlink-udp", ("198.19.0.81", 18081))
                        assert client.recvfrom(4096)[0] == b"rainlink-udp-captured"
                    query = b"\x52\x4c\x01\0\0\x01\0\0\0\0\0\0\x07example\x03com\0\0\x01\0\x01"
                    before_dns = len(dns_hits)
                    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as client:
                        client.settimeout(4)
                        client.sendto(query, ("198.19.0.53", 53))
                        answer = client.recvfrom(4096)[0]
                        assert answer[:2] == query[:2] and answer[-4:] == socket.inet_aton("203.0.113.88")
                    assert len(dns_hits) > before_dns and udp_hits
                    item.update({"unproxiedUdpCaptured": True, "dnsInterceptedByRuntimePolicy": True})
                else:
                    connection = http.client.HTTPConnection("198.19.0.80", 18080, timeout=4)
                    try:
                        connection.request("GET", "/rainlink-tun")
                        response = connection.getresponse()
                        assert response.status == 200 and response.read() == b"rainlink-tun-captured"
                    finally:
                        connection.close()
                    assert len(hits) == before_hits + 1
                    item.update({"unproxiedTcpCaptured": True, "fixtureRequests": 1})
                guardian_ids = [pid for pid, name in children(host.process.pid)
                                if name.lower() == "rainlink-host.exe" and
                                any(child_name.lower() == "sing-box.exe" for _, child_name in children(pid))]
                assert len(guardian_ids) == 1, "Expected exactly one owned elevation guardian"
                core_ids = [pid for pid, name in children(guardian_ids[0]) if name.lower() == "sing-box.exe"]
                assert len(core_ids) == 1, "Expected exactly one guarded core"
                if scenario == "host-crash":
                    host.process.kill()
                    host.process.wait(timeout=5)
                elif scenario == "guardian-crash":
                    terminate(guardian_ids[0])
                    eventually(lambda: host.request("snapshot")["phase"] == "idle", timeout=8)
                elif scenario == "core-crash":
                    terminate(core_ids[0])
                    eventually(lambda: host.request("snapshot")["phase"] == "idle", timeout=8)
                elif scenario == "eof":
                    host.close()
                else:
                    host.request("disconnect")
                    assert host.request("snapshot")["phase"] == "idle"
                item.update({"tunConfirmed": True, "singleGuardedCore": True})
            except Exception:
                if host.process.poll() is None:
                    diagnostics = host.request("logs", {"stream": "", "after": 0})
                    (ROOT / "build/tun-last-failure.json").write_text(json.dumps(diagnostics, ensure_ascii=False, indent=2), encoding="utf-8")
                raise
            finally:
                host.close()
                guard.wait(timeout=8)
            after = network_state()
            assert after == baseline, "Network routes/adapters/DNS did not return to baseline"
            assert proxy_snapshot() == proxy_before, "System proxy did not return to baseline"
            item.update({"networkRestored": True, "proxyRestored": True})
            evidence["scenarios"].append(item)
            print(json.dumps(item, ensure_ascii=False), flush=True)
    finally:
        stopped.set()
        socks.shutdown()
        socks.server_close()
        for thread in threads:
            thread.join(timeout=3)
        relay.close()
        dns.close()
        upstream.shutdown()
        upstream.server_close()
        after = network_state()
        evidence["after"] = {"network": fingerprint(after), "proxy": fingerprint(proxy_snapshot())}
        evidence["passed"] = after == baseline and proxy_snapshot() == proxy_before and len(evidence["scenarios"]) == len(scenarios)
        destination = evidence_path or ROOT / "docs/verification/tun/windows-evidence.json"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--watchdog", nargs=2, metavar=("PID", "EXE"))
    parser.add_argument("--host", type=Path, help="Verify a packaged RainLink host instead of build/host")
    parser.add_argument("--evidence", type=Path, help="Write evidence to a separate run file")
    parser.add_argument("--scenario", choices=("disconnect", "coexist", "eof", "host-crash", "guardian-crash", "core-crash", "udp-dns", "cancel"), action="append")
    options = parser.parse_args()
    if options.watchdog:
        watchdog(int(options.watchdog[0]), Path(options.watchdog[1]))
    else:
        run(options.scenario or ["disconnect", "coexist", "eof", "host-crash", "guardian-crash", "core-crash", "udp-dns", "cancel"], options.host, options.evidence)
