# Force-update verification

Baseline: `392fe9e68973a0c49a3d9738b5c43fa83cca22cf` from `YC-0210/DOCard-ios/main`.
Work branch: `codex/remote-force-update` in a separate clone. Existing worktrees,
behavior-tracking source, simulator devices and derived-data directories are not used.

The initial `AppUpdateTests/testOlderVersionRequiresUpdate` failed with the placeholder
policy, then passed after implementing numeric minimum-version comparison. Full pipeline
results are recorded below after execution; no production minimum is changed by testing.

The app entry-point patch is one `.modifier(AppUpdateGate())` line. Existing behavior
tracking in PR #7 changes startup hooks and onboarding; no tracking file is edited here.
A separate localization catalog avoids edits to the shared app string catalog.

Protected files unchanged: all `DoCard/Utils/Analytics/` files, all onboarding files,
RequestAuthorizer, StrategyManager, NFC readers/strategies, Shared.swift, all extensions,
SwiftData models/migration plan, subscription implementation, capability/signing files,
Xcode project/scheme, upgrade fixture and GitHub workflow. CI selection and its controlled
result fixtures are updated to require the new update-policy and network suites.

Physical NFC, OS shields and real App Store navigation require physical-device checks
before release. No App Store submission or production update enforcement is performed.

The complete staged patch applied cleanly against PR #7's
`origin/codex/onboarding-ui-prototype` tree using a separate temporary Git index.
This checks merge compatibility without changing that branch or its worktree.
The live Swift HTTPS client also fetched the existing `1.40.0` policy: `1.39.0`
required an update while `2.1.0` remained usable. Production JSON was read only.

## Completed local checks (2026-11-04)

- `bash ci/run-test-pipeline.sh --core-only`, with task-owned build/result paths:
  **passed**. Debug build-for-testing succeeded; 156 deterministic methods and four
  serial StoreKit methods passed with zero failures/skips and exact-ID validation.
  Upgrade migration and reopen passed in distinct processes (68190 and 68681).
  Release simulator compilation (arm64 and x86_64) ended with `** BUILD SUCCEEDED **`.
  That is 161 unique XCTest methods / 162 executions, including 17 new update tests.
- Package the tested Debug app with `ci/package-maestro-app.sh`, unpack its archive,
  then run `ci/run-maestro.py`: **four/four journeys passed**; manual lock/unlock,
  scheduled lock/unlock, scheduled early card unlock, and Emergency Unlock.
  Maestro flow time: 2m35s; runner total including setup: 267.6s.
- CI result-gate guards: 22 passed. Runner preflight guards: 11 passed. Maestro
  command/timeout guards: three passed. Maestro result guards: ten passed.
- Strict swift-format lint on all four new Swift files and `git diff --check` passed.
- New English/Traditional Chinese resources were inspected in the built app.

Local evidence is under `.build/force-update/pipeline-results/` (summary, JSON and
xcresult bundles), `.build/force-update/maestro-results/` (JUnit, logs and screenshots)
and `.build/force-update/live-check.log`. These are ignored build artifacts.
These results are local; GitHub check status is reported separately on the PR.
The four Maestro journeys verify existing recovery controls with no live remote-policy
dependency. Update presentation policy and HTTP behavior are covered by the new XCTest
suites; real update-screen/App Store behavior still needs physical-device qualification.
