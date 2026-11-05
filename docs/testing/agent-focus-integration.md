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
