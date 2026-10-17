"""Exercise the shipped helper with a real Flutter release in disposable paths.

Only a copied EXE's CompanyName resource is changed, routing path_provider to a
fresh profile. The copied bundle uses a harmless fixture host, so these checks
cannot connect or restore a real network session. The production bundle and
the user's RainLink profile are never modified.
"""
import ctypes
from ctypes import wintypes
from contextlib import closing
import json
import os
from pathlib import Path
import queue
import re
import shutil
import sqlite3
import subprocess
import tempfile
import threading
import time
import uuid
import zipfile

from package_windows import digest

ROOT = Path(__file__).resolve().parent.parent
RELEASE = ROOT / "app/build/windows/x64/runner/Release"
EVIDENCE = ROOT / "docs/verification/app-update-recovery"
DATABASE_SCHEMA = int(re.search(
    r"int get schemaVersion => (\d+);",
    (ROOT / "app/lib/data/database/app_database.dart").read_text(encoding="utf-8"),
).group(1))


def isolated_company(executable, company):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.LoadLibraryExW.argtypes = [wintypes.LPCWSTR, wintypes.HANDLE, wintypes.DWORD]
    kernel.LoadLibraryExW.restype = wintypes.HMODULE
    kernel.FindResourceW.argtypes = [wintypes.HMODULE, ctypes.c_void_p, ctypes.c_void_p]
    kernel.FindResourceW.restype = wintypes.HANDLE
    kernel.LoadResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
    kernel.LoadResource.restype = wintypes.HANDLE
    kernel.LockResource.argtypes = [wintypes.HANDLE]
    kernel.LockResource.restype = ctypes.c_void_p
    kernel.SizeofResource.argtypes = [wintypes.HMODULE, wintypes.HANDLE]
    kernel.SizeofResource.restype = wintypes.DWORD
    kernel.FreeLibrary.argtypes = [wintypes.HMODULE]
    module = kernel.LoadLibraryExW(str(executable), None, 2)
    if not module:
        raise ctypes.WinError(ctypes.get_last_error())
    try:
        resource = kernel.FindResourceW(module, ctypes.c_void_p(1), ctypes.c_void_p(16))
        if not resource:
            raise ctypes.WinError(ctypes.get_last_error())
        loaded = kernel.LoadResource(module, resource)
        pointer = kernel.LockResource(loaded)
        data = ctypes.string_at(pointer, kernel.SizeofResource(module, resource))
    finally:
        kernel.FreeLibrary(module)
    original = "dev.rainlink\0".encode("utf-16-le")
    replacement = (company + "\0").encode("utf-16-le")
    assert len(original) == len(replacement) and data.count(original) == 1
    data = data.replace(original, replacement)
    kernel.BeginUpdateResourceW.argtypes = [wintypes.LPCWSTR, wintypes.BOOL]
    kernel.BeginUpdateResourceW.restype = wintypes.HANDLE
    kernel.UpdateResourceW.argtypes = [
        wintypes.HANDLE, ctypes.c_void_p, ctypes.c_void_p,
        wintypes.WORD, ctypes.c_void_p, wintypes.DWORD,
    ]
    kernel.EndUpdateResourceW.argtypes = [wintypes.HANDLE, wintypes.BOOL]
    update = kernel.BeginUpdateResourceW(str(executable), False)
    if not update:
        raise ctypes.WinError(ctypes.get_last_error())
    buffer = ctypes.create_string_buffer(data)
    if not kernel.UpdateResourceW(update, ctypes.c_void_p(16), ctypes.c_void_p(1),
                                   0x409, buffer, len(data)):
        error = ctypes.get_last_error()
        kernel.EndUpdateResourceW(update, True)
        raise ctypes.WinError(error)
    if not kernel.EndUpdateResourceW(update, False):
        raise ctypes.WinError(ctypes.get_last_error())


def wait_for(predicate, message, seconds=25):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.05)
    raise RuntimeError(message)


