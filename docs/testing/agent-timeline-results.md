# Shared MCP timelines: verification (2026-11-05)

Branch `codex/agent-timeline-tools`, based on `31f70b3`. Separate worktree at
`/Users/chen/Documents/ChatGPT/DOCard-ios-timeline`. Spec and merge handoff:
`docs/experiments/agent-timeline-tools.md`.

## Automated and build evidence

- 24 Swift public phone/controller tests passed, including maximum persistence while
  active, exact deadline/selection preservation, idempotent acknowledgement, lowering
  the maximum for later starts, and rejection of mixed start/maximum commands.
- 24 Node tests passed over real initialized MCP clients (including stdio discovery),
  real HTTP and SQLite. New checks cover shared UI resource discovery, maximum-only
  envelopes, proposal-only edits, explicit confirmation, concurrent/repeated confirms,
  stale phone policies, stale revisions, over-limit sessions, phone acknowledgements,
  and a network-gated confirmation/revision/expiry race.
- Clean `npm ci` (including UI prepare build), bundled self-contained resource build,
  and `npm audit` passed. Audit reported zero vulnerabilities.
- Signed Debug generic iPhone build passed with automatic provisioning.
- Debug simulator build passed with code signing disabled.
- No native model/schema migration or Xcode project change.

Red/green evidence: the initial maximum-command test failed decoding the unknown action;
then passed with the additive command. The relay test failed 400 versus expected 202;
then passed with the separate schema. The MCP discovery/flow test failed because the
maximum picker was absent, then passed. Mixed native start/maximum was initially applied,
then rejected after its regression guard. The confirmation concurrency test initially
submitted an unreviewed revision, then rejected it after post-await validation.

Logs (local, not committed): `/tmp/docard-timeline-phone-final.log`,
`/tmp/docard-timeline-node-verified.log`, `/tmp/docard-timeline-install.log`,
`/tmp/docard-timeline-audit.log`, `/tmp/docard-timeline-device-build.log`, and
`/tmp/docard-timeline-simulator-build.log`.

## UI walkthrough

The local development host on port 8792 uses the real MCP Apps App/AppBridge SDK,
real MCP client/server, real relay HTTP endpoint and an in-memory SQLite database.
Only the phone side is a clearly labelled simulation; no live credentials are loaded.

Verified in Chrome:

- Each tool loads the same real App resource in a sandboxed iframe.
- Maximum picker has one draggable maximum control and no session-time control.
- Dragging changes the draft, confirmation stays pending until explicit test-phone ack,
  then reports maximum saved. It does not queue a start.
- Session picker subsequently reads the new fixture maximum, has only a session slider,
  and chat revision updates the same visible slider without changing the saved maximum.
- Switching tools uses independent views/proposals; old host bridge is torn down.
- A 24-hour scale makes the full 1440-minute maximum reachable through the range control.
- Empty numeric editing disables confirmation and keeps the component interactive.

Actual phone policy updates and host-native rendering in the user's reloaded Codex MCP
configuration remain untested in this worktree. The signed build was NOT installed on
the user's phone, and the live relay/MCP configuration was NOT restarted or edited,
because a parallel worktree is changing push delivery. Apply the integration checklist
after merging both branches. This evidence does not claim a live maximum update or
new Apple push/cellular validation.

## Standards review

Independent reviewer found one confirmation TOCTOU violation: revision/expiry were
checked before awaiting the phone snapshot, allowing an intervening chat revision.
Fixed by checking existence/expiry/revision after the final await and freezing the
command payload without yielding. Reviewer reran the real HTTP-gated regression and
confirmed the finding resolved. No remaining scoped standards findings.

## Spec review

Independent reviewer found the same confirmation race plus a maximum-range interaction
that stopped at three hours unless the user typed a larger value. Fixed the race as
above, and added explicit 3/6/12/24-hour timeline scales. Reviewer rechecked both fixes
and found no additional directly introduced issues. No remaining scoped spec findings.

Original findings: Standards 1 resolved; Spec 2 resolved (one shared finding).
