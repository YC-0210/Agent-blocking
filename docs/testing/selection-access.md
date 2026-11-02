# Selection & access — local test guide

The new rule is paid-only access, with recovery/billing/help/legal exceptions. It replaces the
old three-app free tier. Co-Focus and external-device synchronization are removed from this
version (ADR-0008); physical DO Card pairing remains. The approved decisions and app interfaces are in
[ADR-0007](../adr/0007-paid-only-access-and-subscription-expiry.md).

## Cases and passing results

A case group may have several input rows or XCTest methods. Method counts are taken from the
executed result bundle, not the number of rows in this document.

| Case | Inputs and passing result | Main checks |
|---|---|---|
| A1 | No verified purchase: no paid access. | SubscriptionAccessTests |
| A2 | Valid monthly/annual purchase: access until its verified end. | SubscriptionAccessTests |
| A3 | Verified trial/free redeemed offer: access during the offer, none after it. | SubscriptionAccessTests |
| A4 | Cancel auto-renew in Apple's local StoreKit environment: retain paid access. | StoreKitAccessTests |
| A5 | One second before / exactly at / one second after expiry: yes / no / no. Expired legacy premium flag grants nothing. | SubscriptionAccessTests |
| A6 | Paid-to-paid confirmed grace: retain access before the exact verified grace end; stop at/after it. | SubscriptionAccessTests |
| A7 | Expired paid time without grace, or failed first payment after a free period: no extra days. Old local 16-day extension is removed. | SubscriptionAccessTests |
| A8 | Offline saved proof: usable only until its known paid/grace end time. | SubscriptionAccessTests, shared reader |
| A9 | Unverified, revoked, future or unrelated purchases grant nothing; an unrelated invalid entry does not remove another valid purchase. | SubscriptionAccessTests, SubscriptionStoreTests |
| A10 | Expired/new valid entries in either order retain valid access. An older pending refresh finishing last cannot erase a verified renewal. | SubscriptionAccessTests, SubscriptionRefreshTests |
| B1 | Without access, normal feature capabilities are disabled; with access they are enabled. | EntitlementsTests, root app gate, actual start checks |
| B2 | Recovery, purchase/restore/manage, help/legal remain permitted without access. | SubscriptionAccessTests, actual unpaid purchase/restore checks |
| B3 | Paid selection counts 0/3/4/49/50 accepted for saving; 51 rejected. Unpaid saving always rejected. Empty selections still do not start ordinary block-mode shields. | SelectionRulesTests |
| B4 | Selected app/category/web identifiers are preserved. Websites do not consume app slots. Custom domain rules remain separate from selected Safari tokens. | SelectionRulesTests |
| B5 | Correct block-selected / allow-only-selected direction when paid. Both modes denied when unpaid; allow-only is not a bypass. | SelectionRulesTests, SelectionEnforcementTests |
| B6 | A replacement plan drops old selections/mode/browser-token settings. Actual production adapter forwards the current plan and clears on expiry. | SelectionRulesTests, SubscriptionLifecycleTests |
| I1 | A newly constructed reader sees the same signed access and deadline; missing/damaged/unsigned snapshots do not grant access or revive old premium flags. The new grant key never auto-signs unsigned data. | SubscriptionLifecycleTests |
| I2 | App, background/shortcut, deep-link, direct NFC strategy and schedule entry points cannot create an unpaid active session or block command. | SubscriptionLifecycleTests |
| I3 | Access expires while NFC scan/editor is open: completing the callback/save cannot start blocking or change saved profiles. Failed create/clone/update leave saved data intact. | SubscriptionLifecycleTests |
| I4 | Manual/scheduled expiry removes restrictions and ends history once. Repeated cleanup does not extend history, delete settings or consume Emergency Unlock uses. | SubscriptionLifecycleTests |
| I5 | Late shared snapshots/schedule callbacks cannot reblock or overwrite the ended row. A late card callback cannot extend that row or clear a renewed session's blocking. | SubscriptionLifecycleTests |
| I6 | Renew during an eligible enabled window: resume automatically. Outside window, disabled schedule, or manually stopped current window: remain stopped. An ended manual session needs a new card tap. A stale expiry event after renewal does nothing. | SubscriptionLifecycleTests |
| I7 | Verified purchase/restore updates real signed storage. Cancelled/pending/unverified/failed purchases grant no new access; failures retain still-valid offline proof. Verified loss clears access. Real local StoreKit tests exercise purchase, restore, refund and renewal cancellation through the production adapter. | SubscriptionStoreTests, StoreKitAccessTests |
| I8 | Start09:00 / deadline09:30 / removal09:40 / break10min: save09:40 and count30min, reason Subscription access ended. Renewal creates another ID. Saved scheduled-session breaks also survive foreground/background expiry import; open breaks close at removal time. History, profile links, domains and schedules survive file-store reopen. | SubscriptionLifecycleTests |

