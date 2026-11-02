# PR preparation: local verification

The session/report-only change was applied to a clean worktree based on main `a5216df72fcbc32fa20b8c7e4e86d7c6a4c936bc`.

- The clean-branch Xcode run passed all79 selected app methods: schedule36, recovery27, upgrade1, history7, reports7 and duration1. Zero failed or skipped.
- Executed method identities match the selected source declarations. The production result verifier also accepted this real result tree with those six selected suites.
- All18 CI gate test methods passed, including subcases for each new suite's missing/failed/skipped results and rejection of the old63-method result. These use controlled command responses and are separate from the real app tests.
- The six app/test source files exactly match the implementation that previously passed Debug and Release arm64 simulator builds. This clean-branch rerun rebuilt the Debug app/tests.
- New Swift files passed strict swift-format lint; shell syntax, Python compilation and diff whitespace checks passed.
- Portable HTML filters, counts, links and desktop/mobile layouts passed browser checks with no runtime errors or page overflow.

The proposed hosted workflow selects78 regression methods, then runs the unchanged upgrade method twice. That means79 unique app methods and80 executions. Hosted results will be recorded by the pull request's Actions run; the local79-method run does not claim both hosted upgrade phases completed.

See [the actual local XCTest summary](pr-local-regression-summary.json), [the initial before/after evidence](DOCard-sessions-reports-results.md) and [the overview](../overview.html). Physical-phone checks remain deferred.
