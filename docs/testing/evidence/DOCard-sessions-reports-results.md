# DO Card — Sessions & reports: recorded local results

This records the local implementation run before PR preparation. The pull request adds these suites to the existing CI gate; hosted results are reported separately.

Date: 2026-11-02, Asia/Taipei. Implemented in the current app working copy; CI work remains separate.

## Result

**15 new XCTest methods passed. The combined regression run passed 79 methods, zero failed and zero skipped.**
All executed method names were checked against the selected source declarations. There were no missing
cases. Debug and Release arm64 iOS Simulator builds both succeeded.

The 15 new methods cover the 13 agreed scenario groups. P7 has two independent test fixtures for its
cross-week and exact-boundary examples. P4 has one report integration method and one calculation method
that checks all five break input rows. Deferred P5/P6 are absent.

## What the new tests cover

| Group | Passing behavior |
|---|---|
| S1 | Same completed session imported twice: one saved record after save/reopen; original ID, times and profile links |
| S2 | Two different imports survive reopening with distinct IDs, exact times and correct links in both directions |
| S3 | An active record becomes completed under the same ID; no second record |
| S4 | Real foreground loader transfers pending completed history, clears the processed list, and does not activate it |
| S6 | Snapshot claiming an 08:00 start cannot change saved 09:00–09:30 history or its 30-minute elapsed duration |
| S7 | Emergency Unlock at 09:20 stays at 09:20 with its reason when a late timer claims 09:30 |
| S8 | Old active snapshot cannot erase the end time/reason of completed history |
| P1 | Empty report: zero total, count and average; finite average and empty ranking |
| P2 | Separate 30- and 20-minute sessions: 50 total, count two, average25; stable on two report loads |
| P3 | Completed30 plus active session: completed report total/count/average are30/1/30 |
| P4 integration | One hour with ten-minute break: total, average, profile total and current trend all show50 minutes |
| P4 calculation | No break60; internal break50; touching start50; touching end50; partly outside55 minutes |
| P7 | Sunday23:50–Monday00:20: all30 minutes stay in the starting week; zero in current week |
| P7 boundary | Separate database: Monday00:00–00:15 contributes15 to the new week and zero to earlier weeks |
| P8 | Work20+20, Study30, Reading20, Family10: overall100; top three Work40/Study30/Reading20 |

S5's persistence checks are included in the import cases. The existing R11 tests continue to own
manual-versus-scheduled control; the new suite does not recreate that sequence. P2 owns report arithmetic,
while S2 checks distinct imported records and their profile links.

## Observed failures before fixes

Each failing case ran before its fix; these are recorded failing XCTest assertions, not inferred failures.

| Case | Before | After |
|---|---|---|
| S7 | Emergency reason was preserved, but late timer changed end09:20→09:30 and duration20→30min | Saved ending remains09:20 and20min |
| S8 | Late active snapshot set end/reason to nil and reopened completed history | Completed history remains ended at09:20 with its card-tap reason |
| P4 | Total, average, profile total and weekly trend all included the break:60min | All four report50min |
| P7 | Weekly trend clipped Sunday23:50–Monday00:20 to10min in the old week | All30min assigned to starting week |

The initial S1–S4 and S6 checks passed without changes to their production behavior.

One filtered P8 attempt returned xcodebuild success with **zero executed tests**. That attempt is
excluded from the passing evidence. The subsequent complete new-suite run and final regression both
executed and passed the exact P8 method. Final result verification compares executed method identities,
per-suite counts, results and skip counts with source declarations.

## App code changes

1. `DoCard/Models/BlockedProfileSessions.swift`: before changing an already-ended row, ignore an old
   active snapshot, and preserve completed Emergency Unlock history against later snapshots. Existing
   ID-based import and authoritative-start behavior remain in use. Other completed-to-completed updates
   retain their existing behavior; this is not a universal event-order resolver.
2. `DoCard/Utils/SessionReportDuration.swift` (new): elapsed interval minus the intersection of a
   completed break with that interval. It changes report calculations, not saved timestamps.
3. `DoCard/ViewModels/ReportViewModel.swift`: use that net duration for totals, profile totals and trend;
   averages follow from the net total. The qualified-duration input to Focus Score uses the same net
   duration. Keep whole sessions in their starting week. Accept a clock/calendar with live defaults.

