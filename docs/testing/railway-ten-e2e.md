# Railway physical end-to-end suite — November 6, 2026

**Result: 10/10 passed.** Main run: 20:14–20:17 Taipei; case 1 visual retry completed at 20:18.

These are real deployed Railway HTTPS → APNs → paired physical iPhone → receipt/
snapshot checks, with screenshots manually inspected for the actual X shield or
normal X content. They are not mocked unit tests. Case 4's conflicting-ID branch
and duplicate requests are intentionally handled at the relay boundary; their
unchanged physical session/shield was also checked. This suite exercises the
command delivery path directly, not the MCP picker or native approval UI.

Both local launchd relay/tunnel services stayed unloaded, with no port 8787
listener. The main DO Card app and existing notification extension were terminated
before the suite. DO Card was never opened by the suite or its retry. No reinstall,
new pairing, selection edit, policy/maximum change or renewal approval UI mutation
was performed. The owner's explicit request authorized the two short test starts;
their renewalConfirmed fields were true. Case 10 deliberately omitted that field.

| # | Test | Observed result | Status |
| --- | --- | --- | --- |
| 1 | Unapproved mode | Phone rejected mode_not_approved; no session; X accessible. | PASS |
| 2 | Above approved maximum | 46-minute request rejected duration_exceeds_approval; maximum stayed 45; X accessible. | PASS |
| 3 | Cold start | Two-minute start applied with main app terminated; matching session/deadline; X shield visible. | PASS |
| 4 | Start retries and conflicting reuse | Identical request returned the same sequence/deadline; changed payload returned HTTP 409 command_id_conflict; X stayed shielded. | PASS |
| 5 | Wrong-session stop | Phone rejected session_mismatch; active session/deadline unchanged; X stayed shielded. | PASS |
| 6 | Valid remote stop | Phone applied stop; session cleared; X accessible. | PASS |
| 7 | Duplicate stop | Same applied receipt and sequence returned; no session recreated; X accessible. | PASS |
| 8 | Old stop against new session | New two-minute session applied; new command targeting old session rejected session_mismatch; new deadline preserved and X shielded. | PASS |
| 9 | Automatic expiry | X shield visible before deadline; session cleared automatically; X accessible afterward without stop or main-app opening. | PASS |
| 10 | Unconfirmed renewal | After expiry, start without renewalConfirmed rejected renewal_approval_required; no session; X accessible. | PASS |

## Expiry timing

Deadline: **20:17:39.161 Taipei**. The pre-expiry shield capture finished at
20:17:31.438. Railway received the cleared phone snapshot **0.603 seconds**
after the deadline. The first post-expiry X capture finished at 20:17:42.555,
**3.394 seconds** after the deadline, showing normal X content.

These observations bound visible unlock time; they do not measure the exact instant.
Native DeviceActivity expiry and the Railway APNs backup were both enabled, so this
suite does not isolate which completed first.

## Evidence and retry

The first case 1 screenshot was entirely black during launch and was not accepted
as visual evidence. The capture helper's settling delay was increased and the
entire case was rerun with a fresh command: rejected mode_not_approved, no session,
and normal X content. An optional blank-image check could not run because Pillow
was absent; it was removed and manual image review retained. These were test-harness
issues, not observed product failures. No app/server code change was needed.

Raw requests, phone receipts, snapshots and timestamps are retained in ignored
`experiments/agent-focus/.local/ten-e2e.json` and `ten-e2e-case1-retry.json`.
The opt-in private device harness is `ten-e2e.mjs`; its screenshots are outside Git
under `/tmp/docard-ten-*.png`. Credentials and private screenshots are not included
in this report.

Command receipt references:

| Case | Command IDs |
| --- | --- |
| 1 | 6bac30d8-7bc6-4a57-b896-5f68eda1f326 |
| 2 | fab360b3-21d3-420c-8056-60bc53a9a1b4 |
| 3 | 276b74f0-0ec7-4f40-93c4-e1abc2445aa2 |
| 4 | Replay of case 3 command ID |
| 5 | 8608226f-c4f2-4e06-8e5a-58e69527e714 |
| 6 | 620123bb-b20b-4545-bd7a-a2efe2444699 |
| 7 | Replay of case 6 command ID |
| 8 | e0bbc1e8-da08-4316-843a-6a0808a9910c; 47c2c916-2985-4579-a576-6c6f100d24d9 |
| 9 | Expiry of case 8 start; no stop sent |
| 10 | 77e4d272-feda-45e7-aca4-91ab1eb3731c |

Final state: no active session; requiresRenewalApproval=true as expected after
expiry; same mode, same selection identity, two selected apps, maximum 45 minutes.
Final process inventories showed no main DO Card process. Local services remain
stopped. Emergency Unlock, NFC, subscriptions, authorization UI, SwiftData and
migration code were not modified. No app build was needed for this documentation/
physical-verification pass.

This is a pass for these ten scenarios on this physical phone and installed Debug
build. It does not establish reboot recovery, offline delivery, denied/revoked
Screen Time authorization, other iOS versions or Instagram enforcement.
