# 2026-11-03 — isolated onboarding capture and PostHog delivery

User authorized implementation while keeping the retention worktree untouched.
OnboardingJournal saves drafts, immutable confirmed revisions and an outbox in one
atomic, protected App Group file. OnboardingTracking restores answers after app
restart, uses AnalyticsIdentity.installID, records start/question/setup/submit/final
completion events, and drains in the foreground. OnboardingPostHogUploader sends
allowlisted anonymous batch events with original timestamps, stable retry UUIDs,
recognized receipts, persistent backoff and destination-specific checkpoints.
No upload is allowed before the existing analytics disclosure. Plain visual-preview
mode is still memory-only; a separate explicit simulator fixture flag marks test data.

Architecture choice: the retention transport/config is private and uncommitted in the
other session. Do not import/copy or edit those files now. Use the same public batch
contract and configuration keys in a small onboarding adapter, leaving consolidation
until integration. No second SDK or identity is introduced. The event-based entry SQL
freezes the latest complete pre-session answer; later answers cannot rewrite it.

Changed in this branch: OnboardingView, one onboarding startup call in DoCardApp,
three new Onboarding analytics files, OnboardingTrackingTests, integration/proof SQL,
a synthetic Swift proof runner and docs. Not changed: shared identity/consent files,
retention code, shared config/Info.plist/project/CI files, models/migrations, permissions,
NFC, emergency unlock, subscription logic, or any other worktree's source.

Validation: 17 native iOS unit tests passed with 0 failures. Debug/ad-hoc-signed and
Release simulator builds reported BUILD SUCCEEDED. A real UI driver verified custom
answers and restore after terminating/relaunching the process (no duplicate unchanged
submission). Direct iOS-to-PostHog validation verified five screen-generated synthetic
events, matching install ID/arrays/custom answers. A separate live Swift fixture used
the exact retention calculator/builder read-only: 21 rows/21 unique UUIDs, including 15
onboarding and 6 retention records. Entry-label SQL returned expected study/exam/other,
work and unknown groups; period-1 test rates matched 1/1, 1/1, 1/1, 0/1 and 1/1.
All live records are marked development/is_synthetic. A temporary simulator disclosure
fixture was restored after the direct delivery check. No production deployment or
physical-device qualification is claimed. Production configuration stays owned by the
other branch and must be integrated before normal Release delivery becomes enabled.

Details and reproducible checks: docs/analytics/onboarding-tracking.md.

---

# 2026-11-03 — onboarding prototype review revision

User review requested shorter options, writable “其他”, no phone-time subtitle,
and removal of lifetime-loss calculations. Habit labels are now six short
single-clause options. Both multi-select pages show a free-text field when “其他”
is selected; nonblank text is required, retained in parent-owned memory across
back/forward navigation, and not uploaded. The calculation, good/bad-news
interstitial and lifetime-loss/recovery screens are removed from this flow;
phone time now leads directly to the existing permissions screen. The years
mapping is removed and the flow contains 12 screens. Unused legacy page files
are left intact rather than changing project structure during this prototype.

Changed: OnboardingView.swift, OnboardingMultiSelectPage.swift,
OnboardingSurveyPage.swift, prototype docs and this changelog. No app startup,
PostHog/identity/upload, session/locking, model/migration, authorization, emergency
unlock, NFC or subscription code changed in this revision.

Validation: Debug simulator BUILD SUCCEEDED. External temporary UI walkthrough
passed with 0 failures (41.568 s): two custom text inputs, blank-answer gating,
selection and typed-answer retention after back/forward, no phone-time subtitle,
and direct arrival at the permission screen. Native screenshots captured under
outputs/onboarding-native-revision in the review workspace. No physical-device
or release qualification claimed; no product test files added.

---

# 2026-11-03 — isolated onboarding UI prototype

Branch: `codex/onboarding-ui-prototype`, based on `392fe9e`. Selected design A
from the standalone prototype. This is UI review work, not a release or a PostHog
integration. See `docs/prototypes/onboarding-ui.md` for rationale and launch steps.

Changes: replace age with purposes; order purposes → habits → daily phone time;
use the user-approved Chinese questions/options; allow multiple purpose/habit
choices with checkboxes and count; preserve answers in parent-owned in-memory
state when navigating back; keep daily-time choices but require explicit Continue;
use stable purpose/habit IDs; wrap and scroll long options. Rejected for this
review: adding persistent profiles/identity or sending questionnaire data to PostHog.

Files changed: OnboardingView.swift, OnboardingMultiSelectPage.swift,
OnboardingSurveyPage.swift, plus a DEBUG simulator-only launch hook in DoCardApp.swift,
a prototype launcher, this changelog, and prototype documentation. The hook starts
at welcome without changing completed-state defaults or the device/Release entry gate.

Files not changed: analytics/upload clients, identity, retention code, models,
schemas/migrations, RequestAuthorization, Emergency Unlock, NFC, session/locking
logic, subscription implementation, and the other session's dirty worktree.