No stored model fields, database schema versions, migration stages, App Group keys or subscription
rules change. The general elapsed `BlockedProfileSession.duration` property is unchanged, including the
upgrade test's raw elapsed-time checks. Overlap merging is not added. Focus Score weights/qualification
thresholds and the other advanced formulas are unchanged; those cards are not certified by this suite.

Added tests: SessionHistoryTests.swift, SessionReportTests.swift, SessionReportDurationTests.swift.
Architecture and rerun guidance are in ADR-0006 and docs/testing/sessions-reports.md inside the app repo.

## Final verification

| Suite | Passed |
|---|---:|
| ScheduleTests |36|
| UnlockRecoveryTests |27|
| Upgrade1301Tests |1|
| SessionHistoryTests |7|
| SessionReportTests |7|
| SessionReportDurationTests |1 (five break rows)|
| **Total** |**79**|

- All79 executed identifiers match source method declarations exactly. Zero failures, skips or expected failures.
- Debug arm64 simulator build: BUILD SUCCEEDED.
- Release arm64 simulator build: BUILD SUCCEEDED.
- Strict swift-format lint passed for the four new Swift files; git diff --check passed.
- Eight-file session/report-only patch passed reverse-application checking against the working copy.
- Eleven unrelated pre-existing tracked diff blocks remain byte-for-byte unchanged. No commit, push or merge.

Environment: Xcode 26.2, Build version 17C52; iPhone17Pro simulator, actual runtime26.3.1(23D8133).
The dedicated simulator UUID is E9A35443-E689-48B5-8409-5E5D0C7D2B6B.

Timing on this machine:

| Measurement | Time |
|---|---:|
| New15 methods, selected-suite elapsed time |0.165s (0.173s wall inside XCTest)|
| New-suite command, including incremental build/launch/results |12.564s|
| Final79 methods, selected-suite elapsed time |0.768s (0.784s wall inside XCTest)|
| Final regression command, including setup/build/launch/results |9.571s|
| Separate Debug build |11.078s|
| Separate Release build |130.415s|

The first test command also rebuilt package dependencies and took127.969s. These local timings do not
predict GitHub-hosted runner duration. Implementation and investigating failures are one-time work,
separate from routine test execution.

## Scope and limits

History tests use fresh file-backed SwiftData stores and separate signed defaults. Save/reopen creates
a new container within the same process; it is not an independent process restart. Report integration
tests use real in-memory SwiftData stores. Times for report queries and trend are fixed to Monday
2026-11-02 noon in Asia/Taipei. The advanced calculators still have their own real-time dependencies.

The normal XCTest app host starts its ordinary services and emits existing network/FamilyControls
simulator diagnostics; test fixtures isolate their own storage but do not make the entire host offline.
The tests do not prove real extension-process delivery, resolution of the documented shared-list
visibility gap, actual NFC reads, Screen Time shields, physical-phone UI, arbitrary damaged history,
incomplete break endpoints, or all advanced report metrics. Incomplete break records currently retain
elapsed-time behavior. Only the selected old suites were rerun; other historical test classes are not
recertified here. The upgrade case in this regression uses its default initial migration phase; its
separate explicit second-process runner was not repeated in this batch.

## Evidence and review files

- [Session/report-only patch](https://github.com/YC-0210/DOCard-ios/compare/main...codex/sessions-reports)
- [All run summaries, including before-fix failures](DOCard-sessions-reports-results.json)
- [Final regression summary](DOCard-sessions-reports-regression-summary.json)
- [Verified suite counts and durations](DOCard-sessions-reports-verified-suites.json)
- [All79 individual test results](DOCard-sessions-reports-individual-results.txt)
- [Session import tests](../../../DoCardTests/SessionHistoryTests.swift)
- [Report integration tests](../../../DoCardTests/SessionReportTests.swift)
- [Break calculation tests](../../../DoCardTests/SessionReportDurationTests.swift)
- [Report duration helper](../../../DoCard/Utils/SessionReportDuration.swift)

Full xcresult bundles and build logs were retained locally during development. Future hosted results are available as GitHub Actions artifacts. No customer conversations or real customer records are included.
