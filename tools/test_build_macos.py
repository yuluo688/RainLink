"""Cross-platform regression checks for Mac staging, pinning and bundle guards.

Compiler/signing fixtures test orchestration only; they do not prove Swift
compilation, macOS execution or actual Keychain authorization.
"""

import json
from pathlib import Path
import plistlib
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build_macos as builder


def macho(arch="arm64"):
    return struct.pack("<IIIIIIII", 0xFEEDFACF, builder.CPU_TYPES[arch], 0, 2, 0, 0, 0, 0) + b"fixture"


class MacBuildTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="rainlink mac fixture ")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.arch = "arm64"
        self.calls = []
        self.inputs = ["tools/build_macos.py", "native/macos/keychain/main.swift",
                       "app/macos/Runner/Release.entitlements", "native/host/go.mod",
                       "native/host/go.sum", "native/host/cmd/rainlink-host/main.go"]
        for name in self.inputs:
            path = self.root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("fixture " + name, encoding="utf-8")
        native = self.root / "build/host/darwin-arm64"
        native.mkdir(parents=True)
        (native / "sing-box").write_bytes(macho())
        for name in builder.RESOURCES:
            (native / name).write_bytes(b"fixture " + name.encode())
        (self.root / "tools/core.lock.json").write_text(json.dumps({
            "goVersion": "fixture-toolchain", "additionalPlatforms": {"darwin-arm64": {
                "binarySha256": builder.digest(native / "sing-box"),
            }},
        }), encoding="utf-8")
        self.start_patch(patch.object(builder, "ROOT", self.root))
        self.start_patch(patch.object(builder.platform, "system", return_value="Darwin"))
        self.start_patch(patch.object(builder, "run", side_effect=self.command))

    def start_patch(self, value):
        value.start()
        self.addCleanup(value.stop)

    def command(self, arguments, **kwargs):
        args = [str(value) for value in arguments]
        self.calls.append((args, kwargs))
        if args[0] == "go":
            pinned = builder.digest(Path(args[args.index("-o") + 1]).parent / "sing-box")
            self.assertIn("signedDarwinCoreSHA256=" + pinned, args[args.index("-ldflags") + 1])
            self.assertEqual(kwargs["env"]["CGO_ENABLED"], "0")
            self.assertEqual(kwargs["env"]["GOARCH"], self.arch)
            Path(args[args.index("-o") + 1]).write_bytes(macho(self.arch) + pinned.encode())
        elif "swiftc" in args:
            self.assertIn("arm64-apple-macosx13.0", args)
            Path(args[args.index("-o") + 1]).write_bytes(macho(self.arch))
        elif args[0] == "/usr/bin/codesign" and "--sign" in args:
            self.assertEqual(args[args.index("--sign") + 1], "-")
            target = Path(args[-1])
            if target.is_file():
                target.write_bytes(target.read_bytes() + b"fixture signature")
        return subprocess.CompletedProcess(args, 0, stdout="/fixture SDK\n", stderr="")

    def app_fixture(self):
        app = self.root / "app/build/macos/Build/Products/Release/RainLink.app"
        contents = app / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "MacOS/RainLink").write_bytes(macho())
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": "dev.rainlink.rainlink", "CFBundleExecutable": "RainLink",
            "LSMinimumSystemVersion": "13.0",
        }))
        asset = self.root / "app/assets/icons/search.svg"
        asset.parent.mkdir(parents=True)
        asset.write_bytes(b"fixture icon")
        target = contents / "Frameworks/App.framework/Resources/flutter_assets/assets/icons/search.svg"
        target.parent.mkdir(parents=True)
        target.write_bytes(asset.read_bytes())
        return app

    def test_sign_before_pin_and_keep_unsigned_source_locked(self):
        original = (self.root / "build/host/darwin-arm64/sing-box").read_bytes()
        result = builder.prepare_runtime(self.arch)
        self.assertEqual(original, (self.root / "build/host/darwin-arm64/sing-box").read_bytes())
        self.assertNotEqual(result["unsignedCoreSha256"], result["signedCoreSha256"])
        self.assertEqual(result["signedCoreSha256"], result["files"]["sing-box"])
        commands = [args for args, _ in self.calls]
        sign_at = next(index for index, args in enumerate(commands)
                       if "--sign" in args and Path(args[-1]).name == "sing-box")
        go_at = next(index for index, args in enumerate(commands) if args[0] == "go")
        self.assertLess(sign_at, go_at)
        self.assertFalse(result["keychainExecuted"])
        self.assertFalse(any(Path(args[0]).name == "rainlink-keychain" for args in commands))
        builder.validate_runtime(self.arch)

    def test_stale_host_helper_signed_core_and_source_are_refused(self):
        builder.prepare_runtime(self.arch)
        for name in ("rainlink-host", "rainlink-keychain", "sing-box", "sing-box-source.zip"):
            with self.subTest(name=name):
                target = self.root / "build/macos/arm64/runtime" / name
                saved = target.read_bytes()
                target.write_bytes(saved + b"changed")
                with self.assertRaisesRegex(ValueError, "runtime changed"):
                    builder.validate_runtime(self.arch)
                target.write_bytes(saved)
        for name in ("native/host/cmd/rainlink-host/main.go", "native/macos/keychain/main.swift",
                     "app/macos/Runner/Release.entitlements"):
            with self.subTest(name=name):
                target = self.root / name
                saved = target.read_bytes()
                target.write_bytes(saved + b"changed")
                with self.assertRaisesRegex(ValueError, "inputs changed"):
                    builder.validate_runtime(self.arch)
                target.write_bytes(saved)

    def test_wrong_unsigned_core_is_refused_before_signing(self):
        (self.root / "build/host/darwin-arm64/sing-box").write_bytes(macho("amd64"))
        with self.assertRaisesRegex(ValueError, "source lock"):
            builder.prepare_runtime(self.arch)
        self.assertFalse(any(args[0] == "/usr/bin/codesign" for args, _ in self.calls))

    def test_bundle_preserves_exact_native_bytes_and_assets(self):
        result = builder.prepare_runtime(self.arch)
        app = self.app_fixture()
        bundle = builder.assemble_bundle(self.arch, app)
        self.assertEqual(bundle["packagedAssetsVerified"], 1)
        self.assertFalse(bundle["nativeExecutionVerified"])
        self.assertFalse(bundle["keychainAuthorizationVerified"])
        self.assertFalse(bundle["notarized"])
        for name in builder.IDENTIFIERS:
            self.assertEqual(result["files"][name], builder.digest(app / "Contents/MacOS" / name))
        app_sign = next(args for args, _ in self.calls if "--sign" in args and args[-1] == str(app))
        self.assertNotIn("--deep", app_sign)

    def test_stale_bundle_asset_and_external_bundle_are_refused(self):
        builder.prepare_runtime(self.arch)
        app = self.app_fixture()
        (self.root / "app/assets/icons/search.svg").write_bytes(b"new icon")
        with self.assertRaisesRegex(ValueError, "stale packaged"):
            builder.assemble_bundle(self.arch, app)
        with self.assertRaisesRegex(ValueError, "generated Flutter"):
            builder.assemble_bundle(self.arch, self.root)

    def test_non_mac_host_is_rejected_before_any_mutation(self):
        with patch.object(builder.platform, "system", return_value="Windows"):
            with self.assertRaisesRegex(ValueError, "require a Mac"):
                builder.prepare_runtime(self.arch)
        self.assertEqual(self.calls, [])
        self.assertFalse((self.root / "build/macos").exists())

    def test_signing_failure_prevents_runtime_and_success_evidence(self):
        command = self.command

        def fail_sign(arguments, **kwargs):
            if str(arguments[0]) == "/usr/bin/codesign":
                raise subprocess.CalledProcessError(1, arguments, stderr="fixture denial")
            return command(arguments, **kwargs)

        with patch.object(builder, "run", side_effect=fail_sign):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.prepare_runtime(self.arch)
        self.assertFalse((self.root / "build/macos/arm64/native-build.json").exists())
        self.assertFalse((self.root / "build/macos/arm64/runtime/rainlink-host").exists())

    def test_macho_architecture_and_truncation(self):
        binary = self.root / "fixture macho"
        for arch in ("arm64", "amd64"):
            binary.write_bytes(macho(arch))
            builder.verify_architecture(binary, arch)
            with self.assertRaisesRegex(ValueError, "Wrong Mach-O"):
                builder.verify_architecture(binary, "arm64" if arch == "amd64" else "amd64")
        for content in (b"", b"MZ" + bytes(50), b"\xca\xfe\xba\xbe" + struct.pack(">I", 2)):
            binary.write_bytes(content)
            with self.assertRaises(ValueError):
                builder.verify_architecture(binary, "arm64")


if __name__ == "__main__":
    unittest.main()
