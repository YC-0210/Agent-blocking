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

## Background scheduled retention authorization observation — 2026-11-04

Physical capture breadcrumbs established the missing start: the DeviceMonitor
process returned auth=false while paid=true and shields=true; the main app later
returned eligible=true and repaired the start. The prior retest therefore proved
foreground recovery, not a wholly background session.

SharedData now holds a signed retentionAuthorizationApproved observation. Only
the main app writes it, from RequestAuthorizer's initial state, request outcome
and authorization-status publisher. The existing strict HMAC reader rejects absent,
malformed, unsigned or tampered values. The schedule monitor uses this observation
for analytics eligibility instead of its unreliable process-local AuthorizationCenter
value. Strategy-timer completion's scheduled restoration uses the same observation.
Actual authorization requests, DeviceActivity registration, shields, subscription
and nonempty-plan checks remain unchanged. This observation grants no OS permission.
There is no arbitrary time-to-live: that would silently drop unattended schedules
when the app is not reopened. Revocation observed by the app writes false; OS
permission enforcement remains authoritative while the app is suspended. Do not
claim this cached observation independently detects every revocation in real time.

Regression: before switching the monitor check, the shared-approved background
start/stop test failed with no recorded session/zero seconds. After the change,
the production start/stop path records its exact time without StrategyManager or
foreground recovery. Added missing/invalid-signature/tampered/revoked observation
coverage. Existing snapshot/journal schema, identity, earlier contributions, upload
checkpoints and backoff are unchanged. No historic sessions are fabricated.

Physical background-only capture remains a user-run test after installation.
Build/test and direct phone verification results are recorded in the handoff.

## Scheduled capture recovery and direct phone log access — 2026-11-04

Direct devicectl reads now succeed for this connected iPhone's App Group. The local
activity log, retention development journal and selected shared preferences were
retrieved read-only. The journal contains exactly the two known manual sessions;
no pending uploads or backoff. Extension callbacks for the two tested schedules
ran but neither scheduled start exists in the journal. Which original extension
eligibility check or write failed is not established by the historical log.

Fixed two independently demonstrated gaps: ScheduleTimerActivity's existing-session
branch returned after applying shields without recording start, and foreground
scheduled reapplication never repaired a missing start. Both now invoke the same
idempotent journal start, retaining authorization, premium and nonempty shield-plan
checks. New and existing scheduled extension paths share a capture helper. Tests
inject only the authorization observation and shield writer, never bypass policy.

Debug-only bounded capture-attempt breadcrumbs include eligible flags, process,
environment, session ID and local write errors. They are diagnostic, not source
facts, can lose a concurrent diagnostic line, and are never uploaded. No card IDs
or tokens logged. Shared-data HMAC, entitlement checks, stored SwiftData schema,
schedule windows, actual restriction behavior, subscription policy and journal
exclusion rules remain unchanged. Existing old scheduled sessions are not fabricated
or backfilled from approximate log timestamps. YAN-96 foreground scheduling remains
separate and unresolved.

52 focused tests passed (9 capture, 15 journal, 28 unlock recovery), zero failures.
Signed Debug device build passed. Release build and phone install metadata are
reported in the accompanying verification artifact. Physical scheduled capture
still requires the next user test; these results are not an end-to-end phone pass.

## Read-only retention diagnostic summary — 2026-11-04

Settings Debug log copies now prepend the journal's last 12 sessions, completed
contribution totals, exclusion state, pending event count and upload retry state.
The summary reads the current development journal and destination checkpoints and
never writes completions, clears data, resets backoff or sends events. It prints
no host/token, card IDs, profile selection or full model data. Existing activity
logs remain below it. This diagnoses the confirmed extension-stop/main-app-empty
handoff without guessing which local retention facts survived.

## Debug log panel reload-loop fix — 2026-11-04

DebugLogPanel.load changed refreshTick, which was also the view's .id; onAppear
called load again after each identity replacement. Removed the identity mutation:
normal @State updates now refresh the text/size without recreating the panel.
Added borderless button style to the action row so Form does not treat its three
buttons as a single row-wide automatic button action. No buffer is cleared on open
or Refresh; Clear remains an explicit separate user action.

## Reachable Debug log panel — 2026-11-04

