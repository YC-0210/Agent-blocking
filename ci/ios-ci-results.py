"""Reject incomplete Xcode runs and record each selected suite's results."""

import json
from pathlib import Path
import sys


def verify(results, expected):
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

    summary = read("test-summary.json")
    tree = read("test-tree.json")

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
    (results / "suite-results.json").write_text(json.dumps(report, indent=2) + "\n")
    for name, counts in suites.items():
        print(f"{name}: {counts['passed']}/{counts['expected']} passed; "
              f"{counts['failed']} failed; {counts['skipped']} skipped")
    for error in errors:
        print(error, file=sys.stderr)
    return not errors


if __name__ == "__main__":
    directory = Path(sys.argv[1])
    expected = {"ScheduleTests": int(sys.argv[2]), "UnlockRecoveryTests": int(sys.argv[3])}
    sys.exit(0 if verify(directory, expected) else 1)
