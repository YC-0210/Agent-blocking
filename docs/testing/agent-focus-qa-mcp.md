# Agent focus MCP QA

Date: 2026-11-05. Branch: `codex/agent-focus-integration`.

## Approved seams and isolation

Tests invoke tools/resources through an initialized MCP SDK client and the real MCP
server, with the real relay serving HTTP against temporary in-memory SQLite. Assertions
read the documented device queue, snapshots and receipts over HTTP, never database
internals. Device snapshots/receipts simulate the external native-phone boundary.
The lost-response fixture forwards requests to the real relay, consumes the accepted
response, then drops the client connection once. Injectable clocks cover expiry.
No live phone, tunnel, APNs, Linear connection or stored credential is used.
All credentials are test literals or generated pairing credentials.

## Added coverage

`experiments/agent-focus/test/mcp-qa.test.mjs` adds 23 tests:

- Maximum endpoints 15/1440 and session endpoints 2/1440 produce separate command envelopes.
- Invalid bounds, fractional/string durations, malformed device IDs and invalid
  confirmation/revision values leave the device queue empty.
- Opening/editing either purpose sends no command; exceeding the saved session
  maximum does not raise that maximum; revising cannot change purpose.
- A changed saved maximum or rotated approval rejects stale confirmation. Active
  sessions reject another start while allowing a separate maximum update.
- An intervening session start and expired drafts reject confirmation.
- Concurrent maximum confirmations and later retries preserve one command/sequence.
- A lost response reports unknown; retries preserve the payload even after ten
  minutes and report the original command's expiry without another queued command.
- Opening another picker after draft expiry preserves the submitted view needed to
  reconcile an ambiguous response, subject to the bounded history policy below.
- One hundred fresh drafts reject the 101st without losing a draft or queuing work.
  One hundred expired submitted views allow another picker by evicting one idle
  historical view; its receipt remains readable and retrying the evicted view cannot
  submit another command.
- Break insistence and completion confirmation are independent stop permissions.
- Pending/rejected/applied receipts remain distinct; a fresh phone snapshot supplies
  the next picker with the newly acknowledged maximum and policy handle.
- A new MCP instance rejects old selections but can read their queued command receipt.
- Missing phone setup blocks both pickers. The served UI is bundled, has no external
  script source, excludes fixture agent/device credentials and declares no resource
  or connection domains.

Existing `mcp.test.mjs` retains the real HTTP-gated confirmation regression: concurrent
60-to-1440 revision and expiry during the phone check both reject without queuing.
It also covers real stdio discovery and completion-stop confirmation.

## Results

Commands run from `experiments/agent-focus`:

```sh
node --test test/mcp-qa.test.mjs
node --test test/mcp*.test.mjs
npm test
```

Latest MCP-only validation: **35 passed, 0 failed, skipped or canceled**
(23 added, 12 existing). Both new capacity methods passed in a separate targeted run.
The final full Node suite/UI build is recorded by the parent integration validation;
these MCP-only counts do not claim a new full-suite run.

The submitted-history regression was observed RED through the public MCP interface:
after a lost submission response, advancing 600001 ms and opening another picker made
the original retry return `selection_missing`. The parent changed cleanup to preserve
immutable submissions during ordinary draft expiry. The same regression is now GREEN.
No production files were changed by this QA agent.

## Bounded picker history

At most 100 picker views are retained in one MCP process. Ordinary cleanup removes
expired unsubmitted drafts. At capacity, a new picker may evict an old, idle submitted
view whose original draft lifetime has elapsed; fresh drafts and in-flight submissions
are not eligible. An evicted view returns `selection_missing` and cannot resubmit.
Its immutable request ID and phone receipt remain in the relay and are still available
through `command_status`. Thus ordinary expired-view retries preserve their payload,
while history pressure bounds view retention without creating a replacement command.

## Remaining manual/system validation

Resource retrieval does not execute the iframe: actual dragging, numeric entry,
chat polling, range expansion, revision conflicts shown to the user, accessibility,
localization, host visibility enforcement and elapsed-session labels still need UI
validation in a compatible MCP Apps host. Attestation fields cannot prove a human
clicked. No test calls Linear or proves task completion; verify issue selection,
progress comments and explicit Done/completion permission separately.

Native policy persistence, maximum changes preserving an active session deadline,
real shield application/release, OS authorization, APNs delivery, offline expiry,
reboot recovery and signed physical-device behavior require their native/device
checks. A simulated applied receipt is not proof that Apple shields were applied.
