# Sessions and reports: local checks

Run from the current app repository using an available simulator UUID:

```sh
xcodebuild test -project DoCard.xcodeproj -scheme DoCard \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  -parallel-testing-enabled NO \
  -only-testing:DoCardTests/SessionHistoryTests \
  -only-testing:DoCardTests/SessionReportTests \
  -only-testing:DoCardTests/SessionReportDurationTests \
  -resultBundlePath /tmp/DOCard-session-report-results.xcresult \
  CODE_SIGNING_ALLOWED=NO
```

Use a new result-bundle path on each run. Expect 15 passed, zero failed and zero skipped:
seven history methods, seven report methods and one calculation method with five input rows.
Check the result bundle, not just xcodebuild's exit status. A filter matching no methods
can return success with zero executed tests. The result tree must contain every selected
source method, including `testP8GroupsSessionsAndRanksTheTopThreeProfiles`.

| Group | Check |
|---|---|
| S1 | Duplicate import saves one record, with original fields/profile link after reopening |
| S2 | Distinct imports retain separate IDs, timestamps, profile links and reverse links |
| S3 | Completion updates the active row instead of creating another row |
| S4 | Foreground loading transfers pending history without activating completed sessions |
| S6 | Conflicting start cannot inflate the saved elapsed interval |
| S7 | Late timer completion cannot extend Emergency Unlock history |
| S8 | Late active snapshot cannot reopen completed history |
| P1 | Empty total/count/average/ranking are valid zeros/empty |
| P2 | Thirty plus twenty minutes remains fifty on reload; count two, average twenty-five |
| P3 | Active sessions are excluded from completed-session report metrics |
| P4 | One-hour session with ten-minute break reports fifty throughout totals and trend |
| P4 calculation | No break:60; inside:50; touches start:50; touches end:50; partial overlap:55 minutes |
| P7 | Sunday23:50–Monday00:20 remains thirty minutes in the starting week |
| P7 boundary | Separate fixture: Monday00:00–00:15 belongs to the new week |
| P8 | Two Work sessions aggregate to forty; top profiles are forty/thirty/twenty; total one hundred |

P5/P6 are excluded. The S5 reopen checks are folded into S1/S2, and the existing recovery
suite owns manual-versus-scheduled precedence (former S9).

For regression, also select `ScheduleTests` (36), `UnlockRecoveryTests` (27), and
`Upgrade1301Tests` (1): expect 79 total. A normal upgrade invocation checks a fresh copied
first-release store; the separate upgrade runner provides its explicit second-process phase.

The GitHub workflow selects these three suites in the existing 78-method regression phase,
then runs the upgrade method twice: 79 unique app methods / 80 executions overall.

No customer records are used. History stores use unique temporary directories, signed defaults
use unique suite names and test key material, and each test cleans its own data. Report tests
use real in-memory SwiftData stores. Physical-device checks and advanced report metrics are
outside this suite's claims. See ADR-0006 for app changes and scope.
