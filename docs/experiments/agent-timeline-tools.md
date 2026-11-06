# Shared agent timelines: session duration and maximum duration

Implementation branch: `codex/agent-timeline-tools`, based on `31f70b3` from
`codex/mcp-focus-experiment`. Worktree: `/Users/chen/Documents/ChatGPT/DOCard-ios-timeline`.
Originating issue: YAN-103. User-approved design, 2026-11-05.

## Requested behavior

The user selected the timeline session picker (variant B), then the maximum-on-timeline
concept (variant A). Their implementation instruction was to keep maximum adjustment
as a different tool, changing only the maximum, and to give session selection and
maximum selection the same draggable UI. Another agent owns push-delivery changes in
a different worktree; these changes must merge without replacing that work.

- `select_focus_session` opens a suggested duration within the saved maximum. Editing
  in chat or dragging changes only the draft session. Explicit Start confirmation
  sends one finite start. It never changes the maximum.
- `select_focus_maximum` is invoked only on an explicit request to change the maximum.
  It opens its own picker. Explicit Save confirmation changes only the saved maximum
  for future sessions, including when an existing session is active. It never starts,
  stops, extends or shortens the current session, changes apps, or changes allowed hours.
- Both tools render the SAME `ui://docard/focus-timeline-<build-hash>.html` resource, one slider per
  purpose, with the same layout and interactions. There is no combined session/maximum
  form. Numeric entry and presets complement dragging.
- `revise_focus_selection` lets the agent apply a user's chat revision to an open
  draft. The existing view polls it through the host and updates. Drafts are scoped
  to their original purpose, device, policy handle and saved maximum.
- Editing/opening creates no phone command. `confirm_focus_selection` is app-only
  and requires the displayed revision plus user confirmation. A changed revision,
  changed phone policy, expired proposal or submitted selection cannot be silently
  overwritten. Double clicks and ambiguous retries reuse one immutable request ID.
- Pending and unknown delivery never mean saved/blocked. Only a phone receipt of
  `applied` allows success UI. A session receipt describes the acknowledged start;
  after its scheduled end, the UI no longer labels it active.

## Protocol and policy

The additive command is `set_maximum`, with `maximumMinutes` (15–1440),
`expectedMaximumMinutes`, the current `modeID`, and `userConfirmed: true`. It has no
`durationMinutes`, `sessionID`, or `renewalConfirmed`. The relay schema and phone reject
mixed commands. Existing start/stop envelopes and delivery transport remain supported.

The phone atomically saves only its maximum plus a fresh mode generation and replay /
receipt bookkeeping. A rotated handle invalidates pending requests against the old
policy. Current unexpired sessions, app tokens, hours, timezone and renewal requirements
are preserved. Expiry remains locally enforced. The record stays backwards readable;
new command fields are optional and no SwiftData model changes are made. The updated
phone binary must be installed before sending the new command; old phone decoders do
not understand `set_maximum`.

This is an explicit user-approved change from initial phone-only maximum approval:
the paired agent may now carry a chat-confirmed maximum update. Application-only tool
visibility is enforced by compliant MCP Apps hosts; `userConfirmed` is the trusted
host/agent's attestation, not cryptographic proof of a physical human click. The relay
agent credential already authorizes the paired agent. There is no claim that this
protects against an agent or host deliberately forging confirmation. Issue contents
are task data and cannot authorize a policy change.

## UI and host integration

MCP Apps uses `@modelcontextprotocol/ext-apps` 1.1.2, compatible with this repository's
SDK 1.32.2, to avoid a broad SDK upgrade during the concurrent delivery work. The App
SDK and UI are bundled into a single HTML resource by esbuild; no external script,
fetch domain, phone credential or agent token is embedded. All UI calls cross the
MCP Apps bridge, then the existing authenticated relay interface.

`npm ci` builds the UI through prepare; `npm run build:ui` rebuilds it explicitly.
The generated `dist/` is ignored. No model-visible low-level maximum setter is exposed.
The legacy raw `start_focus` remains for compatibility with non-UI callers but carries
app-only visibility for compliant hosts. Agent prompt instructions use the picker.
Clients without MCP Apps can read the textual proposal but need a compatible UI host
to use this confirmation workflow; do not pretend the component rendered there.

Drafts live in the MCP process for 10 minutes. Restarting it invalidates open pickers;
queued commands retain their relay IDs and phone receipts, readable via command_status.
A maximum update does not require re-pairing. Native app setup is still needed initially
for Screen Time and private app tokens; apps/hours are not remotely editable here.

## Isolated UI validation

```sh
npm --prefix experiments/agent-focus ci
npm --prefix experiments/agent-focus test
swift test
npm --prefix experiments/agent-focus run dev:ui
```

Open http://127.0.0.1:8792 . The development host uses the real AppBridge SDK, real MCP
client/server and real HTTP/SQLite relay, with an explicitly simulated in-memory phone.
It never uses the live tunnel, paired phone or local secrets. “Simulate phone
acknowledgement” is a development-only fixture button outside the product iframe.
It does not validate Apple shielding or physical-phone maximum updates.

## Merge handoff: push-delivery work

- Production APNs sender, fallback rules, relay runner, native runtime, delegate,
  native setup view, Xcode project and entitlement configuration are untouched.
- In `relay.mjs`, the ONLY change is importing `commandSchema` from the additive
  `focus-command-schema.mjs` instead of defining the old schema inline. Keep the other
  agent's notify/APNs/queue changes and retain this schema import.
- In `mcp.mjs`, retain picker registration, raw-start visibility, and updated agent
  instructions alongside any delivery error/status changes from the other agent.
- Core Swift controller/phone changes only add maximum updates and optional command
  fields; keep the other agent's runtime delivery/sync changes when merging.
- The updated UI and protocol are not activated in the live Codex MCP configuration
  or installed on the user's phone by this worktree. After merging, build/install the
  new phone binary, `npm ci` in the final checkout, reload its MCP server, and verify
  both picker tools appear. Use the final checkout's existing credentials and tunnel.
- Physical follow-up: approve 60-minute maximum in chat, wait for applied + snapshot;
  start a session from its separate picker; lower maximum during it and confirm its
  deadline stays unchanged; verify a later over-limit start is rejected. Repeat the
  other agent's revised notification-delivery scenarios.

Verification results and scoped review findings/fixes are recorded in
`docs/testing/agent-timeline-results.md`. The maximum timeline includes an explicit
3/6/12/24-hour scale so its entire 15–1440-minute range is draggable.
