# Onboarding tracking and retention entry labels

Implementation branch: `codex/onboarding-ui-prototype`.

## Ownership and integration

All changes are in the onboarding worktree. No file in the retention worktree is
edited, committed, reset or copied into this branch. New files use an Onboarding
prefix. The shared install identity, consent implementation, retention journal,
retention uploader, Info.plist, Xcode project and CI selection files are untouched.
The app startup addition is one `OnboardingTracking.shared.start()` call; reconcile
that call with the other branch's existing retention startup when combining branches.
Run retention preparation before onboarding begins minting/reading the shared ID.

The other uploader is private and still uncommitted. To keep both branches independently
buildable, this feature has a small batch adapter rather than importing/copying its
private transport. Both adapters use the same capture API, identity key, consent gate,
configuration keys, environment convention and anonymous event settings. No SDK is
added. A shared transport can be extracted once both implementations are committed;
there is no need to block or alter the other session's files to do that now.

## Storage and identity

`OnboardingTracking` uses `AnalyticsIdentity.installID` as PostHog `distinct_id`.
This is per-install measurement, not a login or cross-device person identity.
A main-app-only App Group journal (`onboarding-v1-development` / `onboarding-v1-production`)
stores the draft, immutable event snapshots and delivery state in one atomic JSON
transaction, protected until first unlock and with owner-only file permissions.
No SwiftData model/schema/migration changes are involved. Draft changes save as the
UI changes; confirm buttons save an event and answer snapshot together. Restarts
return to the welcome page with the saved answers prefilled, not to an arbitrary
later setup step. Capture failures are logged privately and do not block setup.

Version 1 tracks a single initial onboarding attempt per installation. Settings-driven
replays reuse its history; changed question submissions create new revisions. A fresh
replay-start/completion count is not emitted for each settings replay. No events are
invented for users who completed onboarding before this version.

## Events

| Event | Trigger |
| --- | --- |
| onboarding_started | First opening of a tracked onboarding flow; not every foreground/restart |
| onboarding_step_completed | Confirmed question or continuing a setup page; step_id identifies the page |
| onboarding_answers_submitted | Confirming the third question with all three answers valid |
| onboarding_completed | Final offer screen finishes the real flow |

Question confirmation events have question_id as well as step_id. Repeating an
unchanged question/setup step does not add another event. Changed answers add a new
revision; earlier submissions remain. Setup completion means the page's continuation
callback ran, not an additional claim that hardware/permissions were independently
verified by analytics. Actual locking events remain owned by the retention work.

Properties include event_id, response_revision, questionnaire_version=1, original
recording app_version, onboarding_attempt_id, install_id, environment and is_synthetic.
Full submissions have `purposes`, `scrolling_habits` (arrays), `daily_phone_time` (stable
code), plus selected custom `purpose_other_text` / `habit_other_text`. Unselected custom
drafts never leave the device. Individual question events contain only that question's
confirmed answer. The uploader disables person-profile creation and GeoIP enrichment.
It does not call identify/alias, autocapture, replay, screen tracking or feature flags.

## Delivery and configuration

Use the SAME runtime Info.plist keys as the retention branch:

- DOCardPostHogToken: public `phc_` project token, never a personal/admin token.
- DOCardPostHogHost: HTTPS ingestion origin, e.g. https://us.i.posthog.com.
- DOCardPostHogEnvironment: development for Debug, production for Release.

Missing, invalid or mismatched configuration disables networking while local capture
continues. This branch intentionally does not copy the other branch's uncommitted
Info.plist/xcconfig wiring or credentials. Normal device/Release delivery becomes
configured when those shared build settings are integrated. Debug also accepts these
three names as process environment variables for isolated simulator verification;
Release does not. No token is committed.

Upload requires the EXISTING AnalyticsConsent.disclosureShown and general analytics
settings. No new consent bypass exists. A successful disclosure notification, foreground,
new confirmation, and a 60-second foreground timer trigger drains. Each request has at
most 50 events, each drain at most five batches. Backgrounding cancels the active drain;
background delivery is not guaranteed. Network and rate-limit failures retain the queue
with persistent exponential backoff; numeric Retry-After is honored up to 24 hours.

