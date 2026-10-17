"""Opt-in real-node delay verification using existing encrypted local records.

Reads SQLite in read-only mode; private node snapshots reach an isolated host
only over stdin. No subscription URLs, credentials, server names or node names
are printed or saved. Does not change selection or system proxy settings.
"""
import argparse
import concurrent.futures
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import sqlite3

from verify_session import Host, ROOT, proxy_snapshot


def probe(node, host_path, index):
    report = {"alias": f"node-{index + 1}", "protocol": node["protocol"]}
    host = Host(host_path, isolated=True)
    try:
        result = host.request("testNode", node)
        report.update(passed=result.get("passed") is True,
                      failureCode=result.get("failureCode"), httpStatus=result.get("httpStatus"),
                      latencyMs=result.get("latency") if result.get("passed") else None,
                      resultRevisionMatched=(result.get("nodeId") == node["id"] and
                                             result.get("revision") == node["revision"]))
    except Exception as error:
        report.update(passed=False, errorType=type(error).__name__)
    finally:
        try:
            host.close()
            report["cleanedUp"] = True
        except Exception as error:
            report.update(cleanedUp=False, cleanupErrorType=type(error).__name__)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", type=Path, default=ROOT / "build/host/rainlink-host.exe")
    parser.add_argument("--database", type=Path,
                        default=Path(os.environ["APPDATA"]) / "dev.rainlink/rainlink/rainlink.sqlite")
    parser.add_argument("--protocol", choices=["http", "socks", "shadowsocks", "vless", "vmess", "trojan", "hysteria2", "tuic"], default="hysteria2")
    parser.add_argument("--count", type=int, choices=range(1, 9), default=3)
    parser.add_argument("--output", type=Path, default=ROOT / "build/real-node-probes.json")
    args = parser.parse_args()
    before = proxy_snapshot()
    database = sqlite3.connect(args.database.resolve().as_uri() + "?mode=ro", uri=True)
    database.row_factory = sqlite3.Row
    try:
        rows = database.execute(
            "SELECT id, name, revision, protocol, server, port, tls, options, credential "
            "FROM nodes WHERE protocol = ? ORDER BY name, id LIMIT ?",
            (args.protocol, args.count)).fetchall()
        nodes = [{**dict(row), "tls": bool(row["tls"]), "options": json.loads(row["options"])} for row in rows]
    finally:
        database.close()
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        futures = [pool.submit(probe, node, args.host.resolve(), index) for index, node in enumerate(nodes)]
        results = [future.result() for future in futures]
    preserved = proxy_snapshot() == before
    report = {"at": datetime.now(timezone.utc).isoformat(), "scenario": "existing encrypted provider nodes through isolated real core",
              "databaseReadOnly": True, "exactSystemProxyPreserved": preserved,
              "results": results, "passed": bool(results) and preserved and all(
                  result.get("passed") and result.get("resultRevisionMatched") and result.get("cleanedUp") for result in results)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report), flush=True)
    return 0 if report["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
