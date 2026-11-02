"""Reject incomplete Xcode runs and record each selected suite's results."""

import json
from pathlib import Path
import re
import sys


def verify(results, expected, summary_file="test-summary.json", tree_file="test-tree.json",
           report_file="suite-results.json", identifiers=None):
    errors = []
    suites = {
        name: {"expected": count, "discovered": 0, "passed": 0, "failed": 0, "skipped": 0}
        for name, count in expected.items()
    }
    seen = set()

    def read(name):
        try:
            value = json.loads((results / name).read_text())
            if not isinstance(value, dict):
                raise ValueError("expected a JSON object")
            return value
        except (OSError, ValueError) as error:
            errors.append(f"Cannot read {name}: {error}")
            return {}

    summary = read(summary_file)
    tree = read(tree_file)

    def visit(node, bundle=None, suite=None):
        kind = node.get("nodeType")
        if kind == "Unit test bundle":
            bundle = node.get("name")
        if kind == "Test Suite":
            suite = node.get("name")
        if kind == "Test Case":
            identifier = node.get("nodeIdentifier")
            if bundle != "DoCardTests" or suite not in suites:
                errors.append(f"Unexpected test: {bundle}/{suite}/{identifier}")
                return
            if not isinstance(identifier, str) or not identifier.startswith(suite + "/"):
                errors.append(f"Invalid test identifier: {identifier}")
            if identifiers is not None and identifier not in identifiers:
                errors.append(f"Unexpected test method: {identifier}")
            identity = (bundle, identifier)
            if identity in seen:
                errors.append(f"Duplicate test: {identity}")
            seen.add(identity)
            counts = suites[suite]
            counts["discovered"] += 1
            result = node.get("result")
            if result == "Passed":
                counts["passed"] += 1
            elif result == "Skipped":
                counts["skipped"] += 1
            else:
                counts["failed"] += 1
                errors.append(f"Test did not pass: {identifier} ({result})")
        for child in node.get("children", []):
            visit(child, bundle, suite)

    try:
        for node in tree.get("testNodes", []):
            visit(node)
    except (AttributeError, TypeError) as error:
        errors.append(f"Invalid test tree: {error}")
    for name, counts in suites.items():
        if not (
            counts["discovered"] == counts["expected"]
            and counts["passed"] == counts["expected"]
            and counts["failed"] == 0
            and counts["skipped"] == 0
        ):
            errors.append(f"{name}: expected {counts['expected']} passing tests; got {counts}")
    total = sum(expected.values())
    if not (
        summary.get("result") == "Passed"
        and summary.get("totalTestCount") == total
        and summary.get("passedTests") == total
        and summary.get("failedTests") == 0
        and summary.get("skippedTests") == 0
        and summary.get("expectedFailures") == 0
    ):
        errors.append(f"Expected {total} passed, none failed or skipped in Xcode summary")
    report = {"result": "Failed" if errors else "Passed", "suites": suites, "errors": errors}
    (results / report_file).write_text(json.dumps(report, indent=2) + "\n")
    for name, counts in suites.items():
        print(f"{name}: {counts['passed']}/{counts['expected']} passed; "
              f"{counts['failed']} failed; {counts['skipped']} skipped")
    for error in errors:
        print(error, file=sys.stderr)
    return not errors


def verify_upgrade(results, phases_dir):
    errors = []
    phases = {}
    try:
        executions = json.loads((phases_dir / "results.json").read_text())
        if not isinstance(executions, dict):
            raise ValueError("expected phase executions")
    except (OSError, ValueError) as error:
        executions = {}
        errors.append(f"Cannot read upgrade executions: {error}")
    method = "Upgrade1301Tests/testFirstReleaseSavedDataSurvivesUpdate()"
    for phase in ["migrate", "reopen"]:
        # Write validation beside the top-level reports even if setup produced no phase directory.
        prefix = str(phases_dir.relative_to(results) / phase)
        valid = verify(results, {"Upgrade1301Tests": 1}, prefix + "-summary.json",
                       prefix + "-tree.json", phase + "-validation.json", {method})
        if not valid:
            errors.append(f"{phase}: missing, incomplete or failed Xcode results")
        try:
            log = (phases_dir / (phase + ".log")).read_text(errors="replace")
        except OSError:
            log = ""
        markers = re.findall(r"UPGRADE1301_RESULT: phase=(\w+), pid=(\d+)", log)
        pid = None
        if len(markers) == 1 and markers[0][0] == phase and int(markers[0][1]) > 0:
            pid = int(markers[0][1])
        else:
            errors.append(f"{phase}: require one completion marker with the correct phase and process ID")
        execution = executions.get(phase, {})
        command_passed = (execution.get("exitCode") == 0 and execution.get("expectedFailure") is False
                          and pid is not None and execution.get("processID") == pid)
        if not command_passed:
            errors.append(f"{phase}: missing or unsuccessful process execution")
        phases[phase] = {"result": "Passed" if valid and command_passed else "Failed",
                         "processID": pid, "wallSeconds": execution.get("wallSeconds")}
    if phases["migrate"]["processID"] == phases["reopen"]["processID"]:
        errors.append("Reopen must run in a different process")
    report = {"result": "Failed" if errors else "Passed", "phases": phases,
              "uniqueTestMethods": 1, "requiredProcessChecks": 2, "errors": errors}
    (results / "upgrade-results.json").write_text(json.dumps(report, indent=2) + "\n")
    for error in errors:
        print(error, file=sys.stderr)
    return not errors


if __name__ == "__main__":
    directory = Path(sys.argv[1])
    if sys.argv[2] == "--upgrade":
        passed = verify_upgrade(directory, Path(sys.argv[3]))
    else:
        expected = {"ScheduleTests": int(sys.argv[2]), "UnlockRecoveryTests": int(sys.argv[3])}
        passed = verify(directory, expected)
    sys.exit(0 if passed else 1)
