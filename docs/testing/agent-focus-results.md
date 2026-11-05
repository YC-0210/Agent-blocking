# Agent focus experiment verification — 2026-11-05

Branch: `codex/mcp-focus-experiment`.
Baseline: `fe7ccb73d9af606b09281e6d88547bf73b1964a8` (approved design spec).

## Agreed seams and TDD evidence

The user explicitly approved all three seams before tests were written:
phone focus commands, authenticated relay commands, and Codex MCP tools.

The first behavioral red run requested 46 minutes against a 45-minute approval.
It failed with `XCTAssertEqual failed: nil is not equal to duration_exceeds_approval`.
The minimal duration guard then passed. Following cycles added one failing test and
its minimal implementation before proceeding. Test names describe externally visible
behavior; no private functions or database contents are asserted.

- Phone command tests: limits/hours, expiry independent of the agent, stale/future
  delivery, session-specific stops, emergency/replay after recreation, renewal approval,
  failed platform execution, receipt retries, queued-before-emergency starts, and
  recovery when expiry cannot be restored.
- Relay tests: unauthenticated requests, one-use pairing, credential isolation,
  phone acknowledgements, idempotency, expiry, device scoping, terminal receipt
  conflicts, allowlisted snapshots, silent push followed by alert fallback, and
  ES256-signed APNs requests exercised through a local HTTP/2 Apple stand-in.
- MCP tests: pending start, completion confirmation, phone rejections, setup link,
  observed limits, Linear focus instructions and tool discovery through a real
  stdio child process.

Run commands:

```sh
swift test
npm --prefix experiments/agent-focus test
```

Local results:

- 20 Swift phone tests passed, including the persisted phone interface and concurrency.
- 18 Node relay/MCP tests passed (11 relay, 7 MCP).
- 65 existing native iOS regression methods passed across UnlockRecoveryTests,
  SubscriptionLifecycleTests, ActiveSessionStatusTests, SelectionRulesTests and AppUpdateTests.
- Debug and Release simulator builds reported BUILD SUCCEEDED. Signing was disabled;
  these are compilation checks, not physical provisioning or APNs entitlement approval.
- npm audit reports zero vulnerabilities in the pinned dependency graph.

The first two-axis reviews identified seven distinct defects: emergency release racing
restoration, non-durable shield ownership, old pairing replay/outbox state, duplicate
relay sequences under overlapping request bodies, cancellation resurrection after a
failed emergency record write, reliance on cross-device timestamp ordering, and an older cancellation ledger overriding a newer primary cancellation. Each received a failing public-interface
regression before correction. Emergency release is serialized; pending ownership is saved
before effects; pairing identity scopes state; sequence allocation and insertion use a
SQLite transaction. The overlapping-request test uses HTTP 100-continue to reproduce the
race without depending on timing. A file-permission failure verifies that persistence
failure cannot install unowned shields. Retry checks verify no extra physical installation. A separate Keychain-seam cancellation
fixture prevents restore after failed emergency file writes. Ahead/behind clock cases
verify that rotating the opaque mode handle rejects all earlier queued starts while
retaining immediate control through a newly observed handle. Shared cancellation revisions prevent an older ledger from undoing a newer durable primary cancellation.

Simulator smoke: the revised app installs/launches on a dedicated iPhone 17 Pro simulator;
the custom setup URL is registered and produces the system's Open confirmation. Real
Screen Time permission/app selection and completed setup require a physical phone.

See `agent-focus-review.md` for the initial review findings and their resolution.

## Physical-device prerequisites and limits

The user needs setup instructions for both APNs and relay hosting. They are in
`experiments/agent-focus/README.md`. No Apple key was supplied or created, no public
relay was deployed, and no phone was connected for live validation. Local tests must
not be represented as a successful cellular experiment.

Still required: signed build and Family Controls authorization, real app picker tokens,
APNs device registration/delivery and alert fallback, Mac Wi-Fi/phone cellular, offline
expiry, restart/recovery, Emergency Unlock without the agent, and the accepted task/
Linear flow on an actual issue. DeviceActivity scheduling is subject to iOS execution.

No App Store/TestFlight submission, SwiftData model/migration changes, or production
Linear task updates are included.


## Standalone entry follow-up (2026-11-05)

User screenshot exposed the root subscription screen after the earlier adapter-only
exemption. Root now always presents Agent Focus and does not instantiate StoreKit or
run subscription reconciliation; subscription-expiry monitor callbacks return without
enforcing access. Signed Debug device and simulator builds succeeded. Installed and
launched on the user-approved iPhone 13 through devicectl. Simulator launch screenshot
`/tmp/docard-agent-direct-entry.png` visually confirms Agent Focus setup without a
subscription or legacy onboarding screen. Actual pairing/shields remain to be tested.


## Physical phone first start (2026-11-05)

The paired iPhone rejected a 15-minute start with execution_failed. A temporary
console probe isolated Apple DeviceActivity intervalTooShort. The session deadline
is measured from relay issue time, so delivery leaves less than the 15-minute system
minimum. Backdate only the native monitoring start to at least 901 seconds before
the unchanged approved end (one second allows DateComponents truncation). No approved
end, hours, duration or command TTL is extended. This also covers late restoration.

Public MCP/phone regression loop on the physical iPhone: two 15-minute commands were
rejected before the fix; a fresh 15-minute command was applied after the signed build
and installation. The debug probe was removed before the successful build. The real
DeviceActivity error is not reproducible in the Foundation-only package; this is a
physical-device boundary check, not a new unit test. Visual shield appearance, offline
expiry and cellular delivery remain separate user/device checks.
