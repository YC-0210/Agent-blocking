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

Current local results and any review corrections are recorded below before publication.

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
