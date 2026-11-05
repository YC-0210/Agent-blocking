# Agent Focus phone/core QA — 2026-11-05

Branch: `codex/agent-focus-integration`. This pass owns only `AgentFocusTests/` and this report.

## Result

`swift test` passed **59 XCTest cases, 0 failures**, on macOS at 22:30:18 Asia/Taipei.
The baseline was 34 cases. `AgentFocusPhoneBoundaryTests.swift` adds **25 cases**;
all were introduced and run individually through the persisted phone API. Existing-correct
behavior passed immediately; no artificial implementation changes were used to create RED.
The additional Swift Testing runner reports zero tests because these are XCTest cases.

One real defect was reproduced before its production fix: New York on 2026-03-08 at
07:59 UTC (03:59 local), approved hours 00:00–04:00, accepted a two-minute session
ending 04:01. `testSpringForwardHoursCannotAuthorizePastFourAMWallClock` initially
failed three assertions: rejection reason, released shield, and absent session.
Adding elapsed minutes to midnight interpreted the 04:00 boundary as 05:00 on that day.
The coordinating agent changed production calendar-boundary handling; the same regression
then passed. This agent did not edit production sources. Follow-up fall-back and
23-/25-hour full-day boundary examples pass too.

## Approved seams and coverage

The seam is `AgentFocusPhone` / `AgentFocusController`, with actual temporary-directory
persistence and recreation. Injected boundaries are wall time, native shield application /
release, and emergency storage. Assertions observe API status, receipts and external effects;
tests do not decode private persisted records. Storage failures use temporary-directory
permissions, including a failure after native application but before final receipt persistence.
No live phone, relay, credential, APNs operation or network service is used.

| Behavior | Added cases / evidence |
| --- | --- |
| Finite session boundaries | 1 minute rejected; 2 minutes persists across recreation and expires at the exact deadline; 170 accepted under a 170 maximum; 171 rejected |
| Maximum range and consent | 15 and 1440 saved without starting; 14/1441 rejected; absent/false confirmation rejected; stale expected maximum rejected; maximum carrying renewal approval rejected |
| Maximum preserves independent state | A maximum change cannot satisfy expired-session renewal approval; failed maximum persistence preserves the existing live session, old policy and private selection, then the identical retry can succeed |
| Allowed hours / timezone | Exact 09:00 start accepted; exact 18:00 end accepted; one millisecond overflow rejected; Los Angeles previous-local-day interpretation; New York spring-forward 04:00 rejection, fall-back exact 04:00 acceptance and overflow rejection |
| Local midnight | Spring and fall full-day windows accept a session ending exactly at next local midnight and reject a one-millisecond overflow; expected UTC epoch deadlines are literal worked examples |
| Cancellation / authorization | Emergency invalidates a queued maximum while a genuinely new maximum succeeds; explicit denial releases an active session and invalidates queued starts; unreadable emergency ledger fails closed during restoration |
| Persistence / recovery | Failed native restoration durably clears the session and requires renewal; interrupted final receipt save recovers the original unexpired deadline and receipt; an expired pending journal never reapplies shields |

Existing tests were audited and retained rather than duplicated: maximum-only updates
while an active session runs preserve its deadline, app selection, hours and timezone;
lowering the maximum restricts later sessions; unknown authorization preserves current
approval while expiry still runs; overlapping app/extension delivery and acknowledged
retries preserve original receipts; emergency release wins a concurrent restore;
independent cancellation survives primary-record failure; pairing scopes acknowledgements
and resets its sequence/outbox; stale/expired/future commands and clock skew are rejected.

## Limits and follow-up

This is behavioral coverage at the approved seams, not a measured line-coverage percentage.
The suite does not establish physical Family Controls authorization, actual ManagedSettings
shield visibility, DeviceActivity wakeup timing, App Group / Keychain entitlements or locked
phone protection, reboot recovery, APNs, cellular/offline delivery, or UI accessibility.
Those require the separate signed-device checklist. The permission-fault examples assume a
non-root macOS test process; they do not simulate every disk-full or atomic-replacement failure.

The current source resolves nonexistent local-hour boundaries with Calendar `.nextTime` and
repeated boundaries with `.first`. That is an explicit conservative product policy for
ambiguous DST hours; this pass tests unambiguous 04:00 and midnight boundaries and does not
claim exhaustive repeated/nonexistent-hour validation. Synthetic pending-journal tests cover
interrupted durable writes, not an actual OS process kill at every instruction boundary.
