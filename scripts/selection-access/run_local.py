#!/usr/bin/env python3
"""Run the agreed Selection & access suites and reject missing/skipped test methods."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
FAST = ["SubscriptionAccessTests", "EntitlementsTests", "SelectionRulesTests",
        "SelectionEnforcementTests", "SubscriptionLifecycleTests", "SubscriptionStoreTests",
        "SubscriptionRefreshTests", "SettingsLayoutTests"]
STOREKIT = ["StoreKitAccessTests"]
PREVIOUS = ["ScheduleTests", "UnlockRecoveryTests", "SessionHistoryTests", "SessionReportTests",
            "SessionReportDurationTests", "Upgrade1301Tests"]


def leaves(node):
    if isinstance(node, dict):
        if node.get("nodeType") == "Test Case":
            yield node
        else:
            for value in node.values():
                yield from leaves(value)
    elif isinstance(node, list):
        for value in node:
            yield from leaves(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mode", choices=["fast", "storekit", "regression", "all"], default="fast")
    parser.add_argument("--simulator", required=True, help="Dedicated simulator UDID")
    parser.add_argument("--derived-data", type=Path, required=True)
    parser.add_argument("--results", type=Path, required=True, help="New results directory")
    args = parser.parse_args()
    suites = {"fast": FAST, "storekit": STOREKIT, "regression": FAST + PREVIOUS,
              "all": FAST + STOREKIT + PREVIOUS}[args.mode]
    expected = sorted(f"{suite}/{name}()" for suite in suites
                      for name in re.findall(r"func (test\w+)\(",
                          (ROOT / "DoCardTests" / f"{suite}.swift").read_text()))
    output = args.results.resolve()
    output.mkdir(parents=True, exist_ok=False)
    bundle = output / "tests.xcresult"
    command = ["xcodebuild", "test", "-project", "DoCard.xcodeproj", "-scheme", "DoCard",
               "-configuration", "Debug", "-destination", f"platform=iOS Simulator,id={args.simulator}",
               "-derivedDataPath", str(args.derived_data.resolve()), "-parallel-testing-enabled", "NO",
               "-maximum-concurrent-test-simulator-destinations", "1", "-jobs", "2",
               "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "30",
               "-maximum-test-execution-time-allowance", "30", "-resultBundlePath", str(bundle),
               "CODE_SIGNING_ALLOWED=NO"]
    command += [f"-only-testing:DoCardTests/{suite}" for suite in suites]
    (output / "command.json").write_text(json.dumps(command, indent=2) + "\n")
    started = time.monotonic()
    with (output / "xcodebuild.log").open("w") as log:
        process = subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT)
    wall = round(time.monotonic() - started, 3)
    summary, cases = {}, []
    if bundle.exists():
        for resource, filename in [("summary", "summary.json"), ("tests", "tests.json")]:
            result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", resource,
                                     "--path", str(bundle)], capture_output=True, text=True)
            if result.returncode == 0:
                data = json.loads(result.stdout)
                (output / filename).write_text(json.dumps(data, indent=2) + "\n")
                if resource == "summary":
                    summary = data
                else:
                    cases = list(leaves(data))
    actual = [case.get("nodeIdentifier") for case in cases]
    missing = sorted(set(expected) - set(actual))
    unexpected = sorted(set(actual) - set(expected))
    passed = (process.returncode == 0 and summary.get("result") == "Passed"
              and summary.get("passedTests") == len(expected)
              and summary.get("failedTests") == 0 and summary.get("skippedTests") == 0
              and not missing and not unexpected and len(actual) == len(expected)
              and all(case.get("result") == "Passed" for case in cases))
    report = {"passed": passed, "mode": args.mode, "simulator": args.simulator,
              "expectedCount": len(expected), "executedCount": len(actual),
              "wallSeconds": wall, "testBodySeconds": round(sum(
                  case.get("durationInSeconds", 0) for case in cases), 4),
              "missing": missing, "unexpected": unexpected,
              "cases": [{"id": c.get("nodeIdentifier"), "result": c.get("result"),
                         "seconds": c.get("durationInSeconds")} for c in cases]}
    (output / "verification.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "cases"}, indent=2))
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
