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
and deselection/reselection in memory, but reset when the flow is recreated.
All questionnaire answers stay in OnboardingView memory, survive back navigation,
and reset when the flow is recreated. No questionnaire persistence, analytics events,
PostHog SDK, keys, retention code, schema changes, or upload integration is added.

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

The other session owns PostHog, identity linkage, persistence, and delivery. Future
integration should attach to the stable purpose/habit IDs and should preserve the
in-memory back-navigation behavior. Do not merge this prototype until UI review.
DoCardApp.swift contains the small simulator-only entry hook; it may need manual
reconciliation with the other session's startup changes. Product session/locking,
emergency unlock, Family Controls authorization, NFC, models, and subscriptions
are not changed by this prototype.

## Validation

Debug simulator build: BUILD SUCCEEDED. Simulator walkthrough results are recorded
in DO_Card_Changelog.md. Physical-device behavior and downstream setup screens are
not validated by this UI review. No App Store or TestFlight release was performed.
