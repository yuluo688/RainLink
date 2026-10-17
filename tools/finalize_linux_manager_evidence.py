"""Bind managed Linux TUN host acceptance to raw observations and source hashes."""

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import re
import shutil

from finalize_linux_forwarding_evidence import ROOT, catalog, sha


SCENARIOS = [
    "no-service", "stop", "chain-rule", "system-proxy", "eof", "host-killed",
    "guardian-killed", "core-killed", "watchdog-killed", "stop-timeout",
    "route-loss", "permission-denied", "cancel-start", "bad-cipher",
]
NO_CAPTURE = {"no-service", "permission-denied", "cancel-start", "bad-cipher"}


def read(path):
    return path.read_text(encoding="utf-8-sig")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa", type=Path, default=ROOT / "build/qa/linux-manager")
    args = parser.parse_args()
    qa = args.qa.resolve()
    results = qa / "results"
    target = ROOT / "docs/verification/linux"
    target.mkdir(parents=True, exist_ok=True)

    suites = {path.name: catalog(path) for path in sorted(results.glob("*-tests.log"))}
    lifecycle = suites["manager-lifecycle-tests.log"]
    expected = {"TestIsolatedLinuxTUNManagerLifecycle/" + value for value in SCENARIOS}
    assert expected.issubset(set(lifecycle["passed"])), "missing managed host scenario"
    assert len(lifecycle["passed"]) == len(SCENARIOS) + 1

    for scenario in SCENARIOS:
        path = results / ("manager-" + scenario + "-state.json")
        record = json.loads(read(path))
        assert record["scenario"] == scenario and record["before"] == record["after"], path
        if scenario not in NO_CAPTURE:
            assert record["ready"] != record["before"], path
            observed = record["client"]
            connected, sample = observed["connected"], observed["observed"]
            assert connected["phase"] == sample["phase"] == "connected"
            assert connected["sessionId"] == sample["sessionId"]
            assert connected["tun"] and sample["tun"] and sample["mode"] == "global"
            assert sample["telemetry"]["uploadTotal"] > 0 and sample["telemetry"]["downloadTotal"] > 0
            assert observed["directChecks"] == observed["dnsChecks"] == 4
            assert observed["connections"]["sessionId"] == connected["sessionId"]
            if scenario == "chain-rule":
                assert connected["target"]["kind"] == "chain" and connected["ruleRevision"] == 9
                assert len(connected["routeBindings"]) == 3
            else:
                assert connected["node"]["id"] == "manager-entry" and not connected["node"]["credential"]
        for private in ["fixture-forward-password", '"apiSecret"', '"secrets"', "rls1."]:
            assert private not in read(path), (path, "private runtime data leaked")

    forwarding = json.loads(read(results / "manager-forwarding-state.json"))
    assert forwarding["beforeWire"] == forwarding["afterWire"]
    origins = forwarding["server"]
    assert origins["tcp4"] >= 10 and origins["tcp6"] >= 10
    assert origins["udp4"] >= 9 and origins["udp6"] >= 9
    assert origins["rejectedTcp"] == origins["rejectedUdp"] == 20 and origins["dnsQueries"] >= 40
    assert (results / "original-install-inputs-before.txt").read_bytes() == (results / "original-install-inputs-after.txt").read_bytes()
    for kind in ["links", "routes4", "routes6", "rules4", "rules6"]:
        assert (qa / ("parent-" + kind + "-before.txt")).read_bytes() == (qa / ("parent-" + kind + "-after.txt")).read_bytes()
    run = read(qa / "namespace-run.log")
    assert "Parent links/routes/rules unchanged. No fixture network namespace process remains." in run
    assert "Original authorizer and installed helper metadata/content unchanged." in run

    windows = [json.loads(line) for line in read(qa / "windows-go-tests.jsonl").splitlines()]
    assert not any(item["Action"] == "fail" for item in windows)
    windows_passed = [item for item in windows if item["Action"] == "pass" and "Test" in item]
    windows_skipped = [item["Test"] for item in windows if item["Action"] == "skip" and "Test" in item]
    assert len(windows_passed) == 164 and len(windows_skipped) == 3
    assert re.search(r"\+440: All tests passed!", read(qa / "flutter-tests.log"))
    checks = json.loads(read(qa / "checks.json"))
    assert checks and all(value["exitCode"] == 0 for value in checks.values())
    lock = json.loads(read(ROOT / "tools/core.lock.json"))
    assert sha(ROOT / "build/host/sing-box.exe") == lock["binarySha256"]
    assert sha(ROOT / "build/host/linux-amd64/sing-box") == lock["additionalPlatforms"]["linux-amd64"]["binarySha256"]

    artifacts = list(results.iterdir()) + [qa / "namespace-run.log", qa / "windows-go-tests.jsonl", qa / "flutter-tests.log", qa / "checks.json"]
    artifacts += list(qa.glob("parent-*.txt")) + list(qa.glob("vet-*.log"))
    artifacts += [qa / "bootstrap.sh", qa / "run_namespace.sh"]
    history = [qa / "attempt-1/manager-lifecycle-tests.log", qa / "attempt-2/manager-lifecycle-tests.log"]
    copied = []
    for path in sorted(artifacts):
        if not path.is_file():
            continue
        if path.name == "forwarding-state.json":
            name = "manager-private-forwarding-state.json"
        else:
            name = path.name if path.name.startswith("manager-") else "manager-" + path.name
        destination = target / name
        shutil.copyfile(path, destination)
        copied.append(destination)
    for index, path in enumerate(history, start=1):
        assert "--- FAIL:" in read(path)
        destination = target / ("manager-history-attempt-" + str(index) + ".log")
        shutil.copyfile(path, destination)
        copied.append(destination)

    test_catalog = target / "manager-tests.json"
    test_catalog.write_text(json.dumps(suites, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    copied.append(test_catalog)
    sources = sorted((ROOT / "native/host").rglob("*.go"))
    sources += sorted(path for path in (ROOT / "native/host/packaging/linux").iterdir() if path.is_file())
    sources += [ROOT / path for path in [
        "native/host/go.mod", "native/host/go.sum", "tools/core.lock.json",
        "tools/verify_linux_network.sh", "tools/fixtures/linux_network_namespace.sh",
        "tools/fixtures/linux_tun_manager_session.sh", "tools/finalize_linux_manager_evidence.py",
        "tools/finalize_linux_forwarding_evidence.py", "app/lib/platform/core/host_session_client.dart",
    ]]
    binaries = sorted(qa.glob("*.test")) + [qa / "rainlink-host", ROOT / "build/host/linux-amd64/sing-box", ROOT / "build/host/sing-box.exe"]
    runtime_inputs = sorted((qa / "packages").glob("*.apk"))
    rootfs = ROOT / "build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz"
    if rootfs.is_file():
        runtime_inputs.append(rootfs)
    evidence = {
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "scope": "isolated ordinary host + actual Secret Service + locked root TUN core; synthetic pkcheck, no systemd or real polkit prompt",
        "linuxPassEvents": sum(value["passEvents"] for value in suites.values()),
        "linuxTopLevelPassEvents": sum(value["topLevelPassEvents"] for value in suites.values()),
        "managerScenarios": SCENARIOS,
        "windowsPassEvents": len(windows_passed), "windowsSkipped": windows_skipped,
        "flutterTests": 440, "checks": checks,
        "originObservations": origins,
        "publicLinuxTUNCapability": False,
        "knownIssues": ["historical forwarding failure before expanded diagnostics remains unexplained; see linux-tun-forwarding.md"],
        "sources": {str(path.relative_to(ROOT)).replace("\\", "/"): sha(path) for path in sources},
        "runtimeInputs": {str(path.relative_to(ROOT)).replace("\\", "/"): sha(path) for path in runtime_inputs},
        "artifacts": {str(path.relative_to(ROOT)).replace("\\", "/"): sha(path) for path in copied + binaries},
    }
    destination = target / "manager-evidence.json"
    destination.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: evidence[key] for key in ["linuxPassEvents", "linuxTopLevelPassEvents", "windowsPassEvents", "flutterTests", "originObservations"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
