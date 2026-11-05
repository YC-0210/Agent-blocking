# Notification extension focus delivery

Branch: `codex/agent-notification-extension`. Base: `31f70b3`.
Implementation is ready for signing/device validation, not claimed to work on real APNs yet.

## Automated coverage

Swift tests use the actual phone journal, local approval and shared delivery worker.
An external URLProtocol fixture replaces only relay HTTP; the Apple shield effect is
supplied at the existing hardware seam. Coverage includes execution without a UI runtime,
expiry rejection, cancellation, already-handled notification results, failed receipt uploads
not preventing unlock, overlapping app/extension delivery, and bounded lock contention.

Relay tests use real HTTP/SQLite plus an HTTP/2 APNs stand-in. They verify immediate
visible delivery, mutable-content/header fields, no separate delayed alert, no secrets or
app-selection data in the push, pending-until-receipt semantics and device-scoped result reads.
Existing MCP tests still run through the initialized SDK client/server and stdio process.

Red/green evidence (local temporary logs):
- `/tmp/docard-nse-relay-red.log` → `/tmp/docard-nse-relay-green.log`
- `/tmp/docard-nse-apns-red.log` → `/tmp/docard-nse-apns-green.log`
- `/tmp/docard-nse-result-red.log` → `/tmp/docard-nse-result-green.log`
- `/tmp/docard-nse-replay-red.log` → `/tmp/docard-nse-replay-green.log`
- `/tmp/docard-nse-worker-red.log` → `/tmp/docard-nse-worker-green.log`
- `/tmp/docard-nse-unlock-red.log` → `/tmp/docard-nse-unlock-green.log`
- `/tmp/docard-nse-lock-red.log` → `/tmp/docard-nse-lock-green.log`

Verification on 2026-11-05:
- 28 Swift package tests passed (`/tmp/docard-nse-core-final.log`).
- 20 relay/MCP tests passed (`/tmp/docard-nse-node-final.log`).
- 64 selected existing iOS regression methods passed, TEST SUCCEEDED
  (`/tmp/docard-nse-ios-regression.log`).
- Final Debug simulator build passed (`/tmp/docard-nse-debug-final.log`).
- Final Release iPhone SDK build passed with signing disabled
  (`/tmp/docard-nse-release-final.log`).
- The built app embeds DoCardNotificationService.appex with the correct notification
  service extension point, principal class, app-group/keychain configuration and bundle ID.
- `git diff --check` passed. Manual review checked command authority, replay/order,
  result wording, lock/network budgets, completion-once handling and target membership.
  No sub-agents were used in this side conversation.

Simulator builds do not prove that Apple will launch this extension or honor its
Screen Time operations. No real APNs request, device install, provisioning change,
background shield test or extension memory measurement was performed.

## Separate local environment

Do not restart the relay in the other checkout or reuse its database. From this worktree:

```sh
cd experiments/agent-focus
npm ci
node scripts/init-local.mjs
```

Edit this worktree's ignored `.local/relay.env`, set `PORT=8788`, and configure your own
APNs key path/IDs. The default database is already relative to this checkout. Start:

```sh
node --env-file=.local/relay.env src/relay-main.mjs
```

In another terminal, give this separate relay its own tunnel:

```sh
cloudflared tunnel --url http://localhost:8788
```

Point a separately named MCP entry (for example `docard_focus_notification_test`) at this
checkout's `src/mcp-main.mjs`, its private agent token and the new tunnel URL. Do not
replace the existing MCP entry. Keep command IDs opaque and unrelated to task contents.

## Signing and device setup

The new target is `DoCardNotificationService`, bundle ID
`online.do.card.app.FocusNotification`. It needs its own valid provisioning profile with
Family Controls, the existing App Group and shared Keychain group. The APNs topic stays
the containing app ID (`online.do.card.app`); the extension does not register a separate
push token. Developer forks must configure their own team, bundle IDs and groups,
including `KeychainHelper.sharedAccessGroup`; the checked-in project uses DO Card IDs.
Request any needed distribution approval for the extension separately before claiming
TestFlight/App Store support. Successful unsigned compilation does not prove provisioning.

The app bundle ID is unchanged. Installing this branch on the same phone replaces its
existing DO Card binary and shares its existing app data, so coordinate that installation
with work in the other checkout. Prefer a dedicated test phone. Stop active sessions,
install the signed app, pair it to this isolated relay and approve selections/limits.
Grant visible notification alerts; check lock-screen previews/content and hidden-app state.
No install, pairing, Apple capability update or relay restart was performed by this change.

## Required physical tests

For each command, record APNs acceptance time, extension execution, receipt time and
actual shield state; do not count notification appearance alone as success.

1. App in background, phone unlocked: start a short session; verify a selected app is
   shielded without entering DO Card; stop remotely and verify the shield disappears.
2. Repeat while phone is locked; then repeat over cellular with Wi-Fi off.
3. Repeat after the user force-quits DO Card, and separately after iOS terminates it.
   Record behavior instead of promising the two cases are equivalent.
4. Test Low Power Mode, Focus/notification summaries, disabled alerts, disabled previews,
   hidden app and notification permission changes. Pending/fallback must be truthful.
5. Reboot; test before and after first device unlock. Protected storage failures must
   not apply a block or report success.
6. Disconnect network mid-operation and during receipt upload. Outbox retries must
   preserve applied/rejected results without repeating a shield effect.
7. Race duplicate pushes, a start followed by stop, app foreground polling and Emergency
   Unlock. An older queued start must not resurrect an ended session.
8. Disconnect relay/phone after a successful start. Local expiry must clear agent shields;
   Emergency Unlock must work without a network. Measure callback timing separately.
9. Use Instruments/device logs to measure extension memory/runtime. Run signed builds
   without an attached debugger; simulator/URLProtocol checks do not cover system budgets.

Never hide alerts to turn this into a covert execution mechanism. Every command still
requires the phone-approved scope/hours/duration, valid TTL and replay checks.
