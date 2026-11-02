# Maestro locking and unlocking journeys

The top UI layer contains four core journeys in `.maestro/smoke/`. They replace the
previous navigation, unpaid-screen, rename and sample-report smoke flows. Each journey
starts with zero completed sessions and must exercise the real session code to pass.

| Journey | UI and saved-state proof | Lower-level coverage |
| --- | --- | --- |
| manual-lock-unlock | Long-press Start, deliver a card read, see active focus and a blocking request; long-press Stop, deliver a card read, see idle and a release request; reopen and read the completed manual session | UnlockRecoveryTests/testU5ManualCardStartAndStopSavesHistory; subscription lifecycle access rules |
| scheduled-lock-unlock | Save the schedule in the real editor; deliver start/end events at 09:00/10:00; verify active/idle, restriction requests and saved timer-expired history after reopening | ScheduleTests exact boundaries; UnlockRecoveryTests recovery/expiry cases |
| scheduled-card-unlock | Start a schedule, use the real Stop control and simulated card; replay a start event at 09:15; reopen; verify no new block and one saved card-ended scheduled session | UnlockRecoveryTests/testU1CardUnlockEndsScheduledSession, R1/R2/R3/R8/R12 card cases |
| emergency-unlock | Start scheduled focus; open Settings > Emergency Unlock; break the glass and press the real confirmation button; verify a release request, one audit event and quota 3 → 2; replay a start callback and reopen without reblocking | UnlockRecoveryTests/testU2EmergencyUnlockEndsScheduledSessionOnce, testR7RepeatedEmergencyUnlockDoesNotSpendAnotherUse, emergency recovery cases |

## What is real and what is simulated

Maestro operates production SwiftUI controls. The app uses the production strategy
manager, card validation/callbacks, restriction-plan rules, schedule handlers,
suppression signatures, active-session resolution and SwiftData save/reopen paths.
The observation panel reads completed history through a separate model context. It
records emitted restriction plans; it cannot assign an active/ended session or force
an expected result.

Only the hardware reader, OS restriction writes, schedule-event delivery, clock,
emergency-quota storage and unrelated OS effects are simulated. The simulated NFC
reader requires a preceding real UI scan request. The simulated blocker records
writes below production selection/access policy, not instead of that policy.
The 09:00/09:15/10:00 controls deliver events to the real ScheduleTimerActivity
handler. They do not exercise Apple's background scheduler or a separate extension
process. Repeated delivery and app relaunch check that early unlock suppression works.

All fixtures, observation controls and app-wide test-runtime fallback compile only
for `DEBUG && targetEnvironment(simulator)`. An explicit launch scenario and reset
argument are required. Every flow resets first; resume launches preserve the file-backed
store, clock, HMAC signing key, quota and recorder state. Task-scoped runtimes used by
existing XCTest suites take priority over the simulator fallback.
The fixture profile uses allow-only mode, with no allowed apps, so the real policy
produces an observable restriction plan without forged Family Controls tokens.
Family Controls authorization is not changed or marked approved. Paid access uses
the existing Debug override. A future analytics marker prevents synthetic uploads.

This layer proves the app's requests and saved results. It cannot prove a physical
NFC read, that another app is shielded by iOS, background scheduling delivery, or real
subscription purchases. Those checks stay in physical-device/StoreKit testing.

## Run locally

Use Xcode 26.2, the iOS 26.2 simulator runtime, Java 17 and Maestro 2.10.0.
`bash ci/install-maestro.sh INSTALL_DIRECTORY` downloads and checks the pinned CLI.
Add `INSTALL_DIRECTORY/maestro/bin` to PATH and set JAVA_HOME to Java 17.

```sh
xcodebuild build-for-testing -project DoCard.xcodeproj -scheme DoCard \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .build/maestro-build CODE_SIGNING_ALLOWED=NO
python3 ci/test-maestro-results.py
python3 ci/run-maestro.py \
  --app .build/maestro-build/Build/Products/Debug-iphonesimulator/DoCard.app \
  --results .build/locking-results-1
```

Each run requires a new results directory. The runner creates and deletes only its
own simulator. A ten-minute timeout bounds the Maestro process group. A success
requires CLI exit zero and exactly the four expected JUnit SUCCESS cases. Missing,
duplicate, failed, warning, skipped or old flow names cannot pass. No test retries
hide a failure. Reports, screenshots, command records and logs are retained.

## Pipeline

The combined pipeline builds Debug once, runs **139 deterministic methods**, runs
**four serial Apple-local StoreKit methods**, and runs the upgrade method in two
separate processes. Release builds only after these checks pass. That is **144 unique
XCTest methods / 145 executions**. The new expiry-import history test from the audit
branch and the manual card round-trip from the Maestro work are both included.

`ci/ios_test_selection.py` owns the selected suites and derives exact method identities
from source. No workflow count variables compete with that definition. The result
validator rejects missing, duplicate, skipped, unexpected or failed methods before
advancing. Tests now select all access and Settings suites in CI as well as locally.

A manual workflow dispatch with `run_maestro=true` then packages the Debug app.
The downstream Maestro job checks architecture, unpacks and installs that same app,
runs the four journeys, validates JUnit, and saves results. It does not rebuild the app.
The existing core required-check name is preserved. Maestro remains manual opt-in.

Use `bash ci/run-test-pipeline.sh --maestro` to run this complete sequence locally,
including result-gate checks and artifact roundtrip. Java 17 and Maestro 2.10.0 must be
on PATH. The wrapper requires a fresh results directory, writes `pipeline-passed` only
after all requested stages pass, and writes `pipeline-summary.md` even after failure.
`--core-only` skips the optional UI stage. The underlying core runner remains
`ci/run-ios-ci.sh`; it is the same runner invoked by GitHub's first job.

Keep detailed rule permutations in XCTest. If a UI journey finds a logic failure
without a failing lower-level test, add that lower-level regression before the fix.

## Earlier standalone Maestro validation — 2026-11-02

- Four journeys passed on two fresh simulators. Flow execution took 132.627s
  and 99.434s. The second run installed the archived/unpacked app.
- All 143 selected XCTest methods passed with zero missing/skipped/failed methods.
- Ten Maestro result-gate tests and 18 existing CI-gate tests passed. The previous
  five-flow report is rejected. Workflow syntax passed actionlint 1.7.12.
- Debug and Release builds passed. Harness type, controls and clock keys are absent
  from the Release binary. Archive/unpack preserved app executable/library/plist bytes.
- A disposable copy incorrectly expected quota=3 after an Emergency Unlock. Exactly
  that journey failed; three others passed. Runner exited 1 and wrote no success marker.
- No GitHub push/dispatch or physical-device check was performed.

The standalone results above preceded integration with the audit branch. See
[combined CI guide](../ios-ci.md) and the combined validation report for current results.

## Combined pipeline validation — 2026-11-02

The complete local wrapper passed 139 deterministic methods, four StoreKit methods,
both upgrade processes and the Release build before running all four Maestro journeys
successfully. Exact method identities and results were checked at each stage. The
Debug artifact roundtrip and Release harness exclusion checks passed. The final
whole-pipeline marker records `--maestro`. No hosted workflow run is claimed.