Settings > Debug previously exposed only the subscription override. Recent Log was
present in the older DebugView, which had no navigation entry. The existing
DebugLogPanel is now shown directly in the Settings Debug category, with its
Refresh and Copy controls. The section is compiled only in Debug. No logging data
is cleared, exported automatically, or uploaded; this change only exposes the
existing local buffer. No subscription, schedule or retention behavior changes.

## Schedule end-time control — 2026-11-03

The compact end-time DatePicker was nested inside a Menu label. Tapping the time
therefore opened the ending-method menu instead of editing the time. The ending
method now has its own menu row; specific-time schedules show a separate directly
interactive time-picker row. Card-tap schedules hide that row, and the existing
next-day badge/toggle and schedule validation/save bindings are retained.
Only ScheduleTabView.swift and this entry change for this fix. No timer registration,
retention capture/upload, model schema, pairing or subscription behavior changes.
Physical picker interaction and scheduled start/end remain device checks.

## Debug paired-card capacity — 2026-11-03

For physical PostHog testing with additional DO Cards, OnboardingManager.maxPairedCards
is 100 in Debug and remains 5 in Release. Settings' count/availability and pairDOCard's
capacity guard already use this single constant, so both paths change together.
Existing paired IDs are retained. Cards must still be valid and explicitly paired;
NFC ID checks, duplicate rejection, profile propagation, subscription access, retention
capture, stored schema and migration code are unchanged. Only OnboardingManager.swift
and this changelog change for this request. Physical tapping of the newly paired card
remains a user device check; no claim of a completed locking test is made.

## Required subscription screen close control — 2026-11-03

The physical retention test exposed a nonfunctional X: SubscriptionRequiredView
embeds PaywallView as the root, where the environment dismiss action has no presented
screen to close. PaywallView now exposes showsCloseButton (default true), and the
required root screen passes false. A genuinely presented paywall retains its close
action. The paid-only access decision in ADR-0007 is unchanged; returning to Home
without access was rejected as a change to that policy.

Files changed: PaywallView.swift, SubscriptionRequiredView.swift and DoCardApp.swift.
The opt-in --debug-premium-test launch argument sets the existing Debug preference
for physical QA when LLDB cannot complete its device attachment. The argument handler
is compiled out of Release; no real purchase/grant is created. Settings > Debug can
restore the real tier after testing.
No subscription
verification, purchase, NFC, authorization, Emergency Unlock, retention capture,
SwiftData properties or migration code changed. The existing Debug Premium override
can be used separately for the physical analytics test; it does not purchase or alter
the account subscription and is compiled out of Release. Build/device verification
is recorded in the accompanying test handoff, not asserted here before execution.

## PostHog retention upload — 2026-11-03

ADR-0012 adds retention-only batch API delivery, using the durable journal as the
source and separate per-destination revision checkpoints. This replaces the initial
SDK transport proposal: HTTP acceptance is explicit and no SDK automatic events start.
Only cohort entry and daily contribution events are sent, with saved anonymous install
identity, original timestamps, cohort timezone, revision and zero retractions.

Main-app foreground delivery checks the existing disclosure gate, uploads batches of
at most 50, and retries with persistent exponential backoff. Facts are retained after
acceptance. HTTP 2xx requires a recognized JSON success receipt; current Cloud's
string Ok receipt is covered by a regression test. Corrections made during upload
remain pending. Cancellation does not add backoff. Offline schedules upload on a later
main-app foreground; there is no background-delivery guarantee.

No project host/token defaults are in Swift. Ignored local xcconfig or CI settings
configure the app. Both expanded Debug/development and Release/production Info.plist
values were verified. Separate App Group journals prevent development activity from
entering production. The previous unshipped scratch journal is not imported or deleted.

All 202 deterministic native methods passed on Xcode 26.2 / iOS 26.2 iPhone 17 Pro
Simulator (16 new upload tests, 63 retention tests total), exact IDs checked, zero
failed/skipped. Debug generic Simulator and arm64 Simulator Release BUILD SUCCEEDED.
All 22 controlled-response CI checks passed. The 57 pure calculator/journal/upload
methods passed in the temporary macOS SwiftPM harness.

The identical Swift client uploaded marked development test fixtures to PostHog
project 706779. Final successful proof: five events, replay five after checkpoint loss,
two correction events, then zero pending. PostHog contained seven unique revisions;
latest-revision SQL yielded 3,000 seconds in each period, matching Swift, including a
zero retraction. Original timestamps, anonymous properties and placeholder event IP
were checked. One earlier diagnostic fixture remains marked synthetic/development;
no production users or existing insights/settings were changed.