def windows():
    user = ctypes.WinDLL("user32", use_last_error=True)
    user.GetWindowThreadProcessId.argtypes = [wintypes.HWND, ctypes.POINTER(wintypes.DWORD)]
    user.GetClassNameW.argtypes = [wintypes.HWND, wintypes.LPWSTR, ctypes.c_int]
    user.IsWindowVisible.argtypes = [wintypes.HWND]
    result = []
    callback_type = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)

    @callback_type
    def collect(handle, _):
        process = wintypes.DWORD()
        user.GetWindowThreadProcessId(handle, ctypes.byref(process))
        name = ctypes.create_unicode_buffer(256)
        user.GetClassNameW(handle, name, len(name))
        if name.value == "FLUTTER_RUNNER_WIN32_WINDOW" and user.IsWindowVisible(handle):
            result.append((int(handle), process.value))
        return True

    user.EnumWindows(collect, 0)
    return result


def process_path(process_id):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.QueryFullProcessImageNameW.argtypes = [
        wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD),
    ]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    process = kernel.OpenProcess(0x1000, False, process_id)
    if not process:
        return None
    try:
        path = ctypes.create_unicode_buffer(32768)
        size = wintypes.DWORD(len(path))
        if not kernel.QueryFullProcessImageNameW(process, 0, path, ctypes.byref(size)):
            raise ctypes.WinError(ctypes.get_last_error())
        return Path(path.value).resolve()
    finally:
        kernel.CloseHandle(process)


def close_candidate(handle, process_id, executable, force_cleanup=False):
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
    kernel.OpenProcess.restype = wintypes.HANDLE
    kernel.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    process = kernel.OpenProcess(0x00100001, False, process_id)
    if not process:
        raise ctypes.WinError(ctypes.get_last_error())
    user = ctypes.WinDLL("user32", use_last_error=True)
    user.PostMessageW.argtypes = [wintypes.HWND, wintypes.UINT, wintypes.WPARAM, wintypes.LPARAM]
    try:
        if process_path(process_id) != executable.resolve():
            raise RuntimeError("Refusing to close a process outside the isolated installation")
        if not user.PostMessageW(handle, 0x0010, 0, 0):
            raise ctypes.WinError(ctypes.get_last_error())
        if kernel.WaitForSingleObject(process, 15000) != 0:
            if not force_cleanup:
                raise RuntimeError("Candidate did not exit normally")
            kernel.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
            if not kernel.TerminateProcess(process, 1):
                raise ctypes.WinError(ctypes.get_last_error())
            if kernel.WaitForSingleObject(process, 10000) != 0:
                raise RuntimeError("Isolated QA candidate could not be cleaned up")
    finally:
        kernel.CloseHandle(process)


def make_manifest(directory, version):
    files = sorted(path for path in directory.rglob("*")
                   if path.is_file() and path.name != "rainlink-bundle.json")
    result = {
        "schema": 2, "product": "RainLink", "platform": "windows-x64",
        "version": version, "files": [
            {"path": path.relative_to(directory).as_posix(),
             "bytes": path.stat().st_size, "sha256": digest(path)}
            for path in files
        ],
    }
    (directory / "rainlink-bundle.json").write_text(json.dumps(result), encoding="utf-8")


def status_reader(pipe, messages):
    for line in pipe:
        messages.put(line.strip())


