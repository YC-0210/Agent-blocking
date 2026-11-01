"""Render both suites and build status, including incomplete or failed runs."""

import json
from pathlib import Path
import sys

results = Path(sys.argv[1])
print("## DO Card iOS CI\n")
print("Scope: schedule + unlock/recovery tests in one simulator run, then Release compilation.\n")
try:
    report = json.loads((results / "suite-results.json").read_text())
    print("| Suite | Expected | Discovered | Passed | Failed | Skipped |\n|---|---:|---:|---:|---:|---:|")
    for name, counts in report["suites"].items():
        values = [counts[key] for key in ["expected", "discovered", "passed", "failed", "skipped"]]
        print(f"| {name} | " + " | ".join(map(str, values)) + " |")
    print(f"\nSuite validation: **{report['result']}**.")
    for error in report["errors"]:
        # A separate code block keeps arbitrary tool error text out of table markup.
        print("\n```text\n" + error.replace("```", "'''") + "\n```")
except (OSError, ValueError, KeyError, TypeError):
    print("No readable suite report was produced. Check setup and build output in the logs.")

release_log = results / "release.log"
if release_log.exists():
    release_passed = "** BUILD SUCCEEDED **" in release_log.read_text(errors="replace")
    print(f"\nRelease simulator build: **{'passed' if release_passed else 'failed or incomplete'}**.")
else:
    print("\nRelease simulator build: **not reached**.")

overall = "passed" if (results / "ci-passed").exists() else "did not complete successfully"
print(f"\nThe complete pipeline **{overall}**.")
print("\nLogs, per-suite results and available `.xcresult` bundles are uploaded for 7 days.")
print("These checks do not verify actual iOS blocking, NFC hardware, or process restart behaviour.")
