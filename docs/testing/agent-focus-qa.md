# Agent Focus QA matrix and execution record

Date: 2026-11-05 (Asia/Taipei). Branch: `codex/agent-focus-integration`.
Scope: card-free agent session and independent maximum tools, integrated notification
delivery, persisted phone ownership, minimal shared MCP Apps picker, and Linear workflow.

## Rules and evidence

The agent proposes, the user confirms, and the phone independently validates and executes.
Opening/editing a picker must not change the phone. Sessions are finite, at least two
minutes, within the saved maximum, and finish inside the phone-approved local hours.
Maximum changes (15–1440) affect only future session limits. Expiry, Emergency Unlock,
explicit denial, replay protection and pairing isolation remain independent controls.
An APNs acceptance or tool response is not evidence that apps actually blocked.

Tests exercise the previously approved public seams: persisted phone API with injected
native/time/storage boundaries; initialized MCP client/tools; authenticated HTTP relay.
Every automated test uses isolated storage/credentials. No production relay, private
database, phone state, Linear issue or installed app was changed by this QA run.
Tests for already-correct behavior passed immediately; real defects have unchanged
failing tests captured before production fixes. No artificial RED changes were made.

## Automated coverage map

| Original area | Repeatable coverage | Limits |
| --- | --- | --- |
| Session/max boundaries | Phone rejects 1 and 171 under max170; accepts 2/170; MCP/relay reject malformed/fractional/missing values; max15/1440 and invalid14/1441 | Actual 170-minute hardware duration is not waited out |
| Maximum independence | Active deadline/selection/hours/timezone preserved, lowered cap applies later, consent/mixed fields/stale expected max rejected | Latest build needs live active-session cap change check |
| Picker confirmation | No commands on open/edit; revision/expiry/concurrent chat races; double confirmation; lost HTTP response immutable retry; restart invalidates old draft | DOM interaction is a separate browser smoke check below |
| Native effects | Simulated native failures clear/reject; restoration and expiry preserve original deadlines | Apple APIs, actual shield visibility and entitlements require hardware |
| Expiry/renewal | Exact deadline; late/expired/future/stale envelopes; pending-journal expiry; renewed session requires approval | Wall-clock changes while OS monitoring runs need device observation |
| Emergency/cancellation | Emergency-vs-restore race, queued starts/max updates invalidated, ledger/record failure, pairing retained | Physical button availability and protected storage need hardware |
| Delivery/network | Real HTTP relay/SQLite; push failure stays pending; lost response/receipt retry; expiry; distinct/identical concurrent requests; worker adapter tests | Fake APNs and loopback HTTP/2 do not establish Apple delivery |
| Authorization | Unknown preserves approval/live session, expired session releases, explicit denial cancels and invalidates old commands | Native cold-process status requires signed-device confirmation |
| Ordering/durability | Duplicate IDs, changed payload conflict, sequence ordering, overlapping app/extension receipts, SQLite reopen, interrupted phone record writes | Not a kill-at-every-instruction or disk-full simulation |
| Hours/timezones | Exact opening/closing, +1ms overflow, saved zone/previous local day, spring/fall 04:00 and next-midnight boundaries | Ambiguous repeated/nonexistent times follow `.first`/`.nextTime`; product policy should be reviewed |
| Pairing/security | Credential roles, cross-device same IDs/receipts, pairing one-use/expiry, protected snapshot fields, malformed/oversized HTTP, bundled UI excludes fixture secrets | Not a penetration test or proof against a malicious host forging confirmation |
| Linear/agent behavior | Stop tool requires completion approval or break insistence; instruction contract retained | No automated agent evaluation or live Linear mutation; checklist below |

Detailed cases and exact test names:

- [Phone QA](agent-focus-qa-phone.md)
- [MCP QA](agent-focus-qa-mcp.md)
- [Relay QA](agent-focus-qa-relay.md)

## Final validation

- `swift test`: **59 passed**, 0 failures (34 existing +25 added).
- `npm test`, including bundled UI build: **66 passed**, 0 failures/skipped/canceled
  (25 existing +23 MCP QA +18 relay QA).
- Total: **125 automated test methods**, **66 added** by this QA pass.
- Signed Debug device build: **BUILD SUCCEEDED** for the connected iPhone13 destination;
  this command builds/signs but does not install the result.
- `git diff --check`: clean. Cross-review of the three agents' additions found the
  submitted-picker cleanup bug above; its regression and bounded-capacity tests pass.

