"""Render the recorded run into the GitHub job summary, including failed setup."""

import json
from pathlib import Path
import sys

results = Path(sys.argv[1])
print("## DO Card iOS CI\n")
print("Scope: `DoCardTests/ScheduleTests` and a Release simulator build.\n")
summary_path = results / "test-summary.json"
if summary_path.exists():
    try:
        summary = json.loads(summary_path.read_text())
        print("| Schedule tests | Count |\n|---|---:|")
        for label, key in [
            ("Discovered", "totalTestCount"),
            ("Passed", "passedTests"),
            ("Failed", "failedTests"),
            ("Skipped", "skippedTests"),
        ]:
            print(f"| {label} | {summary.get(key, 'Unavailable')} |")
    except (ValueError, OSError):
        print("The test summary could not be read. Check the uploaded logs.")
else:
    print("No test summary was produced. Check setup and build output in the logs.")

release_log = results / "release.log"
if release_log.exists():
    release_passed = "** BUILD SUCCEEDED **" in release_log.read_text(errors="replace")
    print(f"\nRelease simulator build: **{'passed' if release_passed else 'failed or incomplete'}**.")
else:
    print("\nRelease simulator build: **not reached**.")

overall = "passed" if (results / "ci-passed").exists() else "did not complete successfully"
print(f"\nThe complete pipeline **{overall}**.")
print("\nLogs and available `.xcresult` bundles are uploaded for 7 days.")
print("These checks do not verify actual iOS blocking or NFC hardware behaviour.")