No SwiftData schema, report arithmetic, NFC validation, authorization, subscription
policy or Emergency Unlock behavior changed. Physical-device App Group, offline and
terminated/locked schedule checks remain required before release. Local changes remain
uncommitted and unpushed; the original dirty desktop checkout is untouched.


## Durable local retention capture — 2026-11-03

ADR-0011 adds the App Group retention journal and local runtime capture. The first
confirmed post-baseline session fixes cohort identity/timezone. Foreground successful
callbacks save before capture; failed timer registration does not enter a cohort.
Scheduled starts and timer/schedule completions are captured across app/monitor
paths. Saved Emergency Unlock contributes actual time outside recorded breaks.

The journal serializes readers/writers with a BSD file lock and atomic state writes.
Replay does not add seconds; corrections have monotonic revisions and retain zero
retractions. Break facts survive imports without break fields. Ambiguous stale-session
recovery is excluded without removing the original cohort denominator. Known existing
installs are classified separately; insufficient evidence remains unknown.

Added RetentionJournalTests (15) and RetentionCaptureTests (6), for 47 retention
methods including the prior calculator's 26. All 186 selected deterministic methods
passed on iOS 26.2 iPhone 17 Pro Simulator, exact IDs verified, zero failures/skips.
Debug generic Simulator BUILD SUCCEEDED (app, monitor and widget); arm64 Simulator
Release BUILD SUCCEEDED. All 22 controlled-response CI checks passed. The 41 pure
calculator/journal tests also passed in the temporary macOS harness.

Removed the HomeView call to the old deleted-project daily reporter. No PostHog SDK,
transport, production events or remote settings were added. No @Model properties,
migrations, report arithmetic, NFC validation, authorization or subscription policy
changed. The original dirty desktop checkout remains untouched. Physical-device
Tier 1 + Tier 2 + relevant NFC checks remain required before release; no release or
continuous OS-shield verification is claimed. Changes remain local and uncommitted.


## Retention calculator — 2026-11-03

Added a pure `RetentionTimeCalculator` for the agreed PostHog metric: at least
7,200 completed locked seconds total in each fixed three-calendar-day period.
Day 1 is the first successful post-instrumentation session's calendar date,
using the saved cohort timezone. ADR-0010 records the contract and alternatives.

The calculator allocates completed-session time across local midnights and period
boundaries, subtracts clipped breaks (including an open break through session end),
uses real elapsed seconds through DST, and leaves incomplete periods pending.
Repeated identical session inputs count once; conflicting versions or invalid
timestamps fail explicitly. Later finished data can recalculate earlier periods.
Trigger and ending-reason weighting is not applied. Runtime capture and delivery
are not wired in this change.

Files added: `DoCard/Utils/Analytics/RetentionTimeCalculator.swift`,
`DoCardTests/RetentionTimeCalculatorTests.swift`, and ADR-0010. Updated the deterministic
CI selection and its controlled-response fixture for the 26 new methods (165 selected
deterministic methods total), plus the CI guide and project context.

No session model, report duration helper, schema/migration, shared-state key,
extension, RequestAuthorization, Emergency Unlock, NFC trigger, access gate or
PostHog configuration was modified. The original dirty desktop checkout is separate.

Verification on Xcode 26.2 / iOS 26.2 iPhone 17 Pro Simulator: Debug `BUILD SUCCEEDED`;
26 retention methods plus the existing duration method passed (27/27, zero
failed/skipped, exact method IDs verified); arm64 Simulator Release `BUILD SUCCEEDED`.
All 22 controlled-response CI checks passed. The same 26 tests also passed through
a temporary macOS SwiftPM harness using the identical source and XCTest files.
The six-install worked example matches the PostHog proof: 3, 2, 2, 0 active installs
across four completed periods. Core red-to-green runs covered initial contributions,
midnight splitting, break subtraction, aggregation, duplicate handling and invalid input.

No physical-device or production event-delivery tests were run. This is not a release
or collection claim; data capture, cohort persistence, ingestion and device delivery
remain the next implementation step. No SwiftData migration rehearsal is triggered.

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
