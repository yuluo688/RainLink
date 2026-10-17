"""Bind install, real systemd and isolated network results to distinct inputs."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil

from finalize_linux_forwarding_evidence import ROOT, catalog, sha
from finalize_linux_manager_evidence import SCENARIOS


def read(path):
    return path.read_text(encoding="utf-8-sig")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa", type=Path, default=ROOT / "build/qa/linux-install")
    parser.add_argument("--network", type=Path, default=ROOT / "build/qa/linux-install-network")
    parser.add_argument("--vm-results", type=Path, required=True)
    args = parser.parse_args()
    qa, network, vm = (path.resolve() for path in (args.qa, args.network, args.vm_results))
    for path in (qa, network, vm):
        path.relative_to(ROOT)
    destination = ROOT / "docs/verification/linux"
    destination.mkdir(exist_ok=True)
    artifact_hashes = {}

    def record(path, output=None):
        if output:
            target = destination / ("install-" + output)
            shutil.copyfile(path, target)
            path = target
        artifact_hashes[path.relative_to(ROOT).as_posix()] = sha(path)

    suites = {path.name: catalog(path) for path in sorted(qa.glob("*-tests.log"))}
    crash_suite = suites["install-tests.log"]["passed"]
    prefix = "TestActualProcessKillIsRecoverableAtEveryCheckpoint/"
    crash_cases = [name for name in crash_suite if name.startswith(prefix)]
    assert len(crash_cases) == 30, "missing actual SIGKILL scenario"
    assert sum(value["passEvents"] for value in suites.values()) == 95
    real = catalog(vm / "real-systemd-tests.log")
    assert real["passed"] == ["TestRealSystemdInstallation"]
    assert read(vm / "guest-result.txt").strip() == "0"
    guest_inputs = dict(line.split(maxsplit=1)[::-1] for line in read(vm / "guest-inputs.log").splitlines())
    for name in ("rainlink-host", "linuxinstall.test", "sing-box"):
        assert guest_inputs["/opt/rainlink-qa/" + name] == sha(qa / name), "guest binary drift"
    for name in ("rainlink-host", "session.test", "linuxtun.test"):
        assert sha(qa / name) == sha(network / name), "network binary drift"
    journal = read(vm / "systemd-journal.log")
    assert "TUN exit cleanup skipped: another session remains active" in journal
    assert "Failed with result" not in journal and "Failed to start" not in journal
    assert "systemd 257" in read(vm / "cloud-output.log")
    network_suites = {path.name: catalog(path) for path in sorted((network / "results").glob("*-tests.log"))}
    passed_scenarios = network_suites["manager-lifecycle-tests.log"]["passed"]
    assert all("TestIsolatedLinuxTUNManagerLifecycle/" + name in passed_scenarios for name in SCENARIOS)
    for name in SCENARIOS:
        state = json.loads(read(network / "results" / ("manager-" + name + "-state.json")))
        assert state["before"] == state["after"], name
    for kind in ("links", "routes4", "routes6", "rules4", "rules6"):
        assert (network / ("parent-" + kind + "-before.txt")).read_bytes() == (network / ("parent-" + kind + "-after.txt")).read_bytes()
    assert "No fixture network namespace process remains." in read(network / "namespace-run.log")
    results = network / "results"
    assert (results / "original-install-inputs-before.txt").read_bytes() == (results / "original-install-inputs-after.txt").read_bytes()
    forwarding = json.loads(read(results / "manager-forwarding-state.json"))
    assert forwarding["beforeWire"] == forwarding["afterWire"]
    assert forwarding["server"]["tcp4"] >= 10 and forwarding["server"]["tcp6"] >= 10
    assert forwarding["server"]["udp4"] >= 9 and forwarding["server"]["udp6"] >= 9
    assert forwarding["server"]["dnsQueries"] >= 40
    windows = [json.loads(line) for line in read(qa / "windows-regression-retry.jsonl").splitlines()]
    assert not any(item["Action"] == "fail" for item in windows)
    windows_pass = [item for item in windows if item["Action"] == "pass" and "Test" in item]
    assert len(windows_pass) == 164
    checks = json.loads(read(qa / "checks.json"))
    assert checks and all(value["exitCode"] == 0 for value in checks.values())

    for path in sorted(qa.glob("*-tests.log")):
        record(path, path.name)
    for path in sorted(vm.iterdir()):
        if path.is_file():
            record(path, path.name)
    record(qa / "checks.json", "checks.json")
    record(qa / "windows-regression-retry.jsonl", "windows-go-tests.jsonl")
    for path in sorted(results.iterdir()):
        if path.is_file():
            record(path, "network-" + path.name)
    for path in sorted(network.glob("parent-*.txt")):
        record(path, "network-" + path.name)
    record(network / "namespace-run.log", "network-run.log")
    for path in sorted(qa.glob("vet-*.log")):
        record(path, path.name)
    for path in (qa / "windows-regression.jsonl", qa / "systemd-first-run/real-systemd-tests.log", qa / "systemd-results-1792241680/real-systemd-tests.log"):
        record(path, "history-" + path.parent.name + "-" + path.name)
    for path in sorted(qa.glob("vm-*-boot.log")):
        record(path)
    test_catalog = destination / "install-tests.json"
    test_catalog.write_text(json.dumps({"fixture": suites, "realSystemd": real, "network": network_suites}, indent=2) + "\n", encoding="utf-8")
    record(test_catalog)

    sources = sorted((ROOT / "native/host").rglob("*.go"))
    sources += [path for path in (ROOT / "native/host/packaging/linux").iterdir() if path.is_file()]
    sources += [ROOT / path for path in (
        "native/host/go.mod", "native/host/go.sum", "tools/core.lock.json", "tools/linux_systemd_qa.lock.json",
        "tools/verify_linux_install.sh", "tools/verify_linux_systemd_vm.sh", "tools/fixtures/linux_install_namespace.sh",
        "tools/fixtures/linux_systemd_guest.sh", "tools/finalize_linux_install_evidence.py",
        "tools/finalize_linux_forwarding_evidence.py", "tools/finalize_linux_manager_evidence.py",
        "tools/fixtures/linux_network_namespace.sh", "tools/fixtures/linux_tun_manager_session.sh",
    )]
    runtime_inputs = sorted((qa / "vm-cache/packages").glob("*.apk")) + sorted((network / "packages").glob("*.apk"))
    runtime_inputs += [ROOT / "build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz"]
    for name in ("bootstrap.sh", "run_namespace.sh"):
        runtime_inputs.append(network / name)
    for name in ("run_fixture.sh", "run_vm_namespace.sh", "vm-inner.sh", "vm-guest.sh", "user-data", "meta-data"):
        runtime_inputs.append(qa / name)
    runtime_inputs.append(qa / "vm-cache/debian-SHA512SUMS")
    image = qa / "vm-cache/debian-13-genericcloud-amd64.qcow2"
    image_digest = hashlib.sha512()
    with image.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            image_digest.update(chunk)
    lock = json.loads(read(ROOT / "tools/linux_systemd_qa.lock.json"))
    assert image_digest.hexdigest() == lock["sha512"]
    for path in list(qa.glob("*.test")) + list(network.glob("*.test")) + [qa / "rainlink-host", qa / "sing-box", network / "rainlink-host", ROOT / "build/host/sing-box.exe"]:
        record(path)
    evidence = {
        "recordedAt": datetime.now(timezone.utc).isoformat(),
        "fixturePassEvents": sum(value["passEvents"] for value in suites.values()),
        "actualSIGKILLScenarios": 30,
        "realSystemdPassEvents": real["passEvents"],
        "realSystemdScope": "Debian 13, Linux 6.12.113, systemd 257; actual install/upgrade/exit hook/uninstall/recovery; no polkit authentication request or captured TUN session",
        "networkPassEvents": sum(value["passEvents"] for value in network_suites.values()),
        "networkScope": "isolated ordinary UID host, Secret Service, actual TUN forwarding; fixture system activation and authorization",
        "windowsPassEvents": len(windows_pass),
        "windowsSkipped": [item["Test"] for item in windows if item["Action"] == "skip" and "Test" in item],
        "checks": checks,
        "publicLinuxTUN": False,
        "notVerified": ["active desktop polkit authentication", "GUI service management", "root core log transport", "physical power loss", "arm64 execution", "full Linux desktop and distribution"],
        "knownIssues": ["historical forwarding failure before expanded diagnostics remains unexplained; see linux-tun-forwarding.md"],
        "vmImage": {"path": image.relative_to(ROOT).as_posix(), "sha512": image_digest.hexdigest()},
        "sources": {path.relative_to(ROOT).as_posix(): sha(path) for path in sources},
        "runtimeInputs": {path.relative_to(ROOT).as_posix(): sha(path) for path in runtime_inputs},
        "artifacts": artifact_hashes,
    }
    (destination / "install-evidence.json").write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({key: evidence[key] for key in ("fixturePassEvents", "actualSIGKILLScenarios", "realSystemdPassEvents", "networkPassEvents", "windowsPassEvents")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
