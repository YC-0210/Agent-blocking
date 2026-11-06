# Railway physical lock/unlock verification — November 6, 2026

Current result: **PASS — actual X blocking, remote unlocking and automatic expiry through Railway**.
The initial failed tests below were followed by native diagnosis, a targeted repair
and successful physical-device tests, including a clean build with DO Card terminated.

The subsequent [ten-case physical regression suite](railway-ten-e2e.md) also passed
10/10 with the local server off and DO Card closed.

## Repair and final verification

The persisted pairing survived cold app launches, but Family Controls was not
initialized in the new main-app process. Apple's authorization status starts as
notDetermined until requestAuthorization succeeds; the existing cold-process
reconciliation deliberately preserves live sessions under an unknown status rather
than restoring shields. That combination allowed session receipts/state to look
healthy while native enforcement was not initialized.

The controlled diagnostic changed one variable: restoring the existing individual
authorization on launch. Before that refresh, the main app reported notDetermined
and an empty named shield store, with X accessible. Afterward it reported approved,
two shielded apps and a visible X shield. Saved native app selections were unchanged.

AgentFocusDevice.prepareAuthorization now restores that existing grant on the main
actor when its status is undetermined. AgentFocusRuntime awaits it before native
reconciliation or delivery. Existing denial handling remains in reconciliation;
permission errors cannot be turned into a fabricated approval. RequestAuthorizer,
approval UI, Emergency Unlock, native selections, NFC, legacy stores, subscription
gates, SwiftData and migrations are unchanged by this repair.

An attempted refresh inside the headless notification extension stalled delivery
and was removed. The final extension is unchanged. All temporary native tracing
and debug launch flags were removed before the final build.

