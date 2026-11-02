# Selection & access and local-focus verification

Recorded 2026-11-02, before publication. **142 selected XCTest methods passed; zero
failed or skipped.** Exact source/executed identities matched, without missing,
unexpected or duplicate methods. Debug and arm64 Simulator Release builds passed.

This includes 48 Selection & access methods (44 fast and four Apple-local StoreKit),
15 Settings layout methods and the earlier 79-method regression portfolio. The complete
command took 75.524 seconds; summed method execution was 5.9581 seconds. These are local
observations, not hosted runtime estimates. Input-table rows are not separate methods.

The next app version removes Co-Focus and device synchronization: screens, report card,
external-device pairing, badge, premium advertising, startup clients, NFC interception,
foreground/extension sync calls and the Supabase SDK. Local DO Card pairing remains.
Analytics retains its independent REST upload and false/zero retired-feature columns.

Before/after evidence:

- Scheduled expiry initially erased saved breaks: 09:00–09:40 with a ten-minute break
  reported 40 minutes. It now preserves the break and reports 30 minutes. An open break
  from 09:10 closes at removal 09:40 and reports ten minutes. The new method covers
  foreground/background cleanup, later import and repeated cleanup in four input rows.
  Before the fix, that method failed while the other 57 fast methods passed; the
  subsequent 58-method run passed.
- A fabricated unsigned new grant initially granted premium and was automatically signed.
  The new regression initially failed while the other 58 methods passed. Strict HMAC
  verification now denies it, prevents legacy fallback and does not sign the data.
  Older keys keep their existing upgrade behavior.
- The final 142-method run passed after both fixes. Two independent read-only reviews
  found zero actionable Standards findings and zero Spec findings.

No stored SwiftData fields, schema versions, migration stages, original upgrade fixture,
Family Controls authorization implementation or entitlement capability files changed.
Source audit confirmed 19 protected files unchanged and no retired runtime references or
SDK linkage. The original dirty app checkout and historical sources were not changed.

The existing hosted workflow still selects 79 unique app methods / 80 executions because
upgrade runs in two processes. It does not explicitly select the new access suites or
Settings layout suite. Its eventual status must not be read as a hosted 142-method result.
No new hosted result is recorded here. This local run used the default upgrade method once;
the separate two-process rehearsal was not repeated.

Phone checks remain deferred: real tokens, shields, NFC hardware, independent OS delivery,
reboot, offers and production purchases. App Store Connect's three-day paid-to-paid grace
setting remains a separate requirement. Normal host services still start; whole-host network
isolation is not claimed. Backend records, saved pairing credentials and external browser/
iPad apps are untouched; old remote pairings/shields need separate unpair/reset or retirement.

- [Exact identities, timing, before-fix evidence and source audit](selection-access-local-142.json)
- [Current agreed cases and local runner](../selection-access.md)
- [Paid-only access decisions](../../adr/0007-paid-only-access-and-subscription-expiry.md)
- [Feature removal decision](../../adr/0008-local-focus-without-device-synchronization.md)
- [Earlier 125-method HTML record](../selection-access-125-archive.html)
