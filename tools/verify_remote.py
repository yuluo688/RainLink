"""Opt-in verification of private remote providers; never accepts secrets in argv.

Enter one JSON object at the hidden prompt, with subscription and proxies fields.
Each proxy has server, port, username and password. No input is persisted. This
compares direct authenticated HTTP CONNECT with the actual Dart repositories,
Windows DPAPI, host and sing-box. Only redacted evidence is written to --output.
Optional storedNodes accepts existing encrypted host snapshots through the same
private input, to test connectivity when the subscription cannot be fetched.
"""
import argparse
import base64
import concurrent.futures
import getpass
import http.client
import ipaddress
import json
import os
from pathlib import Path
import socket
import ssl
import subprocess
import sys
import threading
import time

from verify_session import proxy_snapshot


ROOT = Path(__file__).resolve().parent.parent


def direct_proxy(proxy, index):
    result = {"alias": f"http-{index + 1}"}
    started = time.monotonic()
    stream = None
    try:
        stream = socket.create_connection((proxy["server"], proxy["port"]), timeout=12)
        token = base64.b64encode(
            f'{proxy["username"]}:{proxy["password"]}'.encode()).decode("ascii")
        stream.sendall((
            "CONNECT www.cloudflare.com:443 HTTP/1.1\r\n"
            "Host: www.cloudflare.com:443\r\n"
            f"Proxy-Authorization: Basic {token}\r\n\r\n"
        ).encode("ascii"))
        response = http.client.HTTPResponse(stream)
        response.begin()
        result["connectStatus"] = response.status
        if response.status != 200:
            result["httpsTransfer"] = False
            body = response.read(8192).decode("utf-8", errors="replace").lower()
            result["failureHints"] = [hint for hint in (
                "authentication", "unauthorized", "invalid request", "bad request",
                "blocked", "timeout", "bandwidth", "whitelist", "not allowed",
            ) if hint in body]
            if response.getheader("CF-Ray"):
                result["responseGateway"] = "cloudflare"
            return result
        stream = ssl.create_default_context().wrap_socket(
            stream, server_hostname="www.cloudflare.com")
        stream.sendall(("GET /cdn-cgi/trace HTTP/1.1\r\n"
                        "Host: www.cloudflare.com\r\n"
                        "User-Agent: RainLink/0.1\r\nConnection: close\r\n\r\n").encode())
        response = http.client.HTTPResponse(stream)
        response.begin()
        body = response.read(65537)
        if len(body) > 65536:
            raise ValueError("Response limit")
        fields = dict(line.split("=", 1) for line in body.decode().splitlines() if "=" in line)
        ipaddress.ip_address(fields["ip"])
        result.update(httpsStatus=response.status, httpsTransfer=response.status == 200,
                      egressIp=fields["ip"], countryCode=fields.get("loc"))
    except Exception as error:
        result.update(httpsTransfer=False, error=type(error).__name__)
    finally:
        if stream is not None:
            stream.close()
        result["durationMs"] = round((time.monotonic() - started) * 1000)
    return result


def main():
    for stream in (sys.stdout, sys.stderr):
        if hasattr(stream, 'reconfigure'):
            stream.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dart", required=True, type=Path)
    parser.add_argument("--host", type=Path, default=ROOT / "build/host/rainlink-host.exe")
    parser.add_argument("--sqlite-dir", type=Path,
                        default=ROOT / "app/build/windows/x64/runner/Release")
    parser.add_argument("--output", type=Path, default=ROOT / "build/remote-verification.json")
    parser.add_argument("--max-seconds", type=int, default=600)
    args = parser.parse_args()
    try:
        config = json.loads(getpass.getpass("Private test JSON (hidden): "))
    except (ValueError, EOFError, KeyboardInterrupt):
        print("Private input cancelled or invalid", file=sys.stderr)
        return 64
    if (not isinstance(config, dict) or not isinstance(config.get("proxies"), list)
            or len(config["proxies"]) > 16 or not 30 <= args.max_seconds <= 1800):
        print("Invalid verification options", file=sys.stderr)
        return 64
    config["host"] = str(args.host.resolve())
    before = proxy_snapshot()
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        direct = list(pool.map(lambda pair: direct_proxy(pair[1], pair[0]),
                               enumerate(config.get("proxies", []))))
    print(json.dumps({"event": "provider-direct", "results": direct}), flush=True)
    env = os.environ.copy()
    env["PATH"] = str(args.sqlite_dir.resolve()) + os.pathsep + env.get("PATH", "")
    process = subprocess.Popen(
        [str(args.dart.resolve()), "run", "tool/verify_remote.dart"],
        cwd=ROOT / "app", env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, encoding="utf-8",
        creationflags=subprocess.CREATE_NO_WINDOW,
    )
    diagnostic_seen = threading.Event()

    def drain_diagnostics():
        for chunk in iter(lambda: process.stderr.read(4096), ""):
            if chunk:
                diagnostic_seen.set()

    reader = threading.Thread(target=drain_diagnostics, daemon=True)
    reader.start()
    expired = threading.Event()

    def expire():
        if process.poll() is None:
            expired.set()
            process.kill()

    watchdog = threading.Timer(args.max_seconds, expire)
    watchdog.daemon = True
    watchdog.start()
    report = {"direct": direct}
    try:
        # stdin is inherited privately; the payload never enters the process argv.
        process.stdin.write(json.dumps(config) + "\n")
        process.stdin.close()
        for line in process.stdout:
            try:
                value = json.loads(line)
            except ValueError:
                # Toolchain diagnostics are retained only as an exit code.
                continue
            print(json.dumps(value, ensure_ascii=False), flush=True)
            if value.get("event") == "report":
                report["rainlink"] = value
        process.wait(timeout=15)
    finally:
        watchdog.cancel()
        if process.poll() is None:
            process.kill()
            process.wait(timeout=8)
        process.stdout.close()
        reader.join(timeout=5)
        process.stderr.close()
    report["exitCode"] = process.returncode
    report["timedOut"] = expired.is_set()
    report["exactSystemProxyPreserved"] = proxy_snapshot() == before
    report["passed"] = (process.returncode == 0 and not expired.is_set()
                        and report.get("rainlink", {}).get("passed") is True
                        and all(item.get("httpsTransfer") for item in direct)
                        and report["exactSystemProxyPreserved"])
    if diagnostic_seen.is_set() and process.returncode:
        print("Dart verification failed; compiler/runtime diagnostics suppressed to protect inputs.",
              file=sys.stderr)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"event": "cleanup", "exitCode": process.returncode,
                      "exactSystemProxyPreserved": report["exactSystemProxyPreserved"]}), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
