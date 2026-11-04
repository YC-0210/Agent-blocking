"""Shared selected portfolio and exact source method identities for iOS CI."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
DETERMINISTIC = (
    "OnboardingTrackingTests", "ScheduleTests", "UnlockRecoveryTests", "SessionHistoryTests", "SessionReportTests",
    "SessionReportDurationTests", "RetentionTimeCalculatorTests", "RetentionJournalTests", "RetentionCaptureTests", "RetentionUploadTests", "SubscriptionAccessTests", "EntitlementsTests",
    "SelectionRulesTests", "SelectionEnforcementTests", "SubscriptionLifecycleTests",
    "SubscriptionStoreTests", "SubscriptionRefreshTests", "SettingsLayoutTests",
    "AppUpdateTests", "AppUpdateNetworkTests",
)
STOREKIT = ("StoreKitAccessTests",)
GROUPS = {"deterministic": DETERMINISTIC, "storekit": STOREKIT}


def expected_methods(suites):
    expected, identifiers = {}, set()
    for suite in suites:
        source = (ROOT / "DoCardTests" / f"{suite}.swift").read_text()
        methods = re.findall(r"^\s*func (test\w+)\(\)", source, re.MULTILINE)
        if not methods or len(set(methods)) != len(methods):
            raise ValueError(f"Require nonempty, unique source methods for {suite}")
        expected[suite] = len(methods)
        identifiers.update(f"{suite}/{method}()" for method in methods)
    return expected, identifiers


if __name__ == "__main__":
    suites = GROUPS[sys.argv[1]]
    expected_methods(suites)  # Fail before xcodebuild if source selection is invalid.
    print("\n".join(f"-only-testing:DoCardTests/{suite}" for suite in suites))
