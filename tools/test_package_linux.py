"""Regression checks for Linux release bytes, paths and executable permissions."""

import hashlib
import json
import os
from pathlib import Path
import tarfile
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import package_linux as packaging


def elf_bytes(name):
    header = bytearray(20)
    header[:6] = b"\x7fELF\x02\x01"
    header[16:20] = b"\x03\x00\x3e\x00"
    return bytes(header) + name.encode()


class LinuxPackageTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="rainlink-linux-package-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        root_patch = patch.object(packaging, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)
        self.release = self.root / "release"
        for name in packaging.REQUIRED:
            target = self.release / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(elf_bytes(name) if target.name in packaging.EXECUTABLES or name.endswith(".so") else name.encode())
            if target.name in packaging.EXECUTABLES:
                target.chmod(0o755)
        with zipfile.ZipFile(self.release / "sing-box-source.zip", "w") as archive:
            archive.writestr("source/LICENSE", "fixture license")
        (self.root / "app").mkdir()
        (self.root / "app/pubspec.yaml").write_text("version: 0.1.0+4\n", encoding="utf-8")
        (self.root / "tools").mkdir()
        (self.root / "tools/core.lock.json").write_text(json.dumps({
            "additionalPlatforms": {"linux-amd64": {
                "version": "fixture", "binarySha256": packaging.digest(self.release / "sing-box"),
            }},
        }), encoding="utf-8")
        native = self.root / "build/host/linux-amd64"
        native.mkdir(parents=True)
        for name in ("rainlink-host", "rainlink-kde-proxy", "sing-box", "sing-box-LICENSE.txt", "sing-box-source.zip"):
            (native / name).write_bytes((self.release / name).read_bytes())
        self.sdk = self.root / "sdk"
        engine = self.sdk / "bin/cache/artifacts/engine/linux-x64-release/libflutter_linux_gtk.so"
        engine.parent.mkdir(parents=True)
        engine.write_bytes((self.release / "lib/libflutter_linux_gtk.so").read_bytes())
        for name, asset in [
            (packaging.ICON, "app/linux/runner/resources/rainlink.png"),
            (packaging.DESKTOP, "app/linux/packaging/" + packaging.DESKTOP),
            ("data/flutter_assets/assets/icons/search.svg", "app/assets/icons/search.svg"),
        ]:
            source = self.root / asset
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_bytes(name.encode())
            target = self.release / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source.read_bytes())

    def test_archive_has_identical_bytes_modes_and_repeatable_digest(self):
        first_path = self.root / "first.tar.xz"
        first = packaging.package(self.release, self.sdk, first_path)
        second = packaging.package(self.release, self.sdk, self.root / "second.tar.xz")
        self.assertEqual(first["sha256"], second["sha256"])
        self.assertTrue(first["permissionsVerified"])
        with tarfile.open(first_path, "r:xz") as archive:
            manifest = json.load(archive.extractfile("RainLink/" + packaging.MANIFEST))
            for item in manifest["files"]:
                member = archive.getmember("RainLink/" + item["path"])
                self.assertEqual(member.mode, int(item["mode"], 8))
                self.assertEqual(item["sha256"], hashlib.sha256(archive.extractfile(member).read()).hexdigest())
            self.assertEqual(archive.getmember("RainLink/rainlink").mode, 0o755)
            self.assertEqual(archive.getmember("RainLink/lib/libapp.so").mode, 0o644)

    def test_debug_engine_stale_host_core_and_assets_are_refused(self):
        for name in ("lib/libflutter_linux_gtk.so", "rainlink-host", "sing-box", packaging.ICON,
                     "data/flutter_assets/assets/icons/search.svg", "sing-box-source.zip"):
            with self.subTest(name=name):
                target = self.release / name
                saved = target.read_bytes()
                target.write_bytes(b"stale")
                with self.assertRaises(ValueError):
                    packaging.package(self.release, self.sdk)
                target.write_bytes(saved)
        self.assertFalse((self.release / packaging.MANIFEST).exists())

    def test_private_data_unknown_roots_and_missing_runtime_are_refused(self):
        for name in ("data/client.sqlite", ".rainlink-updating", "credentials.json"):
            with self.subTest(name=name):
                target = self.release / name
                target.write_bytes(b"private fixture")
                with self.assertRaises(ValueError):
                    packaging.package(self.release, self.sdk)
                target.unlink()
        for name in ("lib/libapp.so", "rainlink-kde-proxy"):
            with self.subTest(name=name):
                target = self.release / name
                saved = target.read_bytes()
                target.unlink()
                with self.assertRaisesRegex(ValueError, "Incomplete"):
                    packaging.package(self.release, self.sdk)
                target.write_bytes(saved)
                if target.name in packaging.EXECUTABLES:
                    target.chmod(0o755)

    def test_foreign_architecture_is_refused_even_with_a_matching_sdk(self):
        (self.release / "lib/libapp.so").write_bytes(b"\x7fELF\x02\x01" + bytes(10) + b"\x03\x00\xb7\x00")
        with self.assertRaisesRegex(ValueError, "Linux x64 ELF"):
            packaging.package(self.release, self.sdk)

    @unittest.skipIf(os.name == "nt", "POSIX executable bits require Linux")
    def test_missing_executable_permission_is_refused(self):
        (self.release / "rainlink").chmod(0o644)
        with self.assertRaisesRegex(ValueError, "permission"):
            packaging.package(self.release, self.sdk)

    @unittest.skipIf(os.name == "nt", "Unprivileged symlink test requires POSIX")
    def test_symlinks_are_refused(self):
        (self.release / "data/outside").symlink_to(self.root)
        with self.assertRaisesRegex(ValueError, "linked path"):
            packaging.package(self.release, self.sdk)

    def test_failed_verification_preserves_an_existing_archive(self):
        output = self.root / "release.tar.xz"
        output.write_bytes(b"previous archive")
        (self.release / "rainlink-host").write_bytes(b"stale")
        with self.assertRaises(ValueError):
            packaging.package(self.release, self.sdk, output)
        self.assertEqual(output.read_bytes(), b"previous archive")

    def test_output_inside_bundle_is_refused(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            packaging.package(self.release, self.sdk, self.release / "archive.tar.xz")


if __name__ == "__main__":
    unittest.main()