Retries keep UUID, timestamp, capture version and payload unchanged. Recognized HTTP
success advances only the sent event IDs; answers/events appended during a request
remain pending. Checkpoints are isolated by destination host/token/environment. History
is retained after acceptance. This is at-least-once delivery, not an unconditional
exactly-once guarantee: downstream queries should use event IDs/revisions. No automatic
server-side repair after accepted-but-dropped ingestion is claimed.

## Retention segmentation

Use `onboarding-entry-segments.sql` as the join input to the retention query. It selects
the last COMPLETE submission at or before each installation's first successful locking
session. Later changes cannot move past cohort membership. A pre-entry submission that
arrives late can correctly resolve an initially unknown label. Join by installation ID
and environment. Keep the existing retention period calculations/denominator unchanged;
never sum raw retention contribution revisions.

Each selected purpose can have its own retention group. The same installation can be
in study and major_exam, so group denominators overlap and must not be added together.
Do not make a new group for every free-text response; label those installations other.
An absent answer is labelled unknown; it is not inferred from later behavior or replaced with a later
submission. Native person-property cohort filters are not implemented by this change;
the verified segmentation path is event properties plus SQL, with person profiles off.

## Validation and proof

- 17 native iOS unit tests: persisted drafts/IDs, immutable revisions, valid answers,
  custom-text filtering, completion, corrupt-file behavior, disclosure/environment gates,
  offline retry/backoff, receipt validation, 429, destination checkpoints, concurrent writes,
  payload identity/version, 50-event bounds, cancellation, concurrent drains and setup steps.
- Real iOS UI driver: multiple/custom answers, back navigation, app termination/relaunch
  and restored answers. No extra submission on unchanged replay. This ran before the final
  setup-step bookkeeping addition, which is covered by its unit test.
- Actual iOS journal: five screen-generated events, one identical installation ID in
  App Group defaults and event distinct_id. In a dedicated synthetic simulator, a
  previously-shown-disclosure fixture was seeded while shut down, then restored afterward.
  The app's own URLSession uploader delivered the persisted queue; all five records and
  custom answers were verified in PostHog, not just accepted over HTTP.
- Swift proof executable: three synthetic development installations. It uses these exact
  onboarding classes and reads the other worktree's retention calculator/journal/builder
  without editing them. An injected offline failure is replayed through the real capture
  API. There are 15 onboarding and 6 retention events, 21 unique stored UUIDs.
- Later study→work answer change preserves the first-session study/exam/other labels.
  Period-1 proof: study 1/1, major_exam 1/1, other 1/1, work_tasks 0/1, unknown 1/1.
  These are test fixtures, not product performance. Query: ../prototypes/onboarding-retention-proof.sql.
- Debug and Release simulator builds pass. No physical-device/offline-extension/NFC
  release qualification or production rollout is claimed.

Proof artifacts are in the review workspace's `outputs/onboarding-tracking-proof`;
fixture prefix `retention-upload-test-onboarding-b280026b-`. Direct iOS fixture ID:
`90A60DEC-CB94-48EE-9C29-46FE9A54CA64`, environment=development, is_synthetic=true.
Do not include these in production analytics. Initial ingestion queries can be partial
and cached: repeat a fresh narrow query before interpreting missing records as loss.

Run the native suite:

```sh
xcodebuild test -project DoCard.xcodeproj -scheme DoCard -configuration Debug \
  -destination 'platform=iOS Simulator,id=SIMULATOR_ID' \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES -parallel-testing-enabled NO \
  -only-testing:DoCardTests/OnboardingTrackingTests
```

App Group capture requires entitlements. Use Xcode's ad-hoc simulator signing above;
an unsigned simulator build can render the UI but may have no App Group container.
The plain --onboarding-ui-prototype flag stays memory-only and sends nothing. Combining
it with --onboarding-tracking-fixture explicitly enables synthetic capture in a separate
Debug simulator journal, still subject to configuration and the disclosure gate.

The live Swift proof runner is `scripts/analytics/onboarding-live-proof.swift`. Compile
it with this branch's OnboardingJournal/OnboardingPostHogUploader and the other branch's
RetentionTimeCalculator/RetentionJournal/RetentionEventBuilder, then provide the public
project token/host in environment variables and OnboardingProofDirectory. It only emits
marked development data and writes no credential into its artifacts. It deliberately
requires explicit access to the retention source rather than taking ownership of it.

Official contract: https://posthog.com/docs/api/capture