## Fast feedback

- Rule tests use explicit clocks and values; boundary tests advance time directly. There are no
  sleeps for subscription/grace duration.
- Existing XCTest is retained. `SubscriptionStore` scripts only the external purchase responses;
  the manager, policy, signed store, session logic and report queries remain real.
- `AppBlockerUtil(write:)` records commands after the real access/selection gate. It does not
  replace the gate with a fake success.
- Most persistence fixtures use in-memory SwiftData and a unique UserDefaults suite/signing key.
  The expiry-history reopen case uses a real temporary file and the production store opener.
- StoreKit Test runs separately and serially against Apple's local purchase environment, with
  dialogs disabled and transactions cleared between cases. These few framework cases use the
  SDK's real-time clock; the rule/lifecycle matrices retain fixed clocks. No real purchases are made.
- The runner checks exact executed method IDs, no skips, no duplicates, and passing results. An
  empty or partial run cannot pass. Each test has a 30-second execution allowance.
- The old free-tier tests are replaced. Duplicate trace assertions were removed after the
  comprehensive cases covered them. Existing schedule, recovery, report arithmetic and upgrade
  tests remain, rather than repeating their matrices in this suite.

## Run locally

Use a dedicated simulator. The local iOS26.3.1 runtime exhibited StoreKit Test Code3; Apple
[documents a matching StoreKit Test issue](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-26_5-release-notes).
The local StoreKit checks use an added iOS26.2 (23C52) simulator with Xcode26.2. Adding the runtime
is a one-time environment task, not test execution time.

```sh
python3 scripts/selection-access/run_local.py --mode fast \
  --simulator YOUR_SIMULATOR_UDID --derived-data /path/to/derived-data \
  --results /path/to/new-fast-results

python3 scripts/selection-access/run_local.py --mode storekit \
  --simulator YOUR_IOS_26_2_SIMULATOR_UDID --derived-data /path/to/derived-data \
  --results /path/to/new-storekit-results

python3 scripts/selection-access/run_local.py --mode all \
  --simulator YOUR_IOS_26_2_SIMULATOR_UDID --derived-data /path/to/derived-data \
  --results /path/to/new-full-results
```

`fast` selects 44 access rule/small integration methods plus 15 Settings layout checks
for removal of the device-sync entry (59 total). `all` selects 142 methods: those 59,
four Apple-local StoreKit methods, and the earlier 79 regression methods.
The two new access methods extend I1 (unsigned grants) and I8 (scheduled breaks);
parameter rows are not counted as extra methods.

`fast` selects the rule/small integration suites and the changed Settings layout suite. `storekit` selects only Apple's local framework
checks. `regression` adds the earlier79 methods; `all` also includes StoreKit. This is the agreed
selected portfolio, not a certification of older, unreworked test classes in the repository.
The default upgrade method runs once here; the separate two-process upgrade runner remains
available and is not duplicated in this suite. Compilation/app launch time is reported separately
from the sum of executed method durations. The test target still launches the host app.

## App changes and limits

See ADR-0007 for the shared access snapshot, production StoreKit adapter, root/picker/profile/
strategy gates, full restriction replacement, expiry monitor, session cleanup/import guards,
and English/Traditional Chinese expiry reason.

No stored SwiftData fields/schema/migration stages or upgrade fixture changed. Original source
folders and customer conversations are untouched. Existing recovery fixtures explicitly grant
paid access, so those tests still exercise recovery rather than unintentionally denying starts.

The GitHub workflow is unchanged in this local implementation. New suites are compiled but must
be explicitly selected/verified when adding this work to the CI gate. No hosted run is claimed.

Before release, separately confirm App Store Connect **3-day grace / paid-to-paid renewals**.
Local fixtures cannot configure or certify the production App Store setting. Real-device checks
remain for selection-token storage, actual shield replacement/removal, app-closed expiry,
reboot, offer redemption and real purchase/restore configuration. Co-Focus and device-sync runtime clients are removed; no backend retirement, remote
unpairing/reset or browser/iPad app change is performed by this local task. The normal app host still starts its services;
only the test fixtures' dependencies are controlled. Reopening a reader/container is not an OS
process restart, and an expiry event executed in a unit test does not prove background delivery.

## References

- [The Practical Test Pyramid — small tests and narrow integration checks](https://martinfowler.com/articles/practical-test-pyramid.html#IntegrationTests)
- [Avoid repeated high-level matrices](https://martinfowler.com/articles/practical-test-pyramid.html#AvoidTestDuplication)
- [Apple: local StoreKit testing](https://developer.apple.com/documentation/xcode/setting-up-storekit-testing-in-xcode)
- [Apple: billing grace options and paid-to-paid setting](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions/)
- [Apple: background interval-end delivery](https://developer.apple.com/documentation/deviceactivity/deviceactivitymonitor/intervaldidend%28for%3A%29)
