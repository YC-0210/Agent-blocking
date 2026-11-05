# Agent Focus relay QA

Date: 2026-11-05. Branch: `codex/agent-focus-integration`.

## Seam and isolation

The authorized seam is the authenticated HTTP relay. The new tests call the production
relay over real loopback HTTP and use a unique temporary file-backed SQLite database per
test. Restart cases close the HTTP server and database, then reopen the same temporary
database. Assertions read through HTTP; tests never inspect database tables.

Only wall-clock time and the outbound APNs transport are replaced. Push failure is injected
at that network boundary. No live relay, saved token, phone, APNs account, Cloudflare tunnel,
or production database is accessed. Temporary files are removed on completion.

## Added coverage

`experiments/agent-focus/test/relay-qa.test.mjs` adds 18 Node test methods:

| Behavior | New methods |
| --- | ---: |
| Snapshot wire-shape rejection preserves the last accepted snapshot | 1 |
| Missing start duration; malformed and mixed command fields do not consume sequence | 2 |
| Pairing redeemable at deadline minus 1 ms, expired at deadline, and single use | 2 |
| Agent/device credential roles and cross-device isolation with identical request IDs | 2 |
| Command available at TTL minus 1 ms, expired at TTL, expired retry never rejuvenates it | 3 |
| Conflicting request payload, idempotent terminal receipt/retry, conflicting receipt reason | 3 |
| APNs failure remains pending until an authenticated phone receipt arrives | 1 |
| Concurrent identical requests allocate one command and one sequence | 1 |
| SQLite reopen preserves pending work, device credentials, terminal receipts, snapshot and sequence | 2 |
| Malformed JSON and oversized body rejection preserve queue and server availability | 1 |

The original 13 relay methods retain distinct-command concurrent ordering, other-device
receipt isolation, minimum snapshot compatibility, and a loopback HTTP/2 APNs adapter check.
They were not modified.

## Regression and results

The new missing-duration test initially failed: an authenticated start without
`durationMinutes` received HTTP 202 and entered the queue instead of receiving HTTP 400.
The parent agent reproduced the failure and tightened the shared production command schema.
The same unchanged assertion now passes, and the queue remains empty after rejection.

On Node v22.18.0:

- `node --test test/relay-qa.test.mjs`: **18 passed**, 0 failed, skipped or canceled.
- `npm test`: UI bundle prebuild succeeded; **63 passed**, 0 failed, skipped or canceled.
  This run included **31 relay methods** (13 original + 18 new) and 32 MCP methods.

Table rows describe grouped behavior; matrix cases inside a method are not counted as
additional Node tests. Other agents may add methods after this recorded run.

## Limits and remaining checks

Relay snapshots deliberately allow absent optional policy fields for older phone clients.
Tests enforce malformed wire types and reject protected/unknown fields. Semantic policy
validation, such as operating-hour ordering, supported timezone and maximum bounds, belongs
to the phone/MCP boundary per the agreed scope; the relay does not independently prove it.

Reopening the relay/database in one Node process proves persisted HTTP behavior, not crash
consistency under process termination, disk failure or competing relay processes. Fake APNs
failure and existing loopback APNs acceptance checks do not establish Apple delivery,
extension execution, actual shields, force-quit/reboot recovery or cellular behavior. Those
remain physical-device/system checks. A pending response remains pending regardless of
transport acceptance; only an authenticated device receipt establishes relay `applied` state.