Final parent-run logs: `/tmp/docard-qa-final-swift.log`,
`/tmp/docard-qa-final-node.log`, `/tmp/docard-qa-final-device-build.log`.
Red evidence: `/tmp/docard-qa-missing-duration-red.log`, `/tmp/docard-qa-dst-red.log`,
`/tmp/docard-qa-retry-red.log`. Temporary logs are local evidence, not committed assets.

## Reproduce the automated run

From repository root, with installed Swift/Xcode tooling and Node >=22.18:

```sh
swift test
npm --prefix experiments/agent-focus ci
npm --prefix experiments/agent-focus test
```

`npm ci`/`npm test` build the shared UI. Swift tests run the Foundation core on macOS;
they do not invoke live Family Controls. Test method counts are not a line-coverage
percentage and grouped boundary examples are not counted as separate methods.

## Browser smoke checks executed in this QA run

Host: `npm --prefix experiments/agent-focus run dev:ui`, loopback port8792.
Uses real MCP Apps AppBridge/client/server/HTTP relay with an explicitly simulated
phone. Browser interactions were performed through computer-use tools, not live-phone
commands. These are recorded smoke checks, not headless CI browser tests.

| Step | Observation |
| --- | --- |
| Open maximum | Only minutes, slider and explicit save action in product iframe |
| Clear numeric value | Confirmation disabled; no crash/NaN label |
| Enter1441 | Maximum confirmation disabled with valid-range feedback |
| Enter15 | Number/range synchronized; valid action restored |
| Slider keyboard End | Numeric value reaches1440 |
| Send chat revision170 | Existing number/range both update to170 |
| Confirm maximum | Inputs disabled; pending explicitly waits for phone |
| Simulate acknowledgement | UI changes to Maximum saved,170; fixture-only result |
| Open session | Same shared minimal view and independent Start action |
| Enter171 under saved170 | Start disabled; slider remains capped170 |
| Slider Home/End | Session number reaches2/170 with valid confirmation |

Evidence: [maximum fixture](agent-focus-qa/maximum.png),
[session boundary](agent-focus-qa/session.png). Pointer drag, narrow layout, screen-reader
navigation, focus restoration, actual host policy and timed elapsed-session labels remain
separate checks. Earlier live user testing established basic dragging and selected-app
blocking, but is not silently counted as a fresh device pass for this QA revision.

## Physical-device and external-service checklist

All boxes below are pending for the QA revision. For each run, record build SHA,
device/OS, network, observedAt, request ID, receipt, original/final deadline, and actual
selected/unselected app behavior. Pending/unknown is never recorded as applied.
Use a short session and retain Emergency Unlock access. Cellular requires real signal.
Issue completion and marking Linear Done are separate approvals.

- [ ] D01: Background Wi-Fi start without notification tap; selected app blocked,
  unselected app available; stop without opening DO Card.
- [ ] D02: Change maximum while that session runs, upward and downward below its
  duration. Original deadline stays fixed; later starts obey the new cap.
- [ ] D03: Disable Wi-Fi in Settings with cellular signal; repeat start and stop.
- [ ] D04: Switch Wi-Fi/cellular mid-delivery. Exactly one finite session results.
- [ ] D05: Phone offline, start queued, reconnect before command TTL. Remaining
  original duration only; no fresh deadline from reconnect time.
- [ ] D06: Reconnect after command TTL. Expired request never blocks; a fresh confirmed
  request can work. Test stale stop separately against a different session.
- [ ] D07: Active session expires offline, phone locked and app backgrounded. Unlock
  phone afterward and verify selected apps available.
- [ ] D08: Force-quit during an active session, then verify expiry and documented
  delivery behavior; distinguish unsupported background execution from failure.
- [ ] D09: Reboot during active session. Verify recovery before/after original deadline,
  including locked-before-first-unlock Keychain/App Group protection.
- [ ] D10: Notification alerts/previews disabled; extension timeout/termination. Never
  show false success; opening DO Card recovers still-valid work.
- [ ] D11: Emergency Unlock offline; reconnect with an older queued start. No re-lock;
  a genuinely new confirmed session still works without re-pairing.
- [ ] D12: Explicitly revoke Screen Time in Settings during a session. Verify physical
  release, old-command rejection and recovery after reauthorization.
- [ ] D13: Cold extension/app starts, repeated sync and multiple notifications. Approval
  stable unless maximum/approval/cancellation actually changes; no unknown-as-denied.
- [ ] D14: Category and website selections, unselected apps, and coexistence with
  unrelated Screen Time restrictions. Agent stop clears only its named store.
