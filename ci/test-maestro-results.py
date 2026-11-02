"""Exercise false-green cases using the pinned Maestro JUnit schema."""

import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest
import xml.etree.ElementTree as ET
import sys

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("maestro_results", Path(__file__).with_name("maestro-results.py"))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class ResultGateTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.path = Path(self.temporary.name) / "report.xml"
        self.root = ET.Element("testsuites")
        self.suite = ET.SubElement(self.root, "testsuite", tests="4", failures="0")
        for name in sorted(gate.EXPECTED):
            ET.SubElement(self.suite, "testcase", name=name, status="SUCCESS")

    def check(self):
        ET.ElementTree(self.root).write(self.path)
        return gate.validate(self.path)

    def test_all_four_successes_pass(self):
        self.assertEqual(self.check()["count"], 4)

    def test_previous_five_flow_report_rejected(self):
        self.suite.clear()
        for name in ("navigation", "unpaid-recovery", "profile-persistence", "schedule-persistence", "report"):
            ET.SubElement(self.suite, "testcase", name=name, status="SUCCESS")
        with self.assertRaises(ValueError):
            self.check()

    def test_missing_report_rejected(self):
        with self.assertRaises(OSError):
            gate.validate(self.path)

    def test_malformed_report_rejected(self):
        self.path.write_text("<broken")
        with self.assertRaises(ET.ParseError):
            gate.validate(self.path)

    def test_missing_flow_rejected(self):
        self.suite.remove(self.suite[0])
        with self.assertRaises(ValueError):
            self.check()

    def test_duplicate_instead_of_missing_flow_rejected(self):
        self.suite[0].set("name", self.suite[1].get("name"))
        with self.assertRaises(ValueError):
            self.check()

    def test_extra_flow_rejected(self):
        ET.SubElement(self.suite, "testcase", name="unexpected", status="SUCCESS")
        with self.assertRaises(ValueError):
            self.check()

    def test_non_success_statuses_rejected_even_without_failure_element(self):
        original = copy.deepcopy(self.root)
        for status in ("ERROR", "WARNING", "PENDING", "RUNNING", "CANCELED", "STOPPED", "SKIPPED", ""):
            with self.subTest(status=status):
                self.root = copy.deepcopy(original)
                self.root[0][0].set("status", status)
                with self.assertRaises(ValueError):
                    self.check()

    def test_failure_error_and_skipped_elements_rejected(self):
        for tag in ("failure", "error", "skipped"):
            with self.subTest(tag=tag):
                child = ET.SubElement(self.suite[0], tag)
                with self.assertRaises(ValueError):
                    self.check()
                self.suite[0].remove(child)

    def test_nonzero_suite_failure_counters_rejected(self):
        for key in ("failures", "errors", "skipped", "disabled"):
            with self.subTest(key=key):
                self.suite.set(key, "1")
                with self.assertRaises(ValueError):
                    self.check()
                self.suite.set(key, "0")


if __name__ == "__main__":
    unittest.main()
