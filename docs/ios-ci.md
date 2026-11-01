# First iOS CI workflow

`iOS CI` uses one GitHub-hosted `macos-26` job. It selects Xcode 26.2 and creates
a disposable iPhone 17 Pro simulator using the installed iOS 26.2 runtime.
The runner image's installed tools can change; setup fails explicitly if the
chosen Xcode or runtime is missing. Update these choices deliberately after verification.

## What runs

1. Build the app and dependent extensions in Debug and run only
   `DoCardTests/ScheduleTests` (the first 36 rebuilt tests).
2. Verify the Xcode result reports exactly 36 passing tests, with none failed or skipped.
3. Build the app and dependent extensions in Release for the simulator.
4. Publish a job summary and upload logs and available `.xcresult` bundles,
   including when an earlier step fails. Reports expire after 7 days.

The job stops after test failure; Release is then reported as not reached.
It has a 30-minute timeout and cancels outdated runs for the same pull request or ref.
The exact test count is intentional: update `EXPECTED_SCHEDULE_TEST_COUNT` when
adding cases to this reviewed suite. The script also has a matching local default.

The workflow uses read-only repository permissions and no Apple signing secrets.
The action dependencies are pinned to full commit SHAs. Package resolution uses
the committed `Package.resolved`. Build/package files stay outside the uploaded reports.
No cache or parallel test matrix is introduced in this first version.

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

This protects window calculations and validation, not actual shields, NFC,
cross-process background delivery, or old-data migration. Extend the reviewed
suite as each later testing area is implemented. Hosted Mac usage and stored
reports count towards the private repository owner's Actions allowance.

## References

- [GitHub macOS 26 runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md)
- [Workflow triggers](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [Concurrency controls](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)
