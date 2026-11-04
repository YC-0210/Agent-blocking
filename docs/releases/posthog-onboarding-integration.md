# Combined release branch

This branch combines onboarding PR #7 (bd0ac3b), PostHog retention and offline upload, the selected privacy-link layout and custom-answer limit, and remote force-update PR #8 (4394845). Main remains unchanged.

The iOS workflow runs automatically on pushes to main, including merged pull requests. It does not run automatically for feature branches or pull requests. Manual dispatch remains available.

The only force-update merge conflict was in the CI controlled-response suite map; both onboarding/retention and update suites are retained. The selected deterministic portfolio now contains 246 methods, with four StoreKit methods and one upgrade method run in two processes. These counts describe selection, not a test result.

No tests, simulator, build, TestFlight operation, or manual workflow dispatch was run for this integration, at the user's request. Earlier component validation is recorded in the existing ADRs and force-update verification document; it does not qualify this combined revision. The latest privacy UI and combined force-update integration still need validation when the machine is available.

Known deferred issue: entirely background scheduled capture is not fully qualified and can miss sessions. This branch does not claim to resolve that limitation.

The real local PostHog configuration is excluded from Git. Follow Config/README.md on each build machine; upload stays disabled when configuration is absent. No live minimum-version policy or PostHog data was changed during branch preparation. No new pull request was created.