def run_scenario(base, bundle, bundle_hash, fixture, version, company, scenario):
    scenario_root = base / scenario
    target = scenario_root / "installation"
    (target / "data").mkdir(parents=True)
    shutil.copy2(RELEASE / "rainlink.exe", target / "rainlink.exe")
    shutil.copy2(fixture, target / "rainlink-ui.exe")
    for name in ["rainlink-host.exe", "rainlink-updater.exe", "sing-box.exe",
                 "flutter_windows.dll", "data/app.so"]:
        (target / name).write_bytes(("previous-" + name).encode())
    make_manifest(target, "0.1.0+1")
    profile_root = Path(os.environ["APPDATA"]) / company
    support = profile_root / "rainlink"
    assert not profile_root.exists(), "Never reuse an existing profile"
    support.mkdir(parents=True)
    environment = dict(os.environ, RAINLINK_UPDATE_FIXTURE_SUPPORT=str(support))
    parent = None
    helper = None
    candidate = None
    before_windows = set(windows())
    result = {"scenario": scenario, "profileIsolated": True, "realFlutterAot": True,
              "hostIsHarmlessFixture": True, "productionBundleModified": False}
    try:
        if scenario == "rollback":
            # Minimal schema 5 supported by the actual Drift migration.
            with closing(sqlite3.connect(support / "rainlink.sqlite")) as db:
                db.executescript("""
                    CREATE TABLE preferences ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL);
                    CREATE TABLE nodes (id TEXT NOT NULL PRIMARY KEY);
                    CREATE TABLE node_groups (id TEXT NOT NULL PRIMARY KEY);
                    CREATE TABLE core_logs (id TEXT NOT NULL PRIMARY KEY);
                    CREATE TABLE node_overrides (node_id TEXT NOT NULL PRIMARY KEY);
                    PRAGMA user_version = 5;
                """)
                db.execute("INSERT INTO preferences VALUES (?, ?)",
                           ("appearance.preferences", '{"textSize":"invalid","reduceMotion":false}'))
                db.commit()
            original_database = digest(support / "rainlink.sqlite")
        parent = subprocess.Popen([str(target / "rainlink-ui.exe"), "--wait"],
                                  stdin=subprocess.PIPE, env=environment,
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        wait_for(lambda: (support / "parent-ready").exists(), "Parent fixture did not start")
        helper = subprocess.Popen([str(RELEASE / "rainlink-updater.exe")],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  stderr=subprocess.PIPE, text=True, env=environment,
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        messages = queue.Queue()
        threading.Thread(target=status_reader, args=(helper.stdout, messages), daemon=True).start()
        request = {
            "target": str(target), "support": str(support), "archive": str(bundle),
            "sha256": bundle_hash, "version": version, "parent": parent.pid,
        }
        helper.stdin.write(json.dumps(request) + "\n")
        helper.stdin.flush()
        assert messages.get(timeout=30) == '{"status":"ready"}'
        assert (target / "data/app.so").read_bytes() == b"previous-data/app.so"
        helper.stdin.write('{"command":"commit"}\n')
        helper.stdin.flush()
        assert messages.get(timeout=10) == '{"status":"committed"}'
        parent.stdin.close()
        parent.wait(timeout=10)
        helper.stdin.close()
        helper.wait(timeout=65)
        if scenario == "install":
            assert helper.returncode == 0
            # Helper has accepted the actual Flutter first frame and observed
            # its consumed receipt. The app is still alive in its new profile.
            candidate = wait_for(
                lambda: next(((handle, pid) for handle, pid in windows()
                              if (handle, pid) not in before_windows
                              and process_path(pid) == (target / "rainlink-ui.exe").resolve()), None),
                "Real Flutter candidate did not remain open")
            with closing(sqlite3.connect(support / "rainlink.sqlite")) as db:
                assert db.execute("PRAGMA user_version").fetchone()[0] == DATABASE_SCHEMA
                assert db.execute("SELECT count(*) FROM nodes").fetchone()[0] == 0
            subprocess.run(
                ["python", str(ROOT / "tools/capture_window.py"), "--pid", str(candidate[1]),
                 "--output", str(EVIDENCE / "actual-release-candidate-isolated.png")],
                cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
            result.update({"bootstrapAndFirstFrameAccepted": True,
                           "schema": DATABASE_SCHEMA, "nodes": 0, "candidateStayedOpen": True})
            close_candidate(*candidate, target / "rainlink-ui.exe")
            candidate = None
            result["normalExitObserved"] = True
        else:
            assert helper.returncode != 0  # The failed upgrade remains a failure.
            wait_for(lambda: (support / "previous-restarted").exists(),
                     "Previous application did not restart")
            receipt = json.loads((support / "update-result.json").read_text())
            assert receipt["status"] == "rolled-back"
            assert digest(support / "rainlink.sqlite") == original_database
            with closing(sqlite3.connect(support / "rainlink.sqlite")) as db:
                assert db.execute("PRAGMA user_version").fetchone()[0] == 5
            assert (target / "data/app.so").read_bytes() == b"previous-data/app.so"
            result.update({"actualBootstrapFailure": True, "previousProgramRestored": True,
                           "schemaBeforeAndAfter": 5, "databaseBytesRestored": True,
                           "previousRestartAcknowledged": True})
        assert not (target / ".rainlink-updating").exists()
        assert not (target / ".rainlink-update.json").exists()
        assert not list(scenario_root.glob(".rainlink-update-*"))
        assert not list(support.glob("update-backup-*"))
        result["transactionFilesCleaned"] = True
        return result
    finally:
        if parent is not None and parent.poll() is None:
            parent.stdin.close()
            parent.wait(timeout=10)
        if helper is not None and helper.poll() is None:
            # This is the exact helper Popen handle created by this test.
            helper.kill()
            helper.wait(timeout=10)
        # A timeout can occur before candidate is assigned. Match the executable
        # path as well as the window so cleanup never touches a user's app.
        for handle, process_id in windows():
            if process_path(process_id) == (target / "rainlink-ui.exe").resolve():
                close_candidate(handle, process_id, target / "rainlink-ui.exe", force_cleanup=True)
        # Retain disposable profiles as local QA evidence. Never recursively
        # delete an external profile from this verification tool.
        result["retainedQaProfile"] = company


def verify_prepared_recovery(base, staging, bundle, version, company):
    """Kill a prepared helper, then recover through the shipped entry and AOT."""
    target = base / "prepared-interruption" / "installation"
    shutil.copytree(staging, target)
    support = Path(os.environ["APPDATA"]) / company / "rainlink"
    assert not support.parent.exists(), "Never reuse an existing profile"
    helper = None
    launcher = None
    before = set(windows())
    try:
        parent = subprocess.Popen([str(target / "rainlink-ui.exe")],
                                  creationflags=subprocess.CREATE_NO_WINDOW)
        original = wait_for(
            lambda: next(((handle, pid) for handle, pid in windows()
                          if (handle, pid) not in before
                          and pid == parent.pid
                          and process_path(pid) == (target / "rainlink-ui.exe").resolve()), None),
            "Original isolated AOT window did not open")
        wait_for(lambda: (support / "rainlink.sqlite").exists(), "Isolated database did not initialize")
        helper = subprocess.Popen([str(RELEASE / "rainlink-updater.exe")],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                  text=True, creationflags=subprocess.CREATE_NO_WINDOW)
        helper.stdin.write(json.dumps({
            "target": str(target), "support": str(support), "archive": str(bundle),
            "sha256": digest(bundle), "version": version, "parent": parent.pid,
        }) + "\n")
        helper.stdin.flush()
        messages = queue.Queue()
        threading.Thread(target=status_reader, args=(helper.stdout, messages), daemon=True).start()
        assert messages.get(timeout=30) == '{"status":"ready"}'
        state = json.loads((target / ".rainlink-update.json").read_text())
        assert state["phase"] == "prepared"
        helper.kill()
        helper.wait(timeout=10)
        assert helper.returncode != 0 and (target / ".rainlink-update.json").exists()
        close_candidate(*original, target / "rainlink-ui.exe")
        parent.wait(timeout=10)
        launcher = subprocess.Popen([str(target / "rainlink.exe")],
                                    creationflags=subprocess.CREATE_NO_WINDOW)
        launcher.wait(timeout=25)
        assert launcher.returncode == 0
        resumed = wait_for(
            lambda: next(((handle, pid) for handle, pid in windows()
                          if (handle, pid) not in before
                          and pid != parent.pid
                          and process_path(pid) == (target / "rainlink-ui.exe").resolve()), None),
            "Recovery entry did not reopen the real Flutter AOT window")
        with closing(sqlite3.connect(support / "rainlink.sqlite")) as db:
            assert db.execute("PRAGMA user_version").fetchone()[0] == DATABASE_SCHEMA
            assert db.execute("SELECT count(*) FROM nodes").fetchone()[0] == 0
        assert not (target / ".rainlink-update.json").exists()
        assert not (target / ".rainlink-updating").exists()
        subprocess.run([
            "python", str(ROOT / "tools/capture_window.py"), "--pid", str(resumed[1]),
            "--output", str(EVIDENCE / "actual-release-recovered-isolated.png"),
        ], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        close_candidate(*resumed, target / "rainlink-ui.exe")
        assert not list(target.parent.glob(".rainlink-update-*"))
        return {"scenario": "prepared-helper-killed", "realFlutterAot": True,
                "actualHelperForcedExit": True, "automaticBootstrapRecovery": True,
                "schema": DATABASE_SCHEMA, "nodes": 0, "transactionFilesCleaned": True,
                "normalExitObserved": True, "retainedQaProfile": company,
                "profileIsolated": True, "hostIsHarmlessFixture": True,
                "productionBundleModified": False}
    finally:
        if helper is not None and helper.poll() is None:
            helper.kill()
            helper.wait(timeout=10)
        if launcher is not None and launcher.poll() is None:
            launcher.kill()
            launcher.wait(timeout=10)
        for handle, pid in windows():
            if process_path(pid) == (target / "rainlink-ui.exe").resolve():
                close_candidate(handle, pid, target / "rainlink-ui.exe", force_cleanup=True)


def main():
    if windows():
        raise RuntimeError("Close other RainLink windows before release update verification")
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rainlink-update-release-", dir=ROOT / "build") as name:
        base = Path(name).resolve()
        fixture = base / "fixture.exe"
        subprocess.run(
            ["go", "build", "-trimpath", "-o", str(fixture),
             "./internal/update/testdata/fixture.go"],
            cwd=ROOT / "native/host", check=True)
        offline_host = base / "offline-host.exe"
        subprocess.run(
            ["go", "build", "-trimpath", "-o", str(offline_host),
             "./internal/update/testdata/offline_host.go"],
            cwd=ROOT / "native/host", check=True)
        staging = base / "candidate"
        shutil.copytree(RELEASE, staging)
        shutil.copy2(offline_host, staging / "rainlink-host.exe")
        version = json.loads((RELEASE / "rainlink-bundle.json").read_text())["version"]
        results = []
        for scenario in ("install", "rollback"):
            company = "qa" + uuid.uuid4().hex[:10]
            shutil.copy2(RELEASE / "rainlink-ui.exe", staging / "rainlink-ui.exe")
            isolated_company(staging / "rainlink-ui.exe", company)
            make_manifest(staging, version)
            bundle = base / "candidate.zip"
            with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as output:
                for path in staging.rglob("*"):
                    if path.is_file():
                        output.write(path, path.relative_to(staging).as_posix())
            results.append(run_scenario(base, bundle, digest(bundle), fixture,
                                        version, company, scenario))
        company = "qa" + uuid.uuid4().hex[:10]
        shutil.copy2(RELEASE / "rainlink-ui.exe", staging / "rainlink-ui.exe")
        isolated_company(staging / "rainlink-ui.exe", company)
        make_manifest(staging, version)
        bundle = base / "prepared-candidate.zip"
        with zipfile.ZipFile(bundle, "w", zipfile.ZIP_DEFLATED) as output:
            for path in staging.rglob("*"):
                if path.is_file():
                    output.write(path, path.relative_to(staging).as_posix())
        results.append(verify_prepared_recovery(base, staging, bundle, version, company))
        report = {"version": version, "checks": results,
                  "officialGitHubReleaseUsed": False, "userDatabaseUsed": False}
        (EVIDENCE / "actual-release-update-evidence.json").write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8")
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
