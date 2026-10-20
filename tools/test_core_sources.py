"""Regression checks for non-root Linux builds from Go's read-only cache."""

from pathlib import Path
import stat
import tempfile
import unittest

from core_sources import copy_module_sources


class ModuleSourceTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="rainlink-module-")
        self.root = Path(self.temporary.name)
        self.source = self.root / "cache/module"
        (self.source / "option").mkdir(parents=True)
        (self.source / "option/tun.go").write_text("upstream", encoding="utf-8")
        for path in (self.source / "option", self.source):
            path.chmod(0o555)
        self.destination = self.root / "build/module"

    def tearDown(self):
        for path in self.root.rglob("*"):
            path.chmod(path.stat().st_mode | stat.S_IWUSR)
        self.temporary.cleanup()

    def test_read_only_module_can_receive_local_dependencies_and_patches(self):
        original_mode = self.source.stat().st_mode
        copy_module_sources(self.source, self.destination)
        dependency = self.destination / "rainlink-modules/sing-tun"
        dependency.mkdir(parents=True)
        (self.destination / "option/extension.go").write_text("extension", encoding="utf-8")
        (self.destination / "option/tun.go").write_text("patched", encoding="utf-8")
        self.assertEqual((self.source / "option/tun.go").read_text(), "upstream")
        self.assertEqual(self.source.stat().st_mode, original_mode)
        self.assertFalse((self.source / "rainlink-modules").exists())

    def test_retry_restores_upstream_files_and_keeps_directories_writable(self):
        copy_module_sources(self.source, self.destination)
        (self.destination / "option/tun.go").write_text("partial patch", encoding="utf-8")
        for path in (self.destination / "option", self.destination):
            path.chmod(0o555)
        copy_module_sources(self.source, self.destination)
        self.assertEqual((self.destination / "option/tun.go").read_text(), "upstream")
        for path in (self.destination / "option", self.destination):
            self.assertTrue(path.stat().st_mode & stat.S_IWUSR)
        (self.destination / "option/retry.go").write_text("retry", encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
