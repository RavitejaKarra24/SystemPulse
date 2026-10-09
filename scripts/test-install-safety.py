#!/usr/bin/env python3
"""Installer fail-closed regressions; never touch the user's installed app."""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class InstallSafetyTests(unittest.TestCase):
    def check_refusal(self, process_status, expected_message):
        with tempfile.TemporaryDirectory(prefix="systempulse-install-test-") as directory:
            root = Path(directory)
            (root / "scripts").mkdir()
            (root / "dist" / "SystemPulse.app").mkdir(parents=True)
            script = root / "scripts" / "install-local.sh"
            shutil.copyfile(Path(__file__).with_name("install-local.sh"), script)
            commands = root / "commands"
            commands.mkdir()
            pgrep = commands / "pgrep"
            pgrep.write_text(f"#!/bin/sh\nexit {process_status}\n")
            pgrep.chmod(0o755)
            marker = root / "unexpected-action"
            for name in ["pkill", "kill", "rm", "mkdir", "ditto", "xattr", "plutil", "codesign", "open"]:
                command = commands / name
                command.write_text('#!/bin/sh\nprintf "%s\\n" "$0" >> "$INSTALL_TEST_MARKER"\nexit 99\n')
                command.chmod(0o755)
            environment = dict(os.environ)
            environment["PATH"] = str(commands) + os.pathsep + environment["PATH"]
            environment["INSTALL_TEST_MARKER"] = str(marker)
            result = subprocess.run(["/bin/bash", str(script)], env=environment, capture_output=True, text=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn(expected_message, result.stderr)
            self.assertFalse(marker.exists(), "Refusal must happen before signals, replacement or quarantine changes")

    def test_running_app_requires_normal_quit_before_any_mutation(self):
        self.check_refusal(0, "Quit SystemPulse normally")

    def test_process_query_error_does_not_authorize_replacement(self):
        self.check_refusal(2, "Could not verify that SystemPulse is stopped")

    def test_incomplete_source_preserves_the_installation(self):
        self.check_refusal(1, "Source bundle is incomplete")


if __name__ == "__main__":
    unittest.main()
