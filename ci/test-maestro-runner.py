"""Exercise the real UI runner CLI without launching Apple tools or a simulator."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
FLOWS = ("manual-lock-unlock", "scheduled-card-unlock", "scheduled-lock-unlock", "emergency-unlock")


class MaestroRunnerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "DoCard.app"
        self.app.mkdir()
        (self.app / "Info.plist").write_text("fixture")
        self.results = self.root / "results"
        self.calls = self.root / "calls.jsonl"
        tools = self.root / "tools"
        tools.mkdir()
        header = f"#!{sys.executable}\nimport json,os,sys,time\nfrom pathlib import Path\n"
        scripts = {
            "xcodebuild": 'print("Xcode 26.2")',
            "java": 'print("fixture Java 17")',
            "xcrun": '''
with Path(os.environ['FIXTURE_CALLS']).open('a') as f:f.write(json.dumps(sys.argv[1:])+'\\n')
if 'runtimes' in sys.argv:
    print(json.dumps({'runtimes':[{'identifier':'com.apple.CoreSimulator.SimRuntime.iOS-26-2','isAvailable':True}]}))
elif 'create' in sys.argv:print('OWNED-SIMULATOR')
''',
            "maestro": '''
if '--version' in sys.argv:print('2.10.0')
else:
    report=Path(sys.argv[sys.argv.index('--output')+1])
    flows=json.loads(os.environ['FIXTURE_FLOWS'])
    cases=''.join('<testcase name="'+name+'" status="SUCCESS"/>' for name in flows)
    report.write_text('<testsuites><testsuite tests="4" failures="0">'+cases+'</testsuite></testsuites>')
    if os.environ.get('FIXTURE_HANG')=='yes':time.sleep(5)
''',
        }
        for name, body in scripts.items():
            p = tools / name
            p.write_text(header + body + "\n")
            p.chmod(0o755)
        self.env = dict(os.environ, PATH=str(tools)+os.pathsep+os.environ["PATH"],
                        FIXTURE_CALLS=str(self.calls), FIXTURE_FLOWS=json.dumps(FLOWS),
                        CI_SIMULATOR_RUNTIME="com.apple.CoreSimulator.SimRuntime.iOS-26-2")

    def invoke(self, **changes):
        return subprocess.run([sys.executable, "-B", str(ROOT / "ci/run-maestro.py"),
                               "--app", str(self.app), "--results", str(self.results)],
                              env=dict(self.env, **changes), capture_output=True, text=True, timeout=20)

    def test_complete_command_and_four_results_produce_success(self):
        result = self.invoke(MAESTRO_SUITE_TIMEOUT_SECONDS="900")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.results / "maestro-passed").is_file())

    def test_passing_report_cannot_override_command_timeout(self):
        result = self.invoke(MAESTRO_SUITE_TIMEOUT_SECONDS="1", FIXTURE_HANG="yes")
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue((self.results / "report.xml").is_file())
        self.assertFalse((self.results / "maestro-passed").exists())
        self.assertIn("timed out", (self.results / "runner.log").read_text())
        calls = [json.loads(line) for line in self.calls.read_text().splitlines()]
        self.assertIn(["simctl", "shutdown", "OWNED-SIMULATOR"], calls)
        self.assertIn(["simctl", "delete", "OWNED-SIMULATOR"], calls)

    def test_invalid_budget_is_rejected_before_any_device_command(self):
        for value in ("0", "901", "unbounded"):
            with self.subTest(value=value):
                result = self.invoke(MAESTRO_SUITE_TIMEOUT_SECONDS=value)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("from 1 to 900", result.stderr)
                self.assertFalse(self.calls.exists())
                self.assertFalse(self.results.exists())


if __name__ == "__main__":
    unittest.main()
