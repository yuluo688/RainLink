"""Bind isolated Linux TUN forwarding acceptance to raw results and sources."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil


ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read(path):
    return path.read_text(encoding="utf-8-sig")


def catalog(path):
    data = read(path)
    assert data.rstrip().endswith("PASS"), path
    assert not re.search(r"^\s*--- FAIL:|^FAIL$|panic:|fatal error:", data, re.M), path
    passed = re.findall(r"^\s*--- PASS: (\S+) \(", data, re.M)
    assert passed, path
    return {
        "passEvents": len(passed),
        "topLevelPassEvents": sum("/" not in name for name in passed),
        "passed": passed,
        "skipped": re.findall(r"^\s*--- SKIP: (\S+) \(", data, re.M),
        "sha256": sha(path),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--qa", type=Path, default=ROOT / "build/qa/linux-forwarding")
    args = parser.parse_args()
    qa = args.qa.resolve()
    # Evidence paths remain reviewable within this checkout.
    qa.relative_to(ROOT)
    output = ROOT / "docs/verification/linux"
    output.mkdir(parents=True, exist_ok=True)
    artifacts = {}

    def record(path, name=None):
        if name:
            destination = output / ("forwarding-" + name)
            shutil.copyfile(str(path), str(destination))
            path = destination
        artifacts[path.relative_to(ROOT).as_posix()] = sha(path)

    names = [
        "ordinary-tests", "lease-unit-tests", "process-tests", "ipc-tests",
        "ipc-root-tests", "managed-core-unit-tests", "tun-plan-tests", "removed-tests",
        "core-policy-tests", "lease-kernel-tests", "watchdog-kernel-tests",
        "permission-lifecycle-tests", "tun-native-client-tests",
        "tun-native-cancellation-tests", "tun-forwarding-tests",
    ]
    suites = {}
    for name in names:
        path = qa / "results" / (name + ".log")
        suites[name] = catalog(path)
        record(path, name + ".log")
    assert suites["tun-forwarding-tests"]["topLevelPassEvents"] == 3
    assert suites["tun-native-client-tests"]["passEvents"] == 66
    assert suites["tun-native-cancellation-tests"]["topLevelPassEvents"] == 20

    run = qa / "namespace-run.log"
    assert "Parent links/routes/rules unchanged. No fixture network namespace process remains." in read(run)
    record(run, "namespace-run.log")
    original_before = qa / "results/original-install-inputs-before.txt"
    original_after = qa / "results/original-install-inputs-after.txt"
    assert original_before.read_bytes() == original_after.read_bytes()
    assert "Original authorizer and installed helper metadata/content unchanged." in read(run)
    record(original_before, original_before.name)
    record(original_after, original_after.name)
    for kind in ["links", "routes4", "routes6", "rules4", "rules6"]:
        before = qa / ("parent-" + kind + "-before.txt")
        after = qa / ("parent-" + kind + "-after.txt")
        assert before.read_bytes() == after.read_bytes(), kind
        record(before, before.name)
        record(after, after.name)

    # Supplemental stress is deliberately separate from the complete fixture
    # totals; ordinary suites also run in those namespaces but are not counted
    # twice. These runs investigate the earlier unexplained forwarding failure.
    stress = ROOT / "build/qa/linux-forwarding-stress"
    supplemental = {}
    for rounds, directory in [(20, stress / "stress20"), (100, stress)]:
        log = directory / "results/tun-forwarding-stress-tests.log"
        supplemental[str(rounds)] = catalog(log)
        assert supplemental[str(rounds)]["topLevelPassEvents"] == rounds
        record(log, "stress-" + str(rounds) + "-tests.log")
        run_log = directory / "namespace-run.log"
        assert "Parent links/routes/rules unchanged. No fixture network namespace process remains." in read(run_log)
        assert "Original authorizer and installed helper metadata/content unchanged." in read(run_log)
        record(run_log, "stress-" + str(rounds) + "-namespace-run.log")
        for kind in ["links", "routes4", "routes6", "rules4", "rules6"]:
            before = directory / ("parent-" + kind + "-before.txt")
            after = directory / ("parent-" + kind + "-after.txt")
            assert before.read_bytes() == after.read_bytes()
            record(before, "stress-" + str(rounds) + "-" + before.name)
            record(after, "stress-" + str(rounds) + "-" + after.name)
    assert sha(stress / "session.test") == sha(qa / "session.test")
    for name in ["fixture.sh", "bootstrap.sh", "run_namespace.sh", "session.test"]:
        record(stress / name)

    snapshots = {}
    for path in sorted((qa / "results").glob("*-state.json")):
        state = json.loads(read(path))
        assert state["before"] == state["after"], path
        if path.name == "forwarding-state.json":
            assert state["beforeWire"] == state["afterWire"]
            client, server = state["client"], state["server"]
            assert client["dnsChecks"] == 8 and client["directRejected"] == 8
            connections = client["connections"]
            assert len(connections) == 4
            expected = {(network, host) for network in ["tcp", "udp"]
                        for host in ["203.0.113.9", "2001:db8:9::9"]}
            assert {(item["metadata"]["network"], item["metadata"]["destinationIP"])
                    for item in connections} == expected
            for item in connections:
                assert item["metadata"]["type"] == "tun/rainlink-tun"
                assert item["metadata"]["destinationPort"] == "20001"
                assert "proxy" in item["chains"] and item["upload"] > 0 and item["download"] > 0
            assert all(server[key] >= 1 for key in ["tcp4", "tcp6", "udp4", "udp6"])
            assert server["rejectedTcp"] == 4 and server["rejectedUdp"] == 4 and server["dnsQueries"] >= 8
            snapshots["forwarding"] = {
                "client": client, "server": server, "restoredExactly": True,
                "wireRestoredExactly": True,
            }
        else:
            snapshots[path.stem] = {"restoredExactly": True}
        record(path, "state.json" if path.name == "forwarding-state.json" else path.name)
    assert all("native-" + scenario + "-state" in snapshots for scenario in [
        "stop", "eof", "guardian-killed", "stop-timeout", "permission-denied", "cancel-start"])
    assert "forwarding" in snapshots

    status = json.loads(read(qa / "results/host-status.json"))
    assert status["capabilities"]["tun"] is False
    record(qa / "results/host-status.json", "host-status.json")
    windows_path = qa / "windows-tests.jsonl"
    events = [json.loads(line) for line in read(windows_path).splitlines() if line.strip()]
    assert not any(event["Action"] == "fail" for event in events)
    passed = [event["Test"] for event in events if event["Action"] == "pass" and "Test" in event]
    # The locked real Windows core must be present, not an all-skipped run.
    assert "TestLockedCoreMatchesCurrentPlatform" in passed
    assert "TestRealCoreRoutesAndLiveModeChanges" in passed
    windows = {
        "passEvents": len(passed),
        "topLevelPassEvents": sum("/" not in name for name in passed), "passed": passed,
        "skipped": [event["Test"] for event in events if event["Action"] == "skip" and "Test" in event],
    }
    record(windows_path)

    for name in ["linux-amd64-vet.log", "linux-arm64-vet.log", "windows-vet.log", "gofmt.txt", "shell-syntax.log"]:
        path = qa / name
        assert not read(path).strip(), name
        record(path)
    for name in ["linuxnet.test", "linuxtun.test", "linuxprocess.test", "linuxipc.test", "session.test", "managed-core.test", "rainlink-host"]:
        record(qa / name)
    for name in ["bootstrap.sh", "run_namespace.sh"]:
        if (qa / name).exists():
            record(qa / name)
    for path in sorted((qa / "packages").glob("*.apk")):
        record(path)
    rootfs = ROOT / "build/qa/linux/alpine-minirootfs-3.22.2-x86_64.tar.gz"
    if rootfs.exists():
        record(rootfs)
    lock = json.loads(read(ROOT / "tools/core.lock.json"))
    linux_core = ROOT / "build/host/linux-amd64/sing-box"
    windows_core = ROOT / "build/host/sing-box.exe"
    assert sha(linux_core) == lock["additionalPlatforms"]["linux-amd64"]["binarySha256"]
    assert sha(windows_core) == lock["binarySha256"]
    record(linux_core)
    record(windows_core)
    preview = ROOT / "build/RainLink-windows-x64-subscriptions-preview.zip"
    previous = json.loads(read(output / "permission-evidence.json"))
    assert sha(preview) == previous["artifacts"][preview.relative_to(ROOT).as_posix()]
    record(preview)
    # Preserve the real initial cancellation failure as history. It is not a
    # passing test suite and never contributes to the totals above.
    history = qa / "native-cancellation-race-before-fix.log"
    assert "native client lost its failure category" in read(history)
    record(history, "history-native-cancellation-before.log")
    intermittent = qa / "forwarding-intermittent-failure.log"
    assert "ordinary forwarding client did not confirm all traffic" in read(intermittent)
    record(intermittent, "history-intermittent-before-diagnostics.log")

    for path_name in artifacts:
        path = ROOT / path_name
        if path.suffix in [".log", ".json", ".jsonl"]:
            content = read(path)
            for secret in ["fixture-forward-password", "fixture-api-secret-only"]:
                assert secret not in content, path

    source_paths = list((ROOT / "native/host").rglob("*.go"))
    source_paths += [ROOT / "native/host/go.mod", ROOT / "native/host/go.sum",
                     ROOT / "tools/core.lock.json", ROOT / "tools/verify_linux_network.sh",
                     ROOT / "tools/fixtures/linux_network_namespace.sh", Path(__file__).resolve()]
    source_paths += [path for path in (ROOT / "native/host/packaging/linux").iterdir()
                     if path.suffix in [".socket", ".service", ".policy"]]
    sources = {path.relative_to(ROOT).as_posix(): sha(path) for path in sorted(source_paths)}
    tests = {"linuxNetwork": suites, "supplementalForwarding": supplemental, "windows": windows}
    tests_path = output / "forwarding-tests.json"
    tests_path.write_text(json.dumps(tests, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    record(tests_path)
    evidence = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "scope": "Native Linux TUN client and real TCP/UDP/DNS forwarding in disposable namespaces",
        "runtime": "Alpine 3.22.2 amd64 on WSL Linux 6.6.87.2; Go 1.25.5; peer pidfd requires Linux 6.5+",
        "authorization": {"fixtureAuthorizerOnly": True, "actualPolkitPromptTested": False,
                          "systemdActivationTested": False},
        "network": {"passEvents": sum(item["passEvents"] for item in suites.values()),
                    "topLevelPassEvents": sum(item["topLevelPassEvents"] for item in suites.values()),
                    "forwardingRounds": 3, "nativeLifecycleScenarios": 6,
                    "nativeLifecycleRounds": 3, "additionalCancellationRounds": 20,
                    "guardianScenarioRuns": 21, "watchdogScenarioRuns": 20,
                    "parentUnchanged": True, "namespaceProcessesRemaining": 0,
                    "originalInstallationUnchanged": True},
        "windows": {key: windows[key] for key in ["passEvents", "topLevelPassEvents"]},
        "supplementalForwarding": {"rounds": 120, "passed": 120, "parentUnchanged": True,
                                   "doesNotResolveEarlierUnexplainedFailure": True},
        "snapshots": snapshots, "capabilities": status["capabilities"],
        "nativeClient": {"ordinaryUID": 65534, "pinnedRootSocketTested": True,
                         "integratedIntoPublicManager": False},
        "knownIssues": ["One early forwarding failure lacks expanded child diagnostics; cause remains unconfirmed"],
        "notValidated": ["real polkit and desktop approval/refusal", "systemd and ExecStopPost",
                         "public Manager credential/session integration", "privileged core log transport",
                         "installer/updater/uninstaller", "public Internet IPv6 and provider TUN traffic",
                         "ARM64 runtime", "race detector", "full Figma UI and icon audit"],
        "sourceFiles": sources, "artifacts": artifacts,
    }
    target = output / "forwarding-evidence.json"
    target.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"evidence": target.relative_to(ROOT).as_posix(), "network": evidence["network"],
                      "windows": evidence["windows"], "sourceFiles": len(sources), "artifacts": len(artifacts)}))


if __name__ == "__main__":
    main()
