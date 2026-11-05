# Timeline + notification extension integration (2026-11-05)

The user explicitly approved combining and activating both branches for a live maximum
selection test. Integration worktree: `/Users/chen/Documents/ChatGPT/DOCard-ios-integration`.
Branch: `codex/agent-focus-integration`.

Combined `codex/agent-timeline-tools` at `12f7a1c` with
`codex/agent-notification-extension` at `36d7600`, shared base `31f70b3`.
Kept both sets of added tests and documentation. Relay retains the new command-schema
module and notification agent's immediate visible delivery/device receipt route.

Integration regression: an applied maximum update also needs to enter the notification
extension's completed-command cache. Without this, replay after a newer policy command
returns rejected rather than the original applied receipt, conflicting with the relay.
A new public phone test failed on the merge result, then passed after maximum updates
used the same `remember` path. Retrying an earlier maximum cannot roll back the later
maximum or create a conflicting result.

Validation: 32 Swift tests, 25 Node tests and signed Debug iPhone build passed.
Logs: `/tmp/docard-integration-swift.log`, `/tmp/docard-integration-node.log`,
`/tmp/docard-integration-device-build.log`. No secrets are recorded here.

Activation completed:

- Installed and launched the merged build on the user-approved connected iPhone 13.
- Gracefully stopped the old relay; backed up its private SQLite database after close.
- Started the integrated relay on the same loopback port using the existing private
  environment file, token path and database; kept the existing Cloudflare tunnel.
- Backed up local Codex configuration and changed only docard_focus's executable-script
  argument to this integration checkout. Relay URL and credential paths are preserved.
- The existing phone pairing still syncs; a fresh snapshot reported maximum 45 minutes
  and no active session. No maximum update or blocking command has been sent for this test.

Remaining user step: reload/restart Codex's MCP connection so this chat discovers the
new selection tools. This active chat still exposes the older tool list despite the
config update. Native computer-use access to Codex itself was denied by the platform,
so the agent cannot refresh Codex's own connection through its settings UI.
After client reload, call select_focus_maximum for the existing paired device and
wait for the user's explicit UI confirmation before sending any policy change.
Then check applied receipt and phone-observed maximum. Real extension-triggered
execution, including Apple framework compatibility, is still a separate device check.

Live maximum attempt: the user's 180-minute request was rejected with
`mode_not_approved`. The command carried the earlier phone approval handle; the
subsequent phone snapshot carried a different handle and still maximum 45. The
phone's stale-approval protection is preserved; a new picker must bind the updated
snapshot rather than replaying or silently rebinding the rejected confirmation.

Simplified both shared picker views to editable minutes, the draggable range and a
small explicit confirmation action. Removed headings, presets, explanatory copy,
axis labels and scale menu. The range still spans the complete approved domain
(maximum: 15–1440); keyboard/numeric entry supports precise values. Status/error
feedback appears only when needed. Stale-approval rejection now explains the
settings change. No phone binary change required.
Validation: all 25 Node tests passed; isolated MCP Apps host verified editing 180,
explicit submission, pending state and simulated applied receipt. That fixture
result is not evidence of a live phone maximum update.

## Cold-process authorization synchronization fix

The repeated `mode_not_approved` receipts were traced to reconciliation collapsing
Family Controls `.notDetermined` into `false`. Cold notification processes can begin
with that initial status, so each delivery rotated the phone approval before reading
the queue. Apple's authorizationStatus documentation describes the initial value and
requires main-queue access:
https://developer.apple.com/documentation/familycontrols/authorizationcenter/authorizationstatus

The adapter now reads reconciliation status on the main queue and distinguishes
approved, explicitly denied and unknown. Unknown cannot revoke persisted approval or
restore a still-live session; it still releases expired sessions. Explicit denial,
Emergency Unlock, stale-mode rejection and native install authorization checks remain.
No pairing reset or approval bypass is added.

TDD evidence: the new persisted-phone regression reproduced approval rotation and
rejected 170-minute maximum (four failing assertions), then passed after the fix.
A second test checks preservation of live sessions, local expiry under unknown status
and rejection of an old-mode maximum after explicit denial. All 34 Swift tests pass.
Device Debug build succeeded. Logs: `/tmp/docard-auth-red.log`,
`/tmp/docard-auth-green.log`, `/tmp/docard-auth-device-build.log`.

## Short-session follow-up

The first two-minute session after the maximum fix reached the phone with the current
mode, but its receipt was `execution_failed` (maximum remained 170, no live session).
The native install adapter still required process-local authorizationStatus approved;
this was inconsistent with reconciliation's cold-process handling. It also read that
main-queue property from the notification worker's background context.

The adapter now captures the three-state authorization decision on the main queue
before acquiring the phone lock. Known denial still rejects installation. Unknown
defers to native monitoring using the owner's already approved, persisted selection;
it does not synthesize an approved status. Phone pairing/mode/TTL/duration validation,
expiry and Emergency Unlock remain unchanged. Native operation failures still reject
and clear owned state. Reading outside the lock avoids dispatch-to-main deadlock with
a competing main-app phone operation.

All 34 Swift tests and the signed device build pass. This adapter behavior requires
a fresh physical short-session test; the generic previous failure receipt alone does
not prove whether any further Apple framework limitation remains.
