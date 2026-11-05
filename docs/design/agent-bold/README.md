# Agent Focus — Bold implementation

Approved direction: **C / Bold**, selected by the owner on 6 November 2026.

Prototype primary source: [661aef3 on the throwaway branch](https://github.com/YC-0210/DOCard-ios/tree/661aef3/experiments/agent-focus/prototype/design-directions).
This implementation is separate: branch `codex/agent-bold-ui`, worktree `DOCard-ios-bold`,
based on integration `964abe8`. The A/B variants and review switcher are not included.
No Impeccable package, hook, source or asset was downloaded or installed.

## Implemented

- Native SwiftUI: vermilion field, large black type, an open ring, cream lower sheet and
  one always-available Emergency Unlock action. Paired, applying, unknown, due/checking
  and idle states use actual local phone status rather than sample data.
- Bounded read-only presentation refresh uses the existing persisted phone interface.
  Busy/unreadable status is unknown, not an empty/ended session. A pending platform
  application journal is exposed as presentation metadata and never shown as applied.
  When the saved end passes, the screen says checking until the phone reconciles state.
- No fabricated issue title or app count: these are not exposed by the current phone
  runtime. "Agent paired" describes the saved relationship, not proof of a live agent.
- Three-step setup retains relay/code, Apple's real FamilyActivityPicker, Screen Time,
  initial maximum (15–1440, 15-minute steps), local hours and explicit final approval.
  Back preserves inputs. Empty selection, missing access, invalid invitation and
  inverted hours cannot advance/approve. New invitations return to step one.
- Session and independent maximum MCP Apps tools retain the existing shared DOM/JS
  and approval/receipt semantics, with Bold's cream, orange, heavy numeric type and
  circular drag handle. Slider target is 44px high; confirmation is at least 44px.
- Native shield configuration uses the supported iOS background/icon/labels/button
  properties to match the material and copy. Apple's layout remains system-owned;
  the prototype's arbitrary sheet arrangement is not claimed to be supported.
- Dynamic Type, visible focus styles, text wrapping, scrolling and clear status/error
  copy. The app uses the light Bold appearance, including when the system is dark.

Locking rules, approval modes, duration/maximum semantics, APNs, expiry and notification
worker behavior are unchanged. Core Status gains only a read-only `applicationPending`
projection; no record schema or policy mutation was added. This is not an expiry fix.

## Verification

- Full app and all extensions: simulator `xcodebuild` succeeds with the final view.
- Existing Swift package: 76 tests pass.
- Existing Node/MCP/relay/APNs suite including bundled UI build: 79 tests pass.
- Simulator-only UI capture harness: source view with sample runtime/authorization.
  All 3 final walkthroughs pass; native captures are in `screenshots/` (see harness README).
- Real bundled UI in isolated MCP Apps host: numeric/range keyboard synchronization
  (20→21), session confirmation and sample phone acknowledgement, separate maximum170
  confirmation and acknowledgement, no browser page errors. No live commands.

Screenshots marked `bold-*` use sample runtime state in an iPhone 13/iOS26.2 simulator.
`chat-*` use the real bundled UI with an explicit isolated test phone. Neither proves
APNs delivery or physical shielding. Native permission, real app selection approval,
shield presentation and the complete physical pairing flow remain phone checks.

No installation, live relay/MCP restart, physical-phone state or parent test was changed.
Merge this branch with the latest integration changes before a physical installation;
ongoing expiry work may have advanced beyond the base commit.

## Integration review (2026-11-06)

Merged commit `6775080` into `codex/agent-focus-integration` after preserving the
online reboot recovery pass and native registration diagnostics in `372334d`.
No merge conflicts. The notification worker, relay expiry jobs, monitoring
schedules, phone approval record schema, subscription exception and separate
session/maximum confirmation paths retain their existing behavior.

### Standards

Independent read-only review found no substantive documented standards violations.
The owner-approved Bold palette supersedes the older brand-color guidance here.

### Spec

Independent review found one presentation defect: `refreshFocusStatus` ran only
after the network worker, so a cached session could remain visible for up to18s
after local reconciliation. Integration refreshes local status before networking
and again afterward to reflect commands received during delivery. No additional
high-confidence lifecycle or Emergency Unlock regression was identified.

Review totals: standards0, spec1 (corrected). The pre-existing synchronous native
reconciliation and intermittent pending-start stall remain separate known risks.

### Integrated verification

- Swift package:76 tests pass.
- Node/MCP/relay/APNs suite and bundled UI build:79 tests pass.
- Signed Debug iPhone app and extensions: `BUILD SUCCEEDED`.
- Release iOS app and extensions, signing disabled for compile validation:
  `BUILD SUCCEEDED` (`/tmp/docard-bold-integration-release.log`).
- Overlay installation on the paired iPhone13 succeeded, preserving app data.
- Launched the installed app; a fresh phone snapshot retained its pairing/mode,
  45-minute maximum and approved hours, with no active session.
- No live focus session was started by this integration.

Logs: `/tmp/docard-bold-integration-swift.log`,
`/tmp/docard-bold-integration-node.log`, `/tmp/docard-bold-integration-device.log`.
The earlier simulator captures are branch evidence, not a new physical UI/shield
verification. The new design's physical Emergency Unlock and shield appearance
still need a user walkthrough.
