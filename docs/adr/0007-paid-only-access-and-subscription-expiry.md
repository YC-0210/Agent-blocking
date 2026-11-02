# 0007 — Paid-only access and subscription expiry

Status: user-approved rules; local implementation, 2026-11-02.

## Rules

This decision supersedes the old free tier and the old instructions that NFC starts
must always be free. NFC stops, Emergency Unlock, billing, help and legal access remain
available without a subscription. Other app functions require verified active access.

- Cancelling auto-renewal preserves the remaining paid period.
- Verified trials and redeemed free subscription offers count as active access.
- Billing grace is three days, paid-to-paid renewals only. The app honors Apple's
  verified grace end time; it never adds a local grace window. App Store Connect
  configuration is a separate deployment prerequisite, not changed by this work.
- Offline use lasts until the latest previously verified access end time.
- When access ends, clear all local DO Card restrictions as soon as iOS permits code
  execution. A foreground check and a dedicated DeviceActivity expiry event use the
  same cleanup operation. The API cannot guarantee exact-second delivery while asleep.
- Preserve saved profiles, selections, schedules and history. Cleanup uses no Emergency
  Unlock quota and creates no manual-stop suppression.
- Renewal resumes eligible schedules, including a currently active window. Existing
  manual-stop suppression still applies. An ended manual session requires a new card tap.
- End history at the cleanup/removal time, not the earlier subscription deadline. Close
  an open break at that time, retain the new ending reason, and subtract recorded breaks.
  Resumed blocking gets a new session ID. Late old callbacks cannot alter that ending or
  release the new session's restrictions.

## Implementation

`SubscriptionAccess` decides access from verified purchase periods and verified renewal
information, independent of the current wall clock, Apple services, UI and storage. Callers
supply the clock. `SubscriptionProduct` identifiers are shared by all relevant targets.

The new signed App Group `subscriptionGrants` snapshot records the facts used by the app and
monitor. The shared types also compile into the widget target. Old signed premium/expiration values are honored only through their
remaining verified end time, with no automatic extra days. A present but invalid new snapshot
cannot fall back to an old premium flag. The new grant key requires an existing valid
HMAC and an available signing key; the older unsigned-data migration does not apply to it. Debug force-tier behavior remains Debug-only.

`StoreKitSubscriptionStore` maps Apple's verified current entitlements and renewal status to
these facts. Free periods cannot create paid-to-paid grace. StoreKit changes cause a complete
refresh, rather than applying an event as though it were the latest state. Concurrent refresh
results have request generations so an older completion cannot erase a newer renewal.

`SubscriptionManager` starts from cached valid proof, checks access before loading the product
catalog, and listens to transactions and renewal-status changes. A failed refresh preserves
only still-valid cached proof. Foreground expiry and the background monitor share
`SubscriptionExpiry`. A stale expiry event rechecks the latest saved access before clearing.
The monitor repeats over a near-full-day interval aligned to the verified end clock time,
checking the absolute saved date on both boundaries. This avoids a short pre-expiry window
that the device might never use, and stays within Apple's one-week maximum interval.
Registration is refreshed when Screen Time authorization becomes approved. Actual delivery
is still a separate phone check.

The root app gate exposes only the agreed unpaid actions. Picker/profile writes, direct
strategies, app/shortcut starts, schedule activation, and the final restriction writer also
check access. The writer receives a full replacement plan and clears obsolete mode/browser
settings before applying it; allow-only mode has no subscription bypass. Existing 50-app
selection limit remains; the free three-app feature is removed.

The foreground coordinator reconciles both the SwiftData and shared-session stores. The
monitor queues completed snapshots for later import. The importer preserves subscription-ended
rows against stale snapshots. Expiry imports preserve break facts already saved in SwiftData
when a schedule snapshot lacks them, and close an open break at the removal time.
NFC stop callbacks ignore an already-ended session before any
restriction write. `SessionRow` displays the ending reason in English/Traditional Chinese.

No stored SwiftData properties, schema versions or migration stages change. Database model
changes are method/guard changes only. The 1.30.1 upgrade fixture remains unchanged.

## Test interfaces and limits

The agreed interfaces are access decisions, selected-action permission, selection validation/
restriction plans, the real shared store, real coordinator/strategy entry points, real profile
writes, expiry/import/report flows, and the production StoreKit adapter.

Tests replace the clock, NFC hardware and restriction writes at their external interfaces.
Recording sits below the production restriction gate. Integration fixtures use real SwiftData
and isolated signed defaults; one file-backed expiry case saves and reopens through the real
production store opener. Reopening a container/reader is not a new OS process.

StoreKit Test uses Apple's local environment and is serialized. Pure rules and narrow
integration checks run separately for rapid feedback. Table rows are not reported as separate
XCTest methods. The local runner rejects missing, skipped, unexpected or duplicate test IDs.

Real selection tokens, actual shields, independent background delivery, reboot, real purchases,
and offer-code redemption remain device/sandbox checks. Co-Focus and device synchronization
are removed from this app version under ADR-0008. Normal
app-host startup still runs its services; the entire host is not claimed to be network isolated.
