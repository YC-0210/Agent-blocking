# iOS CI: schedule, recovery, sessions/reports and first-release upgrade

`iOS CI` uses one GitHub-hosted `macos-26` job. It selects Xcode 26.2 and creates
a disposable iPhone 17 Pro simulator using the installed iOS 26.2 runtime.
The runner image's installed tools can change; setup fails explicitly if the
chosen Xcode or runtime is missing. Update these choices deliberately after verification.

## What runs

1. Build the app, tests and dependent extensions once in Debug with `build-for-testing`.
   Reuse that build with `test-without-building` for `DoCardTests/ScheduleTests`
   (36 tests), `DoCardTests/UnlockRecoveryTests` (27 tests), `DoCardTests/SessionHistoryTests`
   (7), `DoCardTests/SessionReportTests` (7) and `DoCardTests/SessionReportDurationTests`
   (1 calculation method with five break rows), in one 78-method regression run.
2. Export Xcode’s combined summary and test tree. Require 36 passing schedule tests
   and 27 passing unlock/recovery tests, plus 7 history, 7 report and 1 report-duration test
   in the `DoCardTests` bundle, with unique
   identifiers, none failed or skipped, and 78 passed in the combined summary.
   A missing suite cannot be replaced by extra tests in the other suite.
   Missing, unreadable, or inconsistent results fail the job.
3. Reuse the same Debug build to run `Upgrade1301Tests/testFirstReleaseSavedDataSurvivesUpdate`
   against a fresh copy of the committed artificial 1.30.1 store. Then restart the same
   disposable simulator without erasing data and run the method in `reopen` mode.
   Require the exact test to pass in each phase, no skips or expected failures, successful
   commands, correct phase markers and different process IDs. The Swift test requires the
   first process's checkpoint and checks stable schedule IDs and the full saved data again.
4. Build the app and dependent extensions in Release for the simulator, only after all checks pass.
5. Publish a job summary and upload logs and available `.xcresult` bundles,
   including when an earlier step fails. Reports expire after 7 days.

The job stops after test failure; Release is then reported as not reached.
It has a 30-minute timeout and cancels outdated runs for the same pull request or ref.
The exact counts are intentional: update `EXPECTED_SCHEDULE_TEST_COUNT` or
`EXPECTED_UNLOCK_RECOVERY_TEST_COUNT`, `EXPECTED_SESSION_HISTORY_TEST_COUNT`,
`EXPECTED_SESSION_REPORT_TEST_COUNT` or `EXPECTED_SESSION_REPORT_DURATION_TEST_COUNT`
when adding reviewed cases to the corresponding suite.
The script has matching local defaults. `suite-results.json` records separate
expected/discovered/passed/failed/skipped counts and any validation errors.
A nonzero Xcode exit status is preserved even if result files look successful.
`upgrade-results.json` records both phases, process IDs, durations and errors. Each phase
also retains its own log, Xcode summary, test tree and `.xcresult` bundle in a new `upgrade-*`
directory. There are **79 unique app test methods and 80 executions**: the upgrade method
runs twice. CI gate tests are separate from those app test counts.

The fixed store package and expected data are hash checked against provenance before use.
Normal CI does not build the historical app or require old-source folders. Fixture regeneration
and the deliberate-error proof remain manual checks; see `scripts/upgrade1301/README.md`.
The fixture was generated on iOS 26.3.1. Running it on hosted iOS 26.2 is a distinct compatibility
check. A failure must retain the actual error; do not rewrite store metadata or substitute empty data.

The workflow uses read-only repository permissions and no Apple signing secrets.
The action dependencies are pinned to full commit SHAs. Package resolution uses
the committed `Package.resolved`. Build/package files stay outside the uploaded reports.
No cache or parallel test matrix is introduced. One job runs all required checks.

## Triggers

- A pull request targeting `main` is opened, reopened, or receives new commits.
- A push reaches `main`, including a merged pull request.
- A manual `workflow_dispatch` run. The Run workflow button becomes available
  after the workflow exists on the default branch.

The initial pull request can exercise the workflow before merge. Branch protection
is a separate setting: this workflow reports failures but does not configure merge
blocking. Required checks for this private repository depend on the GitHub plan.
Nothing here uploads to TestFlight or submits an App Store release.

## Run the same command locally

From the repository root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash ci/run-ios-ci.sh
```

Local logs default to `.build/ios-ci/results` and build products to
`.build/ios-ci/build` (already ignored by Git). The script creates and removes
only its own simulator. To use another installed runtime for a local diagnostic run:

```sh
CI_SIMULATOR_RUNTIME=com.apple.CoreSimulator.SimRuntime.iOS-26-3 \
  bash ci/run-ios-ci.sh
```

Runtime overrides are for local diagnosis; GitHub's workflow pins iOS 26.2.
`CI_RESULTS_DIR` and `CI_BUILD_DIR` may be overridden to keep separate run outputs.

## Limits

The schedule checks use fixed dates and an explicit Taipei calendar. The existing
Xcode test target is app-hosted, so normal app startup code also runs; these test
assertions do not depend on a successful backend connection. The earlier test
classes are compiled by the test target but are not selected for execution.

The unlock/recovery fixture exercises real session, stop, paired-card validation,
signed-state and shared schedule-start code with controlled dependencies. Each
case has isolated settings, in-memory SwiftData, a fixed clock and a temporary key.
Hardware reads are scripted and blocking requests are recorded. Ancillary platform
effects are omitted; normal application calls keep their live defaults.

These checks protect window calculations, validation, and the selected stop/recovery
paths. The upgrade check covers the artificial source-generated old store through the
production opener and a new test process; it does not certify every original user store.
Actual shields, NFC radio reads, cross-process background delivery, phone reboot, App Store
installation, real app-selection tokens, timer ticks and indefinite card-ended lifetime
across midnight still require other checks. Section D and subscription policy changes remain excluded.
Session/report checks use signed isolated settings, file-backed history stores that are reopened
within one process, real in-memory report queries, and five small break-calculation inputs. P5/P6
overlap cases and advanced report cards are excluded. See [the testing overview](testing/overview.html)
and [the local session/report evidence](testing/evidence/DOCard-sessions-reports-results.md).
See ADR-0004 for dependencies, ADR-0005 for upgrade evidence and ADR-0006 for history/report rules. Extend the reviewed suites as each
later testing area is implemented. Hosted Mac usage and stored
reports count towards the private repository owner's Actions allowance.

## Verify the CI failure rules

```sh
python3 ci/test-ios-ci.py
```

These checks run the actual CI shell script with controlled Xcode/simulator responses.
They verify all five selected regression suites, per-suite reporting, missing/duplicate/skipped/failed
tests, unreadable results, preservation of command failures, Release gating, and removal
of stale success markers. They also require both upgrade phases, a new process, the exact
upgrade method, one Debug build reused by all test runs, and cleanup of only the owned
simulator without erasing data. They do not replace a real local or GitHub-hosted Xcode run.

## References

- [GitHub macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Workflow triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Concurrency controls](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
