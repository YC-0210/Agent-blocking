# 0013 — Opt-in agent focus experiment

Status: implementation on `codex/mcp-focus-experiment`; physical-device validation pending.
Date: 2026-11-05.

## Decision

Implement the user-approved design in `docs/experiments/agent-focus-design.md` as a standalone agent-only build on this branch. Per the user's 2026-11-05 follow-up,
it launches directly into Agent Focus setup or Emergency Unlock, with no legacy home,
onboarding, update gate or subscription entry screen. `docard-agent://setup` supplies
pairing details but is not required to enter the experiment. This supersedes ADR-0008's
no-device-sync scope only for this branch.
The experiment's everyday screen offers Emergency Unlock only; native setup/permissions
and fresh policy approval are intentional exceptions. The update gate preserves that
emergency screen. Legacy update behavior is unchanged when the experiment is disabled.

The approved test seams are the phone focus command interface, the authenticated
relay interface and the MCP tools. The phone core is the same Swift source compiled
into the native app and monitor, exercised by a small Swift package on the Mac.
The relay is tested over actual HTTP against SQLite; the MCP tests use an initialized
MCP client and include real stdio discovery. Apple hardware and APNs are system seams.

## Architecture

- The iPhone owns approved app tokens, hours/timezone and a maximum duration. A fresh
  approval creates a new mode ID, invalidating commands for earlier selections.
- One protected, atomically replaced App Group record stores local policy, session,
  consumed sequence, emergency cutoff, pending effect and acknowledgement outbox. An OS file lock
  serializes the app and monitor, including platform release. Pairing identity scopes
  sequence/outbox state; a replacement pairing resets both. Before shield effects, a
  recoverable pending command and expiry owner are persisted. An independent shared Keychain
  cancellation ledger, ordered by a shared revision, prevents a failed session-file write from resurrecting a stopped
  owner. Emergency Unlock rotates the opaque mode handle; no prior queued command can
  start with it, independent of relay/phone clock ordering. Pairing and authority remain
  intact; Codex reads the fresh handle before a genuinely new start. No SwiftData models or schema versions change.
- A separate named ManagedSettings store and DeviceActivity namespace isolate agent
  shields. Agent stop/expiry never clears a card or schedule store. Activation refuses
  existing sessions or enabled legacy schedules; test on a dedicated phone if possible.
- Register independent local expiry before applying shields. Restore current shields
  only while expiry can be retained/registered; otherwise end the session and require
  approval to continue. No exact-second background-delivery guarantee is claimed.
- Per user instruction on 2026-11-05, this experiment exempts agent focus from
  subscription checks at setup, execution and restoration. This is a scoped exception
  to ADR-0007. StoreKit refresh/reconciliation is removed from the app entry point, and
  subscription-expiry callbacks are ignored in this build. Legacy subscription source
  remains compiled for compatibility but is not part of the agent UI or lifecycle. Screen Time
  authorization, phone-approved scope/hours/duration, and Emergency Unlock remain enforced.
- Device credentials live in the iPhone Keychain with AfterFirstUnlockThisDeviceOnly
  access. They are separate from the Mac agent credential. Pairing codes are random,
  single-use and expire in ten minutes. The phone accepts HTTPS relay addresses only.
- A local stdio MCP process and Node/SQLite relay use sequence numbers, stable request
  IDs, transactional sequence allocation, two-minute command TTLs and phone receipts. Push acceptance never means applied.
  Emergency release invalidates earlier queued starts while allowing a genuinely new
  command afterward, as expressly selected by the user.
- Send an authenticated APNs background notification first. Attempt one generic alert
  after fifteen seconds if still pending. Foreground/push reconciliation retries
  durable receipts before fetching more commands. Network replies are never followed
  through redirects with credentials.
- Linear remains a separate connection in Codex. The MCP prompt describes allowed
  progress updates, completion confirmation, break negotiation and renewal approval.
  No task contents or Screen Time histories are sent to the phone or relay.

## Tradeoffs and alternatives

Reusing the existing card store was rejected because an agent unlock could erase a
physical commitment or schedule. A fake push transport in the production runner was
rejected: it fails clearly until real APNs credentials are configured. SQLite plus an
HTTPS tunnel provides a concrete single-user experiment without provisioning a cloud
database. The Mac and tunnel must remain available; production hosting is not claimed.
A persistent autonomous Codex scheduler is outside scope.

MCP confirmation flags attest what the user said in chat; the server cannot independently
prove the agent's account of that conversation. Phone-enforced app scope, hours and
maximum length are independent of those flags. A task's Done status is not proof of
completion. No Screen Time usage export is included.

## Validation

See `docs/testing/agent-focus-results.md` for test/build evidence and outstanding phone
checks. Actual APNs, Family Controls provisioning, shields, offline/reboot behavior and
cellular delivery require a signed physical iPhone. Do not submit this experiment to the
App Store or TestFlight based solely on local test results.
