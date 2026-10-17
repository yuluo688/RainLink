"""Bind permission log acceptance to isolated, real service, and source inputs."""

import argparse
import base64
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import struct

from finalize_linux_forwarding_evidence import ROOT, catalog, read, sha
from finalize_linux_manager_evidence import SCENARIOS


def digest_file(path, algorithm="sha256"):
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def confirm_network_aging(path):
    data = json.loads(read(path))
    before, after = data["before"], data["after"]
    expected = json.loads(json.dumps(before))
    assert len(before["Routes"]) == len(after["Routes"]), path
    minimum = max(0, data["elapsedMinNs"] // 10_000_000 - 2)
    maximum = data["elapsedMaxNs"] // 10_000_000 + 2
    aging = []
    for index, (left, right) in enumerate(zip(before["Routes"], after["Routes"])):
        assert len(left["Attributes"]) == len(right["Attributes"]), path
        for slot, (a, b) in enumerate(zip(left["Attributes"], right["Attributes"])):
            if a["Type"] != 12 or b["Type"] != 12:
                continue
            first, last = base64.b64decode(a["Value"]), base64.b64decode(b["Value"])
            if len(first) != 32 or len(last) != 32:
                continue
            old, new = struct.unpack_from("<i", first, 8)[0], struct.unpack_from("<i", last, 8)[0]
            if old == new == 0:
                continue
            assert old > 0 and new > 0 and minimum <= old - new <= maximum, path
            value = bytearray(first)
            struct.pack_into("<i", value, 8, new)
            expected["Routes"][index]["Attributes"][slot]["Value"] = base64.b64encode(value).decode()
            aging.append({"route": index, "destination": left["Destination"], "expiredTicks": old - new})
    assert expected == after, path
    return {"elapsedMinNs": data["elapsedMinNs"], "elapsedMaxNs": data["elapsedMaxNs"], "naturalRouteAging": aging}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa", type=Path, default=ROOT / "build/qa/linux-logs")
    parser.add_argument("--vm-results", type=Path, required=True)
    args = parser.parse_args()
    qa, vm = args.qa.resolve(), args.vm_results.resolve()
    for path in (qa, vm):
        path.relative_to(ROOT)
    destination = ROOT / "docs/verification/linux"
    destination.mkdir(exist_ok=True)
    artifacts = {}

    def record(path, name=None):
        if name:
            target = destination / ("logs-" + name)
            shutil.copyfile(path, target)
            path = target
        artifacts[path.relative_to(ROOT).as_posix()] = sha(path)

    results = qa / "results"
    suites = {path.name: catalog(path) for path in sorted(results.glob("*-tests.log"))}
    scenarios = [*SCENARIOS, "core-start-failure"]
    manager_cases = suites["manager-lifecycle-tests.log"]["passed"]
    assert all("TestIsolatedLinuxTUNManagerLifecycle/" + scenario in manager_cases for scenario in scenarios)
    assert suites["tun-logged-client-tests.log"]["passEvents"] == 21
    assert "TestLinuxTUNRouteAgingRetainsAllConfigurationFields" in suites["tun-plan-tests.log"]["passed"]
    for scenario in scenarios:
        data = json.loads(read(results / ("manager-" + scenario + "-state.json")))
        assert data["before"] == data["after"], scenario
    failure = json.loads(read(results / "manager-core-start-failure-state.json"))["client"]["startupFailureLogs"]
    assert any(entry["source"] == "core" and entry["level"] == "error" and "address already in use" in entry["message"] for entry in failure)
    stopped = json.loads(read(results / "manager-stop-state.json"))["client"]
    assert any(entry["source"] == "core" and "inbound/tun" in entry["message"] for entry in stopped["coreLogs"])
    assert any(entry["source"] == "core" and "managerafterclear" in entry["message"] for entry in stopped["postClearLogs"])
    assert (results / "original-install-inputs-before.txt").read_bytes() == (results / "original-install-inputs-after.txt").read_bytes()
    for kind in ("links", "routes4", "routes6", "rules4", "rules6"):
        assert (qa / f"parent-{kind}-before.txt").read_bytes() == (qa / f"parent-{kind}-after.txt").read_bytes()
    assert "No fixture network namespace process remains." in read(qa / "namespace-run.log")
    stress = catalog(qa / "log-unit-stress-final.log")
    assert stress["passEvents"] == 500 and stress["topLevelPassEvents"] == 100

    real = catalog(vm / "real-systemd-log-tests.log")
    assert real["passEvents"] == 3 and read(vm / "guest-result.txt").strip() == "0"
    guest_inputs = dict(line.split(maxsplit=1)[::-1] for line in read(vm / "guest-inputs.log").splitlines())
    for name in ("rainlink-host", "session.test", "sing-box"):
        assert guest_inputs["/opt/rainlink-qa/" + name] == sha(qa / "vm" / name), name
    for name in ("rainlink-host", "session.test"):
        assert sha(qa / name) == sha(qa / "vm" / name), name
    allow, deny = (json.loads(read(vm / f"native-client-{scenario}.log").splitlines()[0]) for scenario in ("allow", "deny"))
    assert any("sing-box started" in line for line in allow["messages"])
    assert any("inbound/tun" in line for line in allow["messages"])
    assert any("网络资源已恢复" in line for line in allow["messages"])
    assert any("系统授权已取消" in line for line in deny["messages"])
    journal = read(vm / "systemd-journal.log")
    for forbidden in ("fixture-systemd-password", "fixture-systemd-user", "sing-box started", "inbound/tun", "apiSecret", "Failed with result", "Failed to start"):
        assert forbidden not in journal, forbidden
    aging = {scenario: confirm_network_aging(vm / f"network-{scenario}.json") for scenario in ("allow", "deny")}
    assert all(len(value["naturalRouteAging"]) == 2 for value in aging.values())

    windows = [json.loads(line) for line in read(qa / "windows-regression-final.jsonl").splitlines()]
    assert not any(event["Action"] == "fail" for event in windows)
    windows_pass = [event for event in windows if event["Action"] == "pass" and "Test" in event]
    assert len(windows_pass) == 164
    checks = json.loads(read(qa / "checks.json"))
    assert checks and all(check["exitCode"] == 0 for check in checks.values())

    for path in sorted(results.iterdir()):
        if path.is_file():
            record(path, "network-" + path.name)
    for path in sorted(qa.glob("parent-*.txt")):
        record(path, path.name)
    for name in ("namespace-run.log", "log-unit-stress-final.log", "windows-regression-final.jsonl", "checks.json"):
        record(qa / name, name)
    for path in sorted(qa.glob("vet-*.log")):
        record(path, path.name)
    for path in sorted(vm.iterdir()):
        if path.is_file():
            record(path, "systemd-" + path.name)
    # Failed runs remain separate from the final accepted totals.
    for path in sorted((qa / "first-pass").rglob("*.log")) + sorted((qa / "first-pass").glob("*.jsonl")):
        record(path)
    for name in ("systemd-results-1792244438", "systemd-results-1792244666"):
        for path in sorted((qa / "vm" / name).iterdir()):
            if path.is_file():
                record(path)
    record(qa / "log-unit-stress.log")
    for path in sorted((qa / "vm").glob("bootstrap-*.log")):
        record(path)
    for path in sorted(qa.glob("*.test")) + sorted((qa / "vm").glob("*.test")):
        record(path)
    for path in (qa / "rainlink-host", qa / "vm/rainlink-host", qa / "vm/sing-box", ROOT / "build/host/sing-box.exe"):
        record(path)
    tests_path = destination / "logs-tests.json"
    tests_path.write_text(json.dumps({"network": suites, "logStress": stress, "realSystemdPolkit": real}, indent=2) + "\n", encoding="utf-8")
    record(tests_path)

    sources = list((ROOT / "native/host").rglob("*.go"))
    sources += [path for path in (ROOT / "native/host/packaging/linux").iterdir() if path.is_file()]
    sources += [ROOT / name for name in (
        "native/host/go.mod", "native/host/go.sum", "tools/core.lock.json", "tools/linux_systemd_qa.lock.json",
        "tools/verify_linux_network.sh", "tools/verify_linux_systemd_vm.sh", "tools/fixtures/linux_network_namespace.sh",
        "tools/fixtures/linux_tun_manager_session.sh", "tools/fixtures/linux_systemd_logs_guest.sh",
        "tools/finalize_linux_log_evidence.py", "tools/finalize_linux_forwarding_evidence.py", "tools/finalize_linux_manager_evidence.py",
    )]
    runtime_inputs = list((qa / "packages").glob("*.apk"))
    runtime_inputs += list((ROOT / "build/qa/linux-install/vm-cache/packages").glob("*.apk"))
    runtime_inputs += [ROOT / "build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz", ROOT / "build/qa/linux-install/systemd-overlay.qcow2",
                       ROOT / "build/qa/linux-install/vm-cache/debian-13-genericcloud-amd64.qcow2"]
    runtime_inputs += [qa / name for name in ("bootstrap.sh", "run_namespace.sh", "run_log_stress.sh")]
    runtime_inputs += [qa / "vm" / name for name in ("run_vm_namespace.sh", "vm-inner.sh", "vm-guest.sh", "user-data", "meta-data")]
    image = ROOT / "build/qa/linux-install/vm-cache/debian-13-genericcloud-amd64.qcow2"
    assert digest_file(image, "sha512") == json.loads(read(ROOT / "tools/linux_systemd_qa.lock.json"))["sha512"]
    evidence = {
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "networkPassEvents": sum(value["passEvents"] for value in suites.values()),
        "networkScope": "isolated namespaces, ordinary UID, actual Secret Service and core; fixture activation/authorization",
        "logStressPassEvents": stress["passEvents"], "logStressRunsPerTest": 20,
        "realSystemdPolkitPassEvents": real["passEvents"],
        "realSystemdPolkitScope": "Debian 13/systemd 257/polkitd 126; actual pkcheck, socket activation, root TUN core and allow/deny decisions using VM-only UID/action rules; no desktop authentication prompt",
        "realSystemdNetworkAging": aging,
        "windowsPassEvents": len(windows_pass),
        "windowsSkipped": [event["Test"] for event in windows if event["Action"] == "skip" and "Test" in event],
        "checks": checks, "publicLinuxTUN": False,
        "notVerified": ["active desktop polkit authentication", "time-namespace sandboxes", "GUI service management", "full Linux desktop and distribution", "arm64 execution", "macOS/iOS native services", "full Figma screen/modal audit"],
        "historicalFailures": ["monotonic clear approximation lost an immediately subsequent entry; replaced with direct kernel timestamps", "Windows fixture port allocator selected incompatible OS reservations; explicit TCP/UDP candidates fixed", "first two real VM assertions expected frozen RA lifetime bytes; full configuration comparison now verifies measured kernel aging", "PowerShell malformed direct test flag; no tests ran in that attempt"],
        "sourceSha256": {path.relative_to(ROOT).as_posix(): sha(path) for path in sorted(set(sources))},
        "runtimeInputSha256": {path.relative_to(ROOT).as_posix(): digest_file(path) for path in sorted(set(runtime_inputs))},
        "artifactSha256": artifacts,
    }
    output = destination / "logs-evidence.json"
    output.write_text(json.dumps(evidence, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"networkPassEvents": evidence["networkPassEvents"], "stressPassEvents": stress["passEvents"], "realServicePassEvents": real["passEvents"], "windowsPassEvents": len(windows_pass), "sourceFiles": len(evidence["sourceSha256"]), "runtimeInputs": len(evidence["runtimeInputSha256"]), "artifacts": len(artifacts)}, ensure_ascii=False))


if __name__ == "__main__":
    main()
