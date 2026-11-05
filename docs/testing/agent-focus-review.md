# Agent focus review

Baseline: approved design commit `fe7ccb73d9af606b09281e6d88547bf73b1964a8`.
Initial implementation: `c49cd4b`. Initial corrections: `b241205`.
Spec: `docs/experiments/agent-focus-design.md`.

Separate fresh-context reviews checked repository standards and spec fidelity. Findings
below are reported by axis; shared findings intentionally appear in both axes.

## Standards

Seven concrete findings were reported across review/recheck passes:

1. Emergency Unlock cleared platform shields before the file lock, allowing a concurrent
   restore to reapply them. This violated the shared serialization contract.
2. Shields could be installed before durable expiry ownership, leaving an orphan after
   termination or a failed record write.
3. A replacement pairing retained another relay identity's sequence/outbox, rejecting
   valid new commands and potentially wedging receipt upload.
4. Relay submissions read a sequence before awaiting the body, allowing overlapping
   requests to allocate the same sequence.
5. Failed emergency primary-record writes left an old session available for restoration.
6. Comparing relay timestamps with the phone's emergency timestamp did not establish
   causal order when clocks differed; an unseen pre-emergency command could reblock.
7. Unconditionally overlaying an older Keychain cancellation could undo a newer primary
   cancellation when a later Keychain write failed.

All seven were corrected with public-interface regressions. The final scoped recheck
confirmed the revision ordering correction; no further findings in that recheck.

## Spec

Four concrete findings were reported across review/recheck passes:

1. The emergency/restore race could violate “Emergency Unlock ends the current session.”
2. Re-pairing retained sequence/outbox state from the old relay identity, contradicting
   the replay/ordering and fresh-approval contract.
3. A failed emergency record write could resurrect the canceled session after recovery.
4. An older ledger could replace a newer emergency generation, permitting an old queued
   command instead of a genuinely new one.

All four were corrected. Final scoped recheck: prior stale-ledger finding resolved;
`load()` overlays only a strictly newer matching cancellation revision. No additional
scope creep was identified.

## Resolution and evidence

The persisted phone interface holds the OS lock through hardware release; journals pending
ownership before effects; scopes state/receipts by pairing; and uses a separate shared
Keychain cancellation ledger. Opaque mode IDs rotate after emergency cancellation,
invalidating earlier queued commands without reconnecting or widening user-approved limits.
Both stores carry cancellation revisions so stale fallback state cannot roll back a newer
cancellation. The relay allocates and inserts sequences transactionally after body parsing.

Regression failures were reproduced before each correction: read-only session storage,
concurrent installation/release, recreated phone adapters, replacement pairing/outbox,
clock offsets, failing independent-ledger writes, and HTTP 100-continue overlapping bodies.
See `agent-focus-results.md` for counts, commands and validation limits.

Summary: Standards 7 findings addressed; Spec 4 findings addressed. Highest reported
severity was P1 in each axis; no outstanding finding in the final scoped rechecks.
Actual iOS/APNs/shared-Keychain behavior on a signed physical phone remains unverified.