Validation: Debug simulator build reported BUILD SUCCEEDED. An external temporary
XCTest UI driver walked the real intro, purpose, habit, phone-time and summary
screens: 1 walkthrough, 0 failures (43.468 s). It checked empty-answer gating,
multiple selection, deselection, selection retention after back/forward, scrolling,
and explicit Continue for phone time. Native screenshots were captured. Git diff
whitespace check and launcher shell syntax passed. No test files were added to the
product. No physical-device, Release, permission/NFC pairing or release qualification
is claimed. This remains a throwaway branch for user review.

---

# DO Card — local change entry, 2026-11-02

This file records the current local implementation. It is not a replacement for the
external historical project changelog. Verification below was recorded before publication;
it makes no hosted-pass or release claim.

The user requested removal of Co-Focus and device synchronization before fixing the
remaining Selection & access review issues. ADR-0008 records the removal and scope:
UI, report card, startup services, NFC interception, external pairing, badges,
subscription advertising, session/extension network clients and the Supabase SDK.
The separate anonymous analytics REST upload retains its endpoint and payload format.
No backend, existing remote pairing credentials, external app repositories, original
dirty app checkout or historical source was changed.

The scheduled-expiry P2 was caused by importing a completed shared schedule snapshot
with absent break fields over a saved SwiftData row. Expiry imports now preserve saved
break facts and close open breaks at the snapshot's removal time. Ordinary imports keep
their behavior; no stored fields, schema versions, migration stages or upgrade fixture
change. A four-input regression covers completed/open breaks and foreground/background
cleanup, reports, actual removal time and repeated cleanup.

The unsigned-grant P2 was caused by applying an old unsigned-data migration to the new
subscriptionGrants key. That key now requires a valid existing HMAC and available key;
it cannot grant access, auto-sign or fall back to legacy flags if its authentication is
missing/invalid. Older keys retain their existing migration. The new regression writes
an unsigned fabricated grant alongside valid older flags and checks denial and no signing.

Implementation files changed for this request: app/Home/DO/Report/Settings/Premium views,
DOFocusButton, SettingsLayout, Entitlements, three NFC strategies, StrategyManager,
ScheduleTimerActivity/StrategyTimerActivity, DeviceActivityMonitorExtension, Shared,
BlockedProfileSessions, SubscriptionAccess, analytics client/aggregator, the Xcode project,
local test selection, Settings/entitlement/recovery/lifecycle tests and associated docs.
Retired client/model/view/string/test files and the unused SDK lockfile are deleted.
The Keychain helper only loses a retired-feature example in its comment.

Sensitive files not modified by this request: RequestAuthorizer, AppModelStore,
AppMigrationPlan, AppSchemaV1–V5, entitlement capability files, StoreKit production adapter,
purchase manager, report arithmetic helper, original upgrade fixture and CI workflows.
Physical DO Card pairing, Emergency Unlock and local schedule/session ownership remain.

Verification: all 142 exact selected XCTest methods passed (0 failed/skipped, no
missing/unexpected/duplicate IDs), including 48 access methods (44 fast and four
Apple-local StoreKit), 15 Settings layout methods and the previous 79-method portfolio.
The new break matrix first failed, then passed all four rows; the unsigned-grant test
first failed, then passed after strict authentication. The removal Debug build, final
Debug test build and arm64 Simulator Release build all succeeded. Summed method execution
was 5.9581 seconds; the complete final test command took 75.524 seconds. These are local
measurements, not hosted CI results or timing estimates.
Independent Standards and Spec reviews found zero new actionable issues. Source audit
confirmed no retired runtime references or SDK linkage, unchanged analytics connection,
valid catalog/runner syntax and 19 protected schema/fixture/configuration files unchanged.
Physical-device checks were not run and remain deferred. Existing remote clients/server
records are outside this removal; any old remote pairing/shield must be reset separately.

## Maestro UI smoke layer (local, 2026-11-02)

ADR-0009 adds five scripted UI smoke journeys after the current lower-level checks.
The GitHub workflow is initially opt-in through manual dispatch. It packages the
already-built Debug simulator app and reuses it in a downstream job, with pinned
Maestro and explicit simulator/runtime selection. JUnit validation requires exactly
five successful flows; artifacts are retained even after a flow failure.

A Debug-simulator-only launcher seeds an isolated persistent store, resets defaults
and the app HMAC key before services initialize, and preserves the store on resume
launches. Production views receive accessibility identifiers. No model/schema,
Family Controls authorization, extension, purchase or blocking behavior was changed.
Real-device testing was not performed; this layer covers simulator UI boundaries.
See docs/testing/maestro.md and the local validation report for commands and results.

## Core locking journeys replace basic UI smoke flows (local, 2026-11-02)

At the user's request, replace the five earlier smoke flows with four core journeys:
manual card lock/unlock, scheduled start/end, early card unlock during a schedule,
and complete Emergency Unlock. The last two check suppression after repeated schedule
delivery and app relaunch. The emergency path also checks one saved audit event and
one spent quota use. Add a lower-level manual-card round-trip test; local selection
is now 143 methods, hosted regression selection 79 plus the upgrade test.

