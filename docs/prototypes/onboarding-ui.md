# DO Card onboarding UI prototype

Throwaway native UI review. Branch: `codex/onboarding-ui-prototype`.
Base: `392fe9e` (committed origin/main), separate from the dirty PostHog worktree.

## Selected design

Variant A: existing dark stacked list, orange selection outline, visible checkboxes.

Welcome → existing statements → card introduction → purposes (multiple selection)
→ scrolling habits (multiple selection) → daily phone time (single selection)
→ permission → app selection → card pairing
→ gallery → offer.

Purposes replace the old age question. Daily-time choices remain unchanged. The
calculation, good/bad-news interstitial, lifetime-loss and time-recovery screens
are removed from the flow, including their years mapping. Question progress now uses three steps. Both multi-select
questions require at least one choice; “其他” can coexist with other choices.
The daily-time screen has no instruction subtitle and uses an explicit Continue
button instead of auto-advancing. Habit options are short single-clause phrases.
Selecting “其他” on either multi-select question opens a free-text field and
requires a nonblank answer before continuing. Custom answers survive navigation
and deselection/reselection. The plain visual-preview launch flag remains memory-only.
The user subsequently authorized persisted onboarding capture and PostHog delivery;
see [the tracking implementation](../analytics/onboarding-tracking.md) for that behavior.
No SDK, retention code or SwiftData schema change is added.

## Review from the beginning

Run one command from the worktree to build and open a fresh dedicated simulator:

```sh
./scripts/prototypes/run-onboarding-ui.sh
```

Or build Debug for an existing booted iOS simulator:

```sh
xcodebuild -project DoCard.xcodeproj -scheme DoCard -configuration Debug \
  -sdk iphonesimulator -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  -derivedDataPath /tmp/docard-onboarding-native-build CODE_SIGNING_ALLOWED=NO build
xcrun simctl install SIMULATOR_ID \
  /tmp/docard-onboarding-native-build/Build/Products/Debug-iphonesimulator/DoCard.app
xcrun simctl launch SIMULATOR_ID online.do.card.app --onboarding-ui-prototype \
  -AppleLanguages '(zh-Hant)' -AppleLocale zh_TW
```

The launch flag opens the real OnboardingView at its welcome page, ignoring the
completed flag and subscription entry gate for this review. It works only in DEBUG
simulator builds. Subscription foreground reconciliation is skipped in this mode.
Without the flag, normal app entry is unchanged. Relaunch with the flag to restart.
The later permission/pairing/gallery screens retain their normal local side effects;
this mode is for a disposable simulator, not a production onboarding bypass.

## Integration boundary

The other session owns retention delivery and the shared build configuration. This
branch now owns the onboarding journal/events and a separate batch adapter, using the
same installation ID/configuration/consent contracts. The other worktree's files remain
untouched. See ../analytics/onboarding-tracking.md for the integration boundary.
DoCardApp.swift contains the simulator-only review hook and one onboarding tracking
startup call; reconcile those with the other branch at merge time. Product locking,
emergency unlock, authorization, NFC, models and subscription logic remain unchanged.

## Validation

Debug simulator build: BUILD SUCCEEDED. Simulator walkthrough results are recorded
in DO_Card_Changelog.md. Physical-device behavior and downstream setup screens are
not validated by this UI review. No App Store or TestFlight release was performed.
