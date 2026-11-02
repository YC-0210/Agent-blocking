# iOS CI: deterministic checks, StoreKit and first-release upgrade

`iOS CI` uses a core GitHub-hosted `macos-26` job, followed by an optional Maestro job. It selects Xcode 26.2 and creates
a disposable iPhone 17 Pro simulator using the installed iOS 26.2 runtime.
The runner image's installed tools can change; setup fails explicitly if the
chosen Xcode or runtime is missing. Update these choices deliberately after verification.

## What runs

1. Run `python3 ci/test-ios-ci.py` before Xcode in the workflow. These controlled-response
   checks verify stage ordering, result validation and failure handling.
2. Build the app, tests and dependent extensions once in Debug with `build-for-testing`.
3. Reuse that build for the 139 deterministic methods: schedule36, recovery28, history8,
   reports7, duration1, access12, entitlements2, selection rules4, enforcement1, lifecycle20,
   scripted store4, refresh1 and Settings15. Validate exact source method identities and
   every result before advancing.
4. Run the four `StoreKitAccessTests` serially using the same build and local Apple StoreKit
   environment. These are separate from the deterministic batch and never make real purchases.
5. Reuse the Debug build to run `Upgrade1301Tests/testFirstReleaseSavedDataSurvivesUpdate`
   against a fresh copy of the committed artificial 1.30.1 store. Restart the dedicated
   simulator without erasing data, then run the method in `reopen` mode. Require its exact
   ID in both phases, successful commands, correct markers and different process IDs.
6. Build Release only after all required checks pass. Publish the summary and upload logs
   and available `.xcresult` bundles even on failure; artifact retention is seven days.
7. When a manual dispatch enables `run_maestro`, archive the already-built Debug app.
   A downstream job downloads it, checks architecture and runs four locking/unlocking
   Maestro journeys on a new simulator. It uploads JUnit, screenshots and logs on failure
   as well as success. No new compilation or Maestro Cloud account is required.

There are **144 unique app methods / 145 executions** because upgrade runs in two processes.
The added manual-card method checks NFC start/stop, release requests and saved history.
The additional history method directly tests closed/open break preservation during expiry import
using an in-memory store. The existing foreground history-loader method now checks both paid
and unpaid paths, with an explicit access precondition. The broader lifecycle tests remain.

`ci/ios_test_selection.py` owns the two CI suite lists and derives expected method IDs/counts
from their Swift source. Adding a reviewed method to a selected suite includes it automatically;
adding a new suite requires explicitly selecting it. Do not substitute hardcoded counts for
identity validation. Missing, unexpected, duplicate, skipped, failed or unreadable results fail
validation, as do expected failures and nonzero Xcode command status.

`deterministic-results.json` and `storekit-results.json` record per-suite expected/discovered/
passed/failed/skipped counts and errors. Each stage retains its summary, tree, selection, log
and result bundle. `upgrade-results.json` retains both process outcomes, with phase evidence
under `upgrade-*`. Only this invocation's disposable simulator is deleted. One Debug build
serves all four test commands; no default upgrade execution is included in the earlier batch.
The job has a 30-minute timeout and cancels outdated runs for the same pull request or ref.
These describe the configured pipeline, not a claim of a new GitHub-hosted pass.

The fixed store package and expected data are hash checked against provenance before use.
Normal CI does not build the historical app or require old-source folders. Fixture regeneration
and the deliberate-error proof remain manual checks; see `scripts/upgrade1301/README.md`.
The fixture was generated on iOS 26.3.1. Running it on hosted iOS 26.2 is a distinct compatibility
check. A failure must retain the actual error; do not rewrite store metadata or substitute empty data.

The workflow uses read-only repository permissions and no Apple signing secrets.
The action dependencies are pinned to full commit SHAs. The existing build uses `-onlyUsePackageVersionsFromResolvedFile`; this checkout
has no Swift package dependency lockfile after the removed SDK dependency. Build/package files stay outside the uploaded reports.
No cache or parallel test matrix is introduced. One core job runs all required XCTest/upgrade/Release checks; the optional Maestro
job runs after it succeeds. The core required-check name is unchanged.

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

## Run the complete combined pipeline locally

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash ci/run-test-pipeline.sh --maestro
```

Put Java 17 and pinned Maestro 2.10.0 on PATH first. The complete runner runs gate
checks, the core shell runner, the app archive/unpack step, and the four UI journeys.
It uses a new results directory and writes `pipeline-passed` only when every requested
stage passed. `CI_RESULTS_DIR` and `CI_BUILD_DIR` can select separate output/build paths.
The default `--core-only` mode omits the optional UI stage. The four journeys and mock
boundaries are documented in [the Maestro guide](testing/maestro.md).

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
across midnight still require other checks. Paid-only access policy now has selected local checks;
production grace configuration remains a separate release requirement.
Session/report checks use signed isolated settings, file-backed history stores reopened within
one process, one direct in-memory expiry-import regression, real report queries, and five small
break-calculation inputs. P5/P6
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
They verify all selected deterministic and StoreKit suites, per-suite reporting, missing/wrong-ID/duplicate/skipped/failed
tests, unreadable results, preservation of command failures, Release gating, and removal
of stale success markers. They also require both upgrade phases, a new process, the exact
upgrade method, deterministic failure stopping before StoreKit, one Debug build reused by all test runs, and cleanup of only the owned
simulator without erasing data. They do not replace a real local or GitHub-hosted Xcode run.

## References

- [GitHub macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Workflow triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Concurrency controls](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)

## Combined local validation — 2026-11-02

A fresh build and a complete `ci/run-test-pipeline.sh --maestro` run passed:
139 deterministic methods, four serial Apple-local StoreKit methods, upgrade migration
and reopen in distinct processes (69805 and 70105), Release compilation, artifact
archive/unpack, and all four Maestro locking journeys. This is 144 unique XCTest
methods /145 executions, followed by four UI journeys. No Xcode methods were skipped.
The wrapper wrote its `pipeline-passed` marker with mode `--maestro` only after the
final UI result gate passed. The core summary and final UI outcome are reported separately.

The run also passed 22 existing controlled-response CI gate checks and ten Maestro
result-gate checks. Three isolated orchestration probes confirmed core failure stops
before packaging/UI, UI failure cannot produce whole-pipeline success, and reused
results directories are refused. These probes control dependencies; they are not
physical-device tests. The packaged Debug app matched its build products byte for
byte, and the Release binary excludes the simulator harness controls/clock/type.

The requested remote audit branch was absent. Integration used the nine uncommitted
files in the existing local `codex/test-pipeline-audit-fixes` worktree and the 32-file
local Maestro implementation. Both input worktrees remain unchanged. The combined
result is a separate local `codex/combined-test-pipeline` checkout. No GitHub push,
workflow dispatch, backend or physical-device change was made.