Apple references:
- [authorizationStatus lifecycle](https://developer.apple.com/documentation/familycontrols/authorizationcenter/authorizationstatus)
- [WWDC22: startup authorization and silently restoring an existing individual grant](https://developer.apple.com/videos/play/wwdc2022/110336/)

The final signed Debug build passed and was installed over the existing app without
uninstalling or resetting pairing/selection. All 89 Swift tests passed. The native
authorization lifecycle is outside the Foundation package-test seam; the physical
red/green check is the regression evidence for this issue.

Final clean-build run, November 6 at 19:43 Taipei time:

| Check | Evidence | Result |
| --- | --- | --- |
| Foreground bootstrap | Fresh phone snapshot after app launch and authorization restoration | Passed |
| Cold/background start | Main app and any existing notification extension terminated; Railway start `fixed-start-1fa6ebb4-bc92-48b3-b34a-f17d8181f558` acknowledged applied | Passed |
| Actual native lock | X launched and showed the Screen Time shield stating X cannot be used because it is restricted | Passed |
| Remote stop | Railway stop `fixed-stop-b47f8bba-c94c-45e7-88b0-0e9e7a9945c7` acknowledged applied | Passed |
| Actual native unlock | X launched normally and displayed its feed without the shield | Passed |
| Cleanup | No active session; same mode handle, two selected apps and maximum 45 minutes | Passed |

Session: `railway-fixed-df96c441-f9f9-410b-a572-19d2688178df`. Both commands were
sent to the Railway HTTPS origin, using the phone's existing approval. Neither
command required opening DO Card to execute. A preceding diagnostic-build cold
cycle also produced a visible shield-to-normal-X transition. Screenshots and
private command evidence are retained locally, excluded from Git. Device screenshot
transport failures in earlier attempts were distinguished from phone execution;
the final clean run captured both screens successfully.

Automatic expiry passed in the subsequent test below. Reboot recovery and offline
operation remain untested.

## Automatic expiry with the Mac relay stopped

November 6, 2026, 19:50–19:52 Taipei time: **PASS** on the same clean installed build.
The local relay was supervised by launchd and restarted after SIGTERM. Both jobs
`online.do.card.focus-relay` and `online.do.card.focus-tunnel` were therefore booted
out before testing. Port 8787 had no listener before the start or after expiry;
neither launch service was loaded at the final check. They remain stopped.

DO Card and its existing notification extension were terminated before the request.
The test never launched the main app, and no stop command was sent. A two-minute
start was posted directly to the Railway HTTPS origin using the existing approval:
`expiry-start-c89e6971-9574-4fcf-9f29-57c596eb3d3c`, session
`railway-expiry-3b24502d-568f-46ba-817b-ca662682d5ce`. APNs accepted it and the
phone acknowledged applied.

| Check | Taipei time | Result |
| --- | --- | --- |
| Start issued | 19:50:26.862 | Two-minute deadline recorded |
| Initial X capture | 19:50:35.943 | Native restriction shield visible |
| Pre-expiry X capture | 19:52:17.142 | Still shielded, 9.720 seconds before deadline |
| Scheduled deadline | 19:52:26.862 | No manual action or stop command |
| Phone snapshot received by Railway | 19:52:28.502 | sessionID and endAt cleared, 1.640 seconds after deadline |
| First post-expiry X capture | 19:52:30.990 | Normal X feed visible, 4.128 seconds after deadline |
| Follow-up X capture | 19:52:42.766 | Still accessible |

Final process inventory showed the notification extension only; the main DO Card
process was absent. Maximum remained 45 minutes with the same two selected apps.
Expiry correctly set requiresRenewalApproval to true; no renewal was approved.
The phone is left without an active session and DO Card remains closed.

This establishes automatic expiry in the deployed Railway configuration with no
local server and no main-app opening. The observations bound the visible unlock
rather than measure its exact millisecond. Native DeviceActivity expiry and the
Railway APNs expiry backup were both enabled; this run does not isolate which
mechanism removed the shield first. Private evidence is in ignored
`.local/automatic-expiry.json`; screenshots remain outside Git. No app/server code
changed for this test.

## Initial failed verification (before repair)

The owner explicitly requested actual lock/unlock testing after restarting Codex.
The reconnected tool reached Railway, but its default device ID still referred to
the old relay. Explicit cloud device ID `e39937d5-a7a9-4147-b1e3-48b2b7953ccd`
worked. The saved default was corrected to that ID; no new pairing was created.

## First session

- Start request: `railway-lock-7345cd53-fc2b-4b20-8a33-5400ebbd7e27`.
- Session: `railway-test-cbdfb2f9-4c7f-496a-b012-169879e8de1c`, two minutes.
- APNs accepted delivery; the paired phone acknowledged `applied` and published
  the matching active session and absolute deadline.
- Launching X (`com.atebits.Tweetie2`) on the paired iPhone showed normal X
  content, without a shield. The owner subsequently confirmed the two selected
  apps were Instagram and X. Instagram could not be launched by CoreDevice in
  this run, so no Instagram enforcement conclusion is claimed.
- Stop request: `railway-unlock-cbdfb2f9-4c7f-496a-b012-169879e8de1c`.
  APNs accepted it and the phone acknowledged `applied`; status returned no
  active session.

## Foreground reconciliation comparison

- DO Card was brought to the foreground before the second two-minute start.
- Start request: `foreground-lock-45e075d2-d819-474a-840b-caaa2715a217`.
- Session: `railway-foreground-6cf69a8f-09b6-4085-8299-0822b6088a56`.
- The phone again acknowledged `applied`. DO Card was relaunched to exercise
  foreground reconciliation; a fresh snapshot retained that active session.
- X still showed normal app content, without a shield. This is not explained
  solely by failed push delivery or lack of a main-app foreground reconciliation.
- Stop request: `railway-foreground-unlock-6cf69a8f`. The phone acknowledged
  `applied`. Both test sessions were deliberately stopped; neither was renewed.

## Limits and next investigation

`applied` receipts prove the phone processed the command, not that Screen Time
visibly enforced a shield. Stop receipts and cleared session state establish test
cleanup; because visible blocking was not observed, a visible blocked-to-unblocked
transition has not been proven. Automatic expiry was not tested in this run.

The native picker showed two selected social apps and the owner confirmed their
names without changing the selection. No app selection or maximum was modified.
Attempting to read the existing token-free expiry diagnostic file through
CoreDevice was denied by its container access policy; that restriction was not
bypassed. No opaque Screen Time tokens, phone credentials or usage data were
exported. Screenshots were inspected locally and are not committed.

Investigate native authorization, saved-selection validity and actual named-store
enforcement using a physical-device pass/fail loop before making further native
changes. No native code was changed by this verification run.
