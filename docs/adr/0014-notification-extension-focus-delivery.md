# 0014 — Visible notification extension for agent focus commands

Date: 2026-11-05. Status: implemented in `codex/agent-notification-extension`;
real-device notification execution and Screen Time compatibility are not yet verified.

## Decision

Use an immediate visible, mutable APNs notification to invoke a Notification Service
Extension, rather than waiting for a discretionary silent push and a 15-second alert.
MCP tools, the authenticated relay command queue, local policy validation, finite expiry
and Emergency Unlock retain their existing contracts. This extends ADR-0013 only on
this experiment branch. No subscription gate is introduced.

The alert carries the agent marker and an opaque request ID, never a device credential,
app selection, mode handle or a remotely supplied relay URL. The extension loads its
approved pairing from shared Keychain storage and fetches commands using the device
credential. Both app and extension execute the same Foundation delivery worker and
persisted phone interface. A notification ID is a hint, not authority.

The native extension compiles the phone core, delivery worker, Keychain access and
ManagedSettings/DeviceActivity adapter. Main-app-only legacy session/selection setup
checks remain in AgentFocusApproval.swift; the extension does not load SwiftUI,
StoreKit or SwiftData models. It uses the same named shield store and App Group record
as the monitor. The app and extension explicitly use the existing shared Keychain group.

The worker limits network work to 18 seconds (including session invalidation on timeout),
checks cancellation before command execution, bounds response sizes and processes at
most 32 queued commands per sync. Extension file-lock acquisition is limited to 200 ms;
busy/unavailable protected storage yields a pending result rather than modifying another
process's shields. Existing app/monitor lock and emergency-release semantics remain.
The notification completion handler is consumed once under a lock; time expiry cancels
network work and delivers the generic fallback content. Apple platform calls themselves
are synchronous and still need real-device timing/memory validation.

Recent command results are retained through their TTL plus 60 seconds. An overlapping
app/extension queue read therefore returns the same receipt even after a newer command
and acknowledgement, without re-applying an older shield or creating a conflicting
rejection. The optional Codable field reads older records without a schema migration.
Failed prior receipt uploads do not prevent fetching a newly queued unlock; every new
result stays in the durable outbox for retry. Only phone receipts change relay status.
A device-authenticated GET of its own command result handles notifications whose request
was already processed by the app. A device cannot inspect another device's results.

The visible result says a request was applied, rejected or is still waiting. It never
claims that a historic applied start means apps are still blocked, or that APNs
acceptance proves execution. A local applied result may be shown if acknowledgement
upload fails, while Codex correctly continues to see pending until upload succeeds.

## Platform evidence and limits

- Apple recommends a notification extension for background work coupled to a visible
  notification: https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app
- An Apple engineer discusses a closely matching parental-control use case, launch
  requirements, time/memory limits and unverified framework compatibility:
  https://developer.apple.com/forums/thread/761212
- Named ManagedSettings stores are shared across an app and extensions:
  https://developer.apple.com/videos/play/wwdc2022/110336/?time=288

These support a feasibility experiment, not a guarantee. Notifications must be visible,
with mutable-content and an alert payload. Disabled alerts/previews, a hidden app,
network loss, unavailable credentials before first unlock after reboot, extension
termination and framework/entitlement restrictions can prevent automatic execution.
The extension's Family Controls development profile and distribution entitlement need
verification for its own bundle ID; the parent entitlement is not proof of support.
There is no App Store approval claim. Local expiry and Emergency Unlock remain essential.

## Isolation and validation

Worktree: `DOCard-ios-notification-extension`, based on `codex/mcp-focus-experiment`
at `31f70b3`. Build products and simulator are separate. No live relay, Cloudflare
process, MCP config, Apple account, existing worktree or physical-phone app is changed.
See `docs/testing/notification-extension-focus.md` for evidence and the device test plan.

## Deadline recovery follow-up

Physical reboot tests did not reliably invoke local expiry monitors, including dated
and recurring-clock candidates. Re-delivering an authenticated visible APNs alert after
expiry cleared restrictions through the existing notification extension without opening
the app; a fresh phone snapshot and the owner confirmed release. The relay therefore
adds a durable original-deadline expiry check after an applied-start receipt. It is a
network-dependent backup, not a replacement or guarantee for local/offline expiry.

Expiry pushes carry an opaque original command ID and an expiry marker with a distinct
collapse domain. The updated extension invokes a release-only phone path and publishes
observed status. It never fetches/executes queued commands for an expiry hint. Only the
phone's stored absolute deadline decides whether release is due; stale/early hints
cannot release a newer unexpired session. APNs acceptance remains transport evidence,
not a phone acknowledgement. See docs/testing/agent-focus-expiry-relay.md and
agent-focus-qa.md for retry, cancellation, restart and device-test limitations.