ADR-0009 and docs/testing/maestro.md describe the boundaries. Real UI and production
session/policy/schedule/storage code are used; hardware, clock, OS writes and quota
storage are simulated only in Debug simulators. SharedData gains a simulator-only
runtime fallback; existing TaskLocal runtimes take precedence. StrategyManager's
Debug-simulator singleton accepts the test composition only for explicit fixture
launches. No model/schema or Family Controls authorization change is made. No push
or physical-device verification is included in this local task.

## Combined audit fixes and Maestro pipeline (local, 2026-11-02)

Combine the uncommitted local `codex/test-pipeline-audit-fixes` changes with the four
Maestro locking journeys in a separate `codex/combined-test-pipeline` worktree. The
remote branch was absent; both original source worktrees are preserved. Keep the
audit's shared selection/exact-ID gates, deterministic → serial StoreKit → two-process
upgrade → Release ordering and direct in-memory expiry-import history regression.
Keep the Maestro Debug-simulator harness, four journeys and manual opt-in final job.

The selected portfolio now has 139 deterministic methods, four StoreKit methods and
one upgrade method (144 unique /145 executions). The audit's added history method and
the manual-card integration method are both retained. Remove superseded hardcoded
workflow counts, update guard fixtures to recovery28/history8, and centralize app
packaging so local and hosted paths archive the same Debug app. A local complete-pipeline
entry point adds the optional Maestro stage without a second Debug compile. No source
model/schema, production Family Controls authorization, fixture data or branch protection
setting is changed by this integration. No GitHub push is included.

## Dedicated self-hosted CI with manual hosted fallback (YAN-85, 2026-11-02)

Routine CI now selects the repository-scoped ARM64 `docard-ios` runner in the separate
`docardci` macOS account. Manual dispatch can choose `hosted`; automatic fallback is
deliberately absent so an offline Mac does not unexpectedly spend hosted allowance.
The core and optional Maestro jobs share one self-hosted concurrency group, retain
the existing required-check name, and use separate per-run/attempt result/build paths.
The preflight uses the selected local Xcode, enforces the runner account, and validates
Xcode 26.2 readiness and the iOS 26.2 runtime. Hosted execution keeps its pinned Xcode path.
Same-repository trusted-author PR checks and read-only, non-persistent checkout credentials
reduce exposure; repository writers remain trusted. Job-scoped sleep assertions protect
the long-running core and UI commands.

Changes are limited to the CI workflow, preflight/helper tests, and CI documentation.
Exact method-ID selection, one Debug build, deterministic → serial StoreKit → separate
upgrade processes → Release ordering, reused Maestro app and failure artifacts remain.
No app/model/schema, fixture, authorization, purchase behavior, signing or billing settings
are modified. Actual workflow results are recorded separately from controlled guard tests;
full self-hosted and hosted-fallback acceptance require real runs.

The first real self-hosted core job passed 139 deterministic methods, four serial
StoreKit methods, both upgrade processes and Release. Three Maestro journeys passed;
the suite timeout interrupted the final journey amid slow runner status-bar snapshots.
The hosted fallback was selected correctly but GitHub billing blocked it before execution.
These are partial results, not a full pipeline pass. Diagnostic evidence is retained.
Inspection also found that attempt-specific app artifact names broke UI-only job reruns.
App artifacts now use the immutable workflow run ID, with replacement on a successful
core rerun; per-attempt result artifacts remain distinct. Actual UI retry verification
is required to establish recovery without repeating the core suite.

Focused UI probes rejected GUI visibility, foreground-account selection and the runner
security-session flag as explanations for the slow status-bar snapshots. The exact
tested app was fast in chen (about 0.07 seconds per status-bar lookup), while docardci
remained slow even through Terminal. Investigation found that the standard CI account
lacked developer-group membership and Apple's developer-tools mode was disabled.
Add an optional-UI-only readiness guard with lower-level controlled-response checks;
core checks remain available independently. Any actual authorization change is made
through a separate, reviewed native macOS administrator dialog, not through a CI job.
This records a prerequisite and a testable next step, not a claim of a latency fix.

Diagnostic uploads now require an initialized results directory even on failure.
Remove the Maestro upload path's trailing slash so a preflight failure with an unset
variable cannot turn the upload target into the filesystem root. A verification run
was stopped before the UI stage while this error path was corrected. No root-directory
artifact upload was executed. Workflow lint passes; final workflow execution is pending.

Native authorization subsequently enabled developer-tools mode and added docardci to
_developer without administrator membership. The next probe still had slow status-bar
snapshots despite the readiness checks passing. Stop treating this prerequisite as a
proven latency fix. The measured first full UI run had valid progress and three passing
journeys before the outer ten-minute cap interrupted the final journey. Give only the
optional self-hosted UI command a bounded fifteen-minute budget (25 minutes including
job setup); retain the hosted/local ten-minute default and every assertion/result gate.
Add three controlled-command tests, including a real one-second timeout after a passing
JUnit report, proving that the command failure still prevents a success marker and that
only the owned simulator is cleaned. Invalid or unbounded budgets are rejected before
device commands. Full final execution remains the acceptance proof.
