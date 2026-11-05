# Durable relay expiry fallback

Date: 2026-11-06. Branch: `codex/agent-focus-integration`.

## Behavior

An authenticated phone `applied` receipt for a start atomically saves the receipt and a
SQLite expiry job. Its immutable deadline is the original relay command's `issuedAt` plus
`durationMinutes * 60000`. Receipt delivery delay, maximum changes and stale snapshots never
extend or cancel this deadline. Pending/rejected starts do not create jobs.

An applied stop cancels pending jobs for the exact device/session whose original start
precedes that stop in command sequence. A delayed/duplicate old stop cannot cancel a
newer start, including legacy callers reusing a session ID. If the later-sequence
stop receipt arrived before its start receipt, that late start creates a canceled job.
Duplicate start receipts cannot reset a canceled or successfully sent job. An older stop
does not cancel a subsequent start.

The production relay runner enables a one-second worker. The constructor defaults to no
worker (`expiryIntervalMs: null`) so existing callers/tests keep their prior behavior.
One worker pass considers at most ten due jobs and processes APNs calls serially. Each
claim conditionally persists the attempt and a 30-second retry lease before network I/O;
the conditional update prevents another relay instance from claiming the same current
lease. Clock injection supports deadline tests.

Expiry sends reference the original start's opaque command ID, with `kind: 'alert'`,
`purpose: 'expiry'`, and APNs expiration at the original deadline plus 24 hours. Only
`accepted_by_apns` marks a job sent. Failure, missing registration and unconfigured
transport retry after 30 seconds. Pending jobs stop sending at the 24-hour horizon.
Closing clears the timer and prevents post-await database writes from in-flight sends.

APNs acceptance changes only the expiry job's transport state. It never changes the
original command receipt, command TTL, session or phone snapshot. Existing HTTP response
contracts remain unchanged. Push tokens, agent credentials and APNs keys are not exposed
by a new endpoint or written to test/run output.

## Tests and evidence

The authorized seam is real authenticated HTTP against a fresh temporary file-backed
SQLite database, with only time and outbound APNs replaced. Tests read results through
HTTP and observe the injected APNs boundary, never database internals. No live relay,
phone, tunnel, saved credential or cloud service was touched.

`test/relay-expiry.test.mjs` contains ten test methods covering:

1. Only an applied start sends; no send before the exact original deadline; one alert at it.
2. Maximum changes preserve the original expiry deadline.
3. Rejected/mismatching stops do not cancel; applied matching stops cancel, including retries.
4. Out-of-order applied-stop/start receipts cannot recreate an obsolete expiry job.
5. Delayed/duplicate old stop receipts preserve a newer start with a reused session ID.
6. Failed and unconfigured transports retry at 30-second boundaries, stopping after acceptance.
7. Reopening SQLite preserves retry leases, sent state and receipt idempotency.
8. Expiry APNs acceptance preserves the original receipt, TTL and last phone snapshot.
9. The 24-hour horizon stops further attempts across reopening.
10. In-flight delivery is serialized and closing safely ends timer activity.

The exact-deadline test was first RED because no expiry worker existed, then GREEN after
durable jobs and the worker were implemented. The out-of-order receipt test was also RED
(an obsolete alert was sent), then GREEN after checking later applied stops transactionally.
The reused-session-ID regression was RED because an old stop canceled a newer start's
job, then GREEN after stop cancellation was restricted by the original start sequence.

`node --test test/relay-expiry.test.mjs`: **10 passed**, 0 failed, skipped or canceled.
The full npm test script, including its UI prebuild and the concurrently added APNs
adapter cases, passed **79 tests**, with 0 failed, skipped or canceled.
`node --check` passed for both changed relay modules; `git diff --check` passed.

## Limits

This is a server/network-dependent backup for the observed physical reboot callback gap.
The relay process, internet access, APNs delivery and the phone notification extension must
be available. It cannot guarantee offline expiry after reboot or exact-second delivery.
APNs acceptance is not evidence of device execution or unlocked apps; a fresh phone
snapshot and device confirmation are still needed for that conclusion.

A clean SQLite reopen is not a process-kill/disk-failure test. If the process dies after
APNs accepted a send but before the successful result is persisted, the leased job may
retry an uncertain send; accepted jobs already persisted as sent do not send again. The
phone reconciliation path must remain idempotent. No exactly-once network-delivery claim
is made.