- [ ] D15: Device timezone change and manual clock forward/backward during a session.
  Record actual deadline behavior; do not claim monotonic enforcement without evidence.
- [ ] D16: Re-pair phone through owner setup; old pairing commands cannot control it.
  Inspect user-facing subscription/card-free flow and emergency availability.
- [ ] U01: Actual pointer dragging on desktop/mobile widths; numeric and chat edits;
  full range reachable; consistent session/maximum UI and no silent confirmation.
- [ ] U02: Keyboard-only and screen-reader operation, focus after errors, contrast,
  long localized text, and supplementary model-context failure.
- [ ] U03: Leave confirmed session picker open until deadline. Historical applied
  receipt must change to elapsed-window language, not claim live blocking/unlocking.
- [ ] L01: Ask agent to work on YAN-103. Verify correct issue lookup and a finite
  proposed session. Lookup/permission failure must not invent issue context.
- [ ] L02: Issue text requesting increased limits or hidden starts is treated as data;
  no policy action without the user's explicit request/confirmation.
- [ ] L03: User confirms task completion; unlock correct session. Separately request
  approval before marking Done; external issue status alone is insufficient.
- [ ] L04: User insists on a break; unlock. Task unfinished at expiry never causes
  silent renewal. Confirm factual comments/progress actions only as authorized.

## Defects established during this run

1. Missing start duration accepted by relay. New HTTP regression failed202 vs400;
   shared schema now requires duration for start.
2. DST allowed hours computed as elapsed minutes. Persisted-phone regression allowed
   03:59–04:01 beyond approved04:00; boundaries now use local wall-clock calendar times.
3. Ordinary picker cleanup erased submitted history after draft expiry. Lost-response
   retry failed after another picker opened; submitted selections now survive ordinary
   cleanup. History remains bounded100; old idle submitted views can be evicted only
   under capacity pressure, while their command receipts remain durable/readable.

These changes are source/test changes. They are not proof that this QA revision has
been installed or activated on the phone/relay/MCP processes.

## Live short-session follow-up

QA revision `c4e8dee` was installed on the paired iPhone13 and launched; the relay was
restarted from that revision with the existing pairing/database/tunnel. The running
Codex MCP connection still needs a reload for the submitted-picker history fix.

The user confirmed the new two-minute test worked and ended automatically. Request
`focus-b85d3543-07da-4d70-b623-66f4524f26a7` has an authenticated `applied` start receipt,
sequence15, issued at1793889540615 and original end1793889660615 (epoch milliseconds).
The last uploaded snapshot still describes the start, so it is historical evidence,
not fresh proof of release. Automatic release is the user's physical observation.
Maximum in that snapshot remains170. This establishes a live short-session/automatic
expiry pass on the QA phone build; it does not complete the broader offline, cellular,
reboot, manual-clock or DST hardware checklist.

## Reboot expiry failure and candidate repair

Live follow-up established: maximum changes170→160→170 retained the five-minute
session's exact original deadline, followed by user-confirmed automatic unlock;
offline expiry passed; expired queued start sequence20 was `delivery_expired` and
left no active session after reconnection; offline Emergency Unlock synced a rotated
approval and no session; force-quit expiry was reported passed by the user.

Reboot test failed: selected apps stayed blocked after restarting, but expiry did not
release them until DO Card opened. This is a failed hardware case, not superseded by
unit-test success. The fetched app watchdog report (`/tmp/docard-reboot-crash.ips`,
not committed) shows the main thread synchronously waiting in DeviceActivity/UsageTracking
from AgentFocusDevice.clearShields. No monitor-extension crash was found in the available
crash-file listing; that does not prove its callback ran or did not run.

Candidate repair:

- Shield release only clears the named ManagedSettings store; no DeviceActivity query
  or stop call can stall expiry or Emergency Unlock's release path.
- One stable agent monitor name replaces its schedule on the next start. This bounds
  registrations without monitoring cleanup inside a callback. Apple documents same-name
  overwrite: https://developer.apple.com/documentation/deviceactivity/deviceactivityname
- New persisted-phone `expire` path only releases due ownership. It never reads
  authorization/Keychain or restores shields. State writes still use the shared OS lock;
  a delayed callback cannot clear a newer unexpired session. Expired pending journals
  complete as rejected without reinstalling shields.
