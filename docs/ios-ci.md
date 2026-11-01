# iOS CI: schedule and unlock/recovery

`iOS CI` uses one GitHub-hosted `macos-26` job. It selects Xcode 26.2 and creates
a disposable iPhone 17 Pro simulator using the installed iOS 26.2 runtime.
The runner image's installed tools can change; setup fails explicitly if the
chosen Xcode or runtime is missing. Update these choices deliberately after verification.

## What runs

1. Build the app and dependent extensions in Debug and run only
   `DoCardTests/ScheduleTests` (36 tests) and `DoCardTests/UnlockRecoveryTests`
   (27 tests), in one `xcodebuild test` invocation.
2. Export Xcode’s combined summary and test tree. Require 36 passing schedule tests
   and 27 passing unlock/recovery tests in the `DoCardTests` bundle, with unique
   identifiers, none failed or skipped, and 63 passed in the combined summary.
   A missing suite cannot be replaced by extra tests in the other suite.
   Missing, unreadable, or inconsistent results fail the job.
3. Build the app and dependent extensions in Release for the simulator.
4. Publish a job summary and upload logs and available `.xcresult` bundles,
   including when an earlier step fails. Reports expire after 7 days.

The job stops after test failure; Release is then reported as not reached.
It has a 30-minute timeout and cancels outdated runs for the same pull request or ref.
The exact counts are intentional: update `EXPECTED_SCHEDULE_TEST_COUNT` or
`EXPECTED_UNLOCK_RECOVERY_TEST_COUNT` when adding reviewed cases to that suite.
The script has matching local defaults. `suite-results.json` records separate
expected/discovered/passed/failed/skipped counts and any validation errors.
A nonzero Xcode exit status is preserved even if result files look successful.

The workflow uses read-only repository permissions and no Apple signing secrets.
The action dependencies are pinned to full commit SHAs. Package resolution uses
the committed `Package.resolved`. Build/package files stay outside the uploaded reports.
No cache or parallel test matrix is introduced. One job runs both suites.

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
paths. They do not certify actual shields, NFC radio reads, cross-process background
delivery, app/phone restart, old-data migration, timer ticks, or indefinite card-ended
lifetime across midnight. Section D and subscription policy changes remain excluded.
See ADR-0004 for dependency design and limits. Extend the reviewed suites as each
later testing area is implemented. Hosted Mac usage and stored
reports count towards the private repository owner's Actions allowance.

## Verify the CI failure rules

```sh
python3 ci/test-ios-ci.py
```

These checks run the actual CI shell script with controlled Xcode/simulator responses.
They verify both selected suites, per-suite reporting, missing/duplicate/skipped/failed
tests, unreadable results, preservation of command failures, Release gating, and removal
of stale success markers. They do not replace a real local or GitHub-hosted Xcode run.

## References

- [GitHub macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Workflow triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Concurrency controls](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
