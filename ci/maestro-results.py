"""Reject missing, duplicate, skipped or failed smoke flows, even after a zero exit."""

from collections import Counter
import json
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

EXPECTED = {"manual-lock-unlock", "scheduled-lock-unlock", "scheduled-card-unlock", "emergency-unlock"}


def validate(path):
    root = ET.parse(path).getroot()
    cases = list(root.iter("testcase"))
    names = Counter(case.get("name") for case in cases)
    if names != Counter(EXPECTED):
        raise ValueError(f"Expected each of the four locking journeys exactly once; got {dict(names)}")
    for case in cases:
        if case.get("status") != "SUCCESS":
            raise ValueError(f"Flow is not SUCCESS: {case.get('name')} ({case.get('status')})")
        if any(case.find(tag) is not None for tag in ("failure", "error", "skipped")):
            raise ValueError(f"Flow did not pass: {case.get('name')}")
    for suite in root.iter("testsuite"):
        for key in ("failures", "errors", "skipped", "disabled"):
            if int(suite.get(key, "0")) != 0:
                raise ValueError(f"Nonzero {key} in report")
    return {"result": "passed", "count": len(cases), "flows": sorted(names)}


if __name__ == "__main__":
    try:
        result = validate(Path(sys.argv[1]))
    except (ValueError, OSError, ET.ParseError) as error:
        sys.exit(f"Maestro result gate failed: {error}")
    print(json.dumps(result, indent=2))
