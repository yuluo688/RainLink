"""Regression checks for the local Windows release packaging boundary."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import package_windows as packaging


class WindowsPackageTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="rainlink-package-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.patch = patch.object(packaging, "ROOT", self.root)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.release = self.root / "release"
        for name in packaging.REQUIRED:
            path = self.release / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(("fixture-" + name).encode())
        (self.root / "app").mkdir()
        (self.root / "app/pubspec.yaml").write_text("version: 0.1.0+2\n", encoding="utf-8")
        (self.root / "tools").mkdir()
        (self.root / "tools/core.lock.json").write_text(json.dumps({
            "version": "fixture", "binarySha256": packaging.digest(self.release / "sing-box.exe"),
        }), encoding="utf-8")
        for name in ["rainlink-host.exe", "rainlink-updater.exe", "rainlink.exe"]:
            target = self.root / "build/host" / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((self.release / name).read_bytes())
        self.sdk = self.root / "sdk"
        self.engine = self.sdk / "bin/cache/artifacts/engine/windows-x64-release/flutter_windows.dll"
        self.engine.parent.mkdir(parents=True)
        self.engine.write_bytes((self.release / "flutter_windows.dll").read_bytes())

    def test_digest_streams_more_than_one_chunk_on_python_38(self):
        content = bytes(range(256)) * 12000
        source = self.root / "large-file"
        source.write_bytes(content)
        self.assertEqual(packaging.digest(source), hashlib.sha256(content).hexdigest())

    def test_runtime_rejects_debug_engine_and_stale_native_binaries(self):
        self.assertTrue(packaging.verify_runtime(self.release, self.sdk)["releaseEngineVerified"])
        for name in ["flutter_windows.dll", "rainlink-host.exe", "rainlink-updater.exe", "rainlink.exe", "sing-box.exe"]:
            with self.subTest(file=name):
                path = self.release / name
                previous = path.read_bytes()
                path.write_bytes(b"different runtime")
                with self.assertRaises(ValueError):
                    packaging.verify_runtime(self.release, self.sdk)
                path.write_bytes(previous)

    def test_manifest_native_assets_and_identical_package_content(self):
        (self.release / "native_assets.yaml").write_text("native-assets: {}\n", encoding="utf-8")
        first = packaging.package(self.release, self.root / "first.zip")
        second = packaging.package(self.release, self.root / "second.zip")
        self.assertEqual(first["sha256"], second["sha256"])
        with zipfile.ZipFile(self.root / "first.zip") as bundle:
            manifest = json.loads(bundle.read(packaging.MANIFEST))
            self.assertEqual(manifest["schema"], 2)
            self.assertIn("rainlink-ui.exe", bundle.namelist())
            self.assertIn("native_assets.yaml", bundle.namelist())
            self.assertEqual(set(bundle.namelist()),
                             {item["path"] for item in manifest["files"]} | {packaging.MANIFEST})
            for item in manifest["files"]:
                self.assertEqual(item["sha256"], hashlib.sha256(bundle.read(item["path"])).hexdigest())

    def test_missing_updater_and_private_data_are_refused(self):
        (self.release / "data/local.sqlite").write_bytes(b"private fixture")
        with self.assertRaisesRegex(ValueError, "local data"):
            packaging.package(self.release)
        (self.release / "data/local.sqlite").unlink()
        for name in ("rainlink-updater.exe", "rainlink-ui.exe"):
            with self.subTest(file=name):
                path = self.release / name
                content = path.read_bytes()
                path.unlink()
                with self.assertRaisesRegex(ValueError, "Incomplete"):
                    packaging.package(self.release)
                path.write_bytes(content)

    def test_live_transaction_state_cannot_be_packaged(self):
        for name in [".rainlink-update.json", ".rainlink-updating", ".rainlink-update.lock", "native_assets.json"]:
            with self.subTest(file=name):
                path = self.release / name
                path.write_text("private update state", encoding="utf-8")
                with self.assertRaisesRegex(ValueError, "Unexpected release root"):
                    packaging.package(self.release)
                path.unlink()


if __name__ == "__main__":
    unittest.main()
