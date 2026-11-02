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
