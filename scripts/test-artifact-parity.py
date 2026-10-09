#!/usr/bin/env python3
"""Disposable bundle regressions; no installation, signing or app launch."""

import importlib.util
import plistlib
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "artifact_parity", Path(__file__).with_name("verify-artifact-parity.py")
)
parity = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parity)


class ArtifactParityTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.source = self.root / "Info.plist"
        self.metadata = {
            "CFBundleExecutable": "SystemPulse",
            "CFBundleIdentifier": "local.systempulse.monitor",
            "CFBundleShortVersionString": "1.7.2",
            "CFBundleVersion": "17",
        }
        self.source.write_bytes(plistlib.dumps(self.metadata))
        self.archive = self.root / "archive/SystemPulse.app"
        self.executable = self.archive / "Contents/MacOS/SystemPulse"
        self.executable.parent.mkdir(parents=True)
        self.executable.write_bytes(b"fixture executable")
        self.executable.chmod(0o755)
        self.icon = self.archive / "Contents/Resources/AppIcon.icns"
        self.icon.parent.mkdir()
        self.icon.write_bytes(b"fixture icon")
        (self.archive / "Contents/Info.plist").write_bytes(self.source.read_bytes())
        self.comparison = self.root / "comparison/SystemPulse.app"
        shutil.copytree(self.archive, self.comparison)

    def verify(self):
        parity.verify(self.source, self.archive, [self.comparison])

    def testMatchingBundleAndSemanticallyEqualPlistPass(self):
        # Serialization/key order need not match the source plist.
        (self.archive / "Contents/Info.plist").write_bytes(
            plistlib.dumps(self.metadata, fmt=plistlib.FMT_BINARY)
        )
        shutil.copyfile(
            self.archive / "Contents/Info.plist",
            self.comparison / "Contents/Info.plist",
        )
        self.verify()

    def testSameVersionButWrongBuildFails(self):
        self.metadata["CFBundleVersion"] = "16"
        (self.archive / "Contents/Info.plist").write_bytes(
            plistlib.dumps(self.metadata)
        )
        with self.assertRaisesRegex(ValueError, "CFBundleVersion"):
            self.verify()

    def testWrongPermissionIdentityFails(self):
        self.metadata["CFBundleIdentifier"] = "wrong.identity"
        (self.archive / "Contents/Info.plist").write_bytes(
            plistlib.dumps(self.metadata)
        )
        with self.assertRaisesRegex(ValueError, "CFBundleIdentifier"):
            self.verify()

    def testSameMetadataButStaleExecutableFails(self):
        (self.comparison / "Contents/MacOS/SystemPulse").write_bytes(
            b"older executable"
        )
        with self.assertRaisesRegex(ValueError, "Contents/MacOS/SystemPulse"):
            self.verify()

    def testMissingOrChangedResourcesFail(self):
        for missing in (False, True):
            with self.subTest(missing=missing):
                path = self.comparison / "Contents/Resources/AppIcon.icns"
                if missing:
                    path.unlink()
                else:
                    path.write_bytes(b"stale icon")
                with self.assertRaisesRegex(ValueError, "AppIcon.icns"):
                    self.verify()

    def testExtraPayloadFails(self):
        (self.comparison / "Contents/Resources/extra").write_bytes(b"unexpected")
        with self.assertRaisesRegex(ValueError, "extra"):
            self.verify()

    def testExecutableModeDifferenceFails(self):
        (self.comparison / "Contents/MacOS/SystemPulse").chmod(0o644)
        with self.assertRaisesRegex(ValueError, "Contents/MacOS/SystemPulse"):
            self.verify()

    def testSymlinksAreComparedWithoutFollowingThem(self):
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "not-bundle-payload").write_bytes(b"unrelated")
        for bundle in (self.archive, self.comparison):
            (bundle / "Contents/Resources/link").symlink_to(
                outside, target_is_directory=True
            )
        self.verify()
        link = self.comparison / "Contents/Resources/link"
        link.unlink()
        link.symlink_to(self.root / "different")
        with self.assertRaisesRegex(ValueError, "Resources/link"):
            self.verify()

    def testMissingExecutableOrIconFailsEvenWithoutComparisons(self):
        self.icon.unlink()
        with self.assertRaisesRegex(ValueError, "icon"):
            parity.verify(self.source, self.archive, [])
        self.icon.write_bytes(b"fixture")
        self.executable.chmod(0o644)
        with self.assertRaisesRegex(ValueError, "executable"):
            parity.verify(self.source, self.archive, [])

    def testMissingComparisonFailsClosed(self):
        with self.assertRaisesRegex(ValueError, "app bundle directory"):
            parity.verify(self.source, self.archive, [self.root / "missing.app"])


if __name__ == "__main__":
    unittest.main()
