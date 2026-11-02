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
