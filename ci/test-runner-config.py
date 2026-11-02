"""Exercise runner preflight through its shell entry point with controlled host tools."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class RunnerPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.xcode = self.root / "Selected Xcode.app/Contents/Developer"
        self.xcode.mkdir(parents=True)
        self.env = dict(os.environ, DOCARD_RUNNER_KIND="self-hosted",
                        GITHUB_ENV=str(self.root / "github-env"),
                        TEST_ACCOUNT="docardci", TEST_XCODE=str(self.xcode))
        self.env.pop("DOCARD_CI_XCODE_PATH", None)
        self.env.pop("CI_JOB_STAGE", None)
        scripts = {
            "id": 'print(os.environ["TEST_ACCOUNT"])',
            "uname": 'print("Darwin" if sys.argv[1] == "-s" else "arm64")',
            "xcode-select": 'print(os.environ["TEST_XCODE"])',
            "xcodebuild": 'print(os.environ.get("TEST_VERSION", "Xcode 26.2\\nBuild version 17C52"))',
            "xcrun": 'print(json.dumps({"runtimes": [{"identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-2", "isAvailable": os.environ.get("TEST_RUNTIME", "yes") == "yes"}]}))',
        }
        for name, body in scripts.items():
            path = self.root / name
            path.write_text(f"#!{sys.executable}\nimport os,sys,json\n{body}\n")
            path.chmod(0o755)
        self.env["PATH"] = str(self.root) + os.pathsep + os.environ["PATH"]

    def invoke(self, **changes):
        return subprocess.run(["/bin/bash", str(ROOT / "ci/prepare-ios-runner.sh")],
                              env=dict(self.env, **changes), text=True, capture_output=True)

    def test_self_hosted_refuses_development_account_before_export(self):
        result = self.invoke(TEST_ACCOUNT="chen")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("docardci", result.stderr)
        self.assertFalse((self.root / "github-env").exists())

    def test_selected_xcode_is_exported_for_later_steps(self):
        result = self.invoke()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "github-env").read_text(),
                         f"DEVELOPER_DIR={self.xcode}\n")

    def test_explicit_local_xcode_override_is_used(self):
        override = self.root / "Other Xcode.app/Contents/Developer"
        override.mkdir(parents=True)
        result = self.invoke(DOCARD_CI_XCODE_PATH=str(override))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.root / "github-env").read_text(),
                         f"DEVELOPER_DIR={override}\n")

    def test_wrong_xcode_version_cannot_reach_later_steps(self):
        result = self.invoke(TEST_VERSION="Xcode 26.1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Expected Xcode 26.2", result.stderr)
        self.assertFalse((self.root / "github-env").exists())

    def test_unavailable_runtime_cannot_reach_later_steps(self):
        result = self.invoke(TEST_RUNTIME="no")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("runtime is unavailable", result.stderr)
        self.assertFalse((self.root / "github-env").exists())

    def test_missing_xcode_override_is_rejected(self):
        result = self.invoke(DOCARD_CI_XCODE_PATH=str(self.root / "missing"))
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.root / "github-env").exists())

    def test_unknown_runner_kind_is_rejected(self):
        result = self.invoke(DOCARD_RUNNER_KIND="unknown")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported runner kind", result.stderr)
        self.assertFalse((self.root / "github-env").exists())

    def test_jobs_get_separate_results_under_runner_temp(self):
        for stage in ("core", "maestro"):
            with self.subTest(stage=stage):
                env_file = self.root / "github-env"
                env_file.unlink(missing_ok=True)
                result = self.invoke(CI_JOB_STAGE=stage, RUNNER_TEMP=str(self.root),
                                     GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="2")
                self.assertEqual(result.returncode, 0, result.stderr)
                values = dict(line.split("=", 1) for line in env_file.read_text().splitlines())
                self.assertEqual(values["CI_RESULTS_DIR"],
                                 str(self.root / f"docard-123-2/{stage}-results"))
                self.assertEqual(values["CI_BUILD_DIR"], str(self.root / "docard-123-2/core-build"))
                self.assertEqual(values["MAESTRO_APP_DIR"], str(self.root / "docard-123-2/app"))


if __name__ == "__main__":
    unittest.main()