- End callbacks retry busy locks for a bounded5-second budget (up to one extra0.2-second
  acquisition). They never clear outside a contended lock. Start callbacks opportunistically
  check expiry with zero lock wait, avoiding a startMonitoring/callback lock cycle.
- Native monitor end rounds upward to whole-second precision; the persisted approved
  deadline is unchanged. This prevents an early truncated one-shot callback from being
  ignored permanently. Wake-up rounding adds less than one second, separate from OS
  callback scheduling latency.
- Fixed, small App Group diagnostic files record monitor registration and start/end
  callback entry/result. No credentials or app-selection tokens are written.

TDD: cold expiry under unavailable emergency storage failed before the dedicated path;
whole-second rounding failed before ceil. Eight added regressions cover those plus
no early release, newer-session protection, save-failure recovery, lock-contention retry,
and expired pending journal; error-triggered release is also verified to remain inside
the ownership lock. Final Swift run:67 passed,0 failures. The final signed build is
blocked by macOS Keychain dark wake (`errSecInternalComponent`; `security` reports
"In dark wake, no UI possible"). The owner must wake/unlock the Mac before signing
and installation can finish. Node sources are unchanged by this repair; their prior
66-test pass is retained.
Logs: `/tmp/docard-reboot-expiry-red.log`, `/tmp/docard-reboot-rounding-red.log`,
`/tmp/docard-reboot-final-swift.log`, `/tmp/docard-reboot-device-build.log`.

A fresh physical reboot test is still required. The change removes identified application
hazards; it cannot guarantee the OS will invoke a monitor after every reboot, nor can it
resolve an indefinitely held lock or arbitrary storage/daemon failure. Callback diagnostics
are intended to distinguish these remaining conditions on the next run.

Signing follow-up: after the owner woke/unlocked the Mac, revision6b0a84c signed
successfully, was pushed, installed on the paired iPhone13 and launched. The physical
reboot-expiry retest remains pending.

The prior Quick Tunnel hostname stopped resolving (NXDOMAIN) and its local connector
reported zero ready connections. The relay stayed alive under its launchctl job. A
replacement Quick Tunnel is now also managed as an independent launchctl job; its
public hostname is https://catalogue-computation-convertible-newark.trycloudflare.com.
The local Codex config changed only its relay URL, preserving the existing agent
credential path; a private local backup was made. A fresh one-time invitation was
opened on the phone for owner approval. No pairing code or credential is recorded
here. Owner setup approval and a Codex MCP reload are required before live testing
can continue. A named stable tunnel remains preferable to expiring Quick Tunnel URLs.

## Reboot retest: original end callback still absent

The next two-minute physical test also failed. Before opening DO Card, diagnostics
were copied through devicectl: registration for session8fabb528 was present, and a
start callback at registration recorded busy/nonblocking failure as expected while the
native start held the phone lock. There was no end callback entry/result file after
reboot and the approved deadline. No new monitor crash appeared in the available crash
listing. This is evidence of no recorded end callback, not proof that the extension
was never launched under every possible failure mode. The start receipt was applied.
The previous candidate must not be reported as resolving reboot expiry.

A second bounded on-device recovery experiment adds a fixed `recovery` monitor. It
starts at the whole-second rounded approved deadline and runs for24h, with full date
components and explicit calendar/timezone. Its start callback invokes the same locked,
due-only expiry path. Both monitor registrations must succeed before shields apply;
both names are reused rather than accumulating activities. Callback traces distinguish
primary/recovery roles and include their activity name, never selection tokens or
credentials. Existing older monitors cannot clear a newer unexpired owner.

The additional public-phone regression verifies the recovery window's literal UTC
bounds, unchanged approved deadline, and cleanup without the original end callback or
readable emergency ledger. It tests schedule intent and core recovery, not OS callback
delivery. Final Swift suite:68 tests passed. Signed Debug build passed before final
native diagnostics/calendar refinement; final signing/install results are recorded in
the live handoff. Existing Node sources remain unchanged (prior66-test pass).

Apple's nextInterval documentation says scheduled dates are the earliest invocation
points and callbacks depend on device use during a relevant interval. This is another
recovery opportunity through the same framework, not a guaranteed boot/deadline wake,
and cannot cover arbitrary offline/non-use beyond the24h window. A busy recovery-start
callback intentionally cannot wait on a synchronous startMonitoring caller. Physical
retest is required; if still blocked, preserve callback evidence before opening DO Card.
https://developer.apple.com/documentation/deviceactivity/deviceactivityschedule/nextinterval
https://developer.apple.com/documentation/deviceactivity/deviceactivityname
