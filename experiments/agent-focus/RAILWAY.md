# Railway relay deployment

This deploys the Node relay, not the local stdio MCP agent. The relay can deliver
commands and run expiry recovery while the Mac is asleep. New agent decisions still
require the agent to run. Phone execution remains subject to iOS/APNs availability.

## Service configuration

The relay is connected to `YC-0210/Agent-blocking`, branch
`codex/agent-focus-integration`, with root directory `/experiments/agent-focus`.
GitHub deployments build this directory's Dockerfile. Source, branch and root are
declared in `.railway/railway.ts`. Link the existing project/service, then run
`npm ci`, `railway config plan`, and `railway config apply --yes` to apply it. Review
the plan first: it must retain the relay volume. The `railway` SDK is a development
dependency for configuration commands, excluded from the runtime image. CLI source
uploads remain a manual fallback; they are no longer the configured source.

Railway's older `railway.json` format cannot configure new services and stops
being read on December 1, 2026. This project uses the current IaC format instead.
Secrets are unmanaged by IaC and remain in Railway; configuration planning does
not read their values into the source. GitHub is connected to the standalone
Agent-blocking repository.

Attach a persistent volume mounted at `/data` **before deployment**. The IaC file
declares that mount and disables sleeping, runs one replica, checks `/healthz`, and
restarts the process after exit. The image uses Node 22.18.0 (the existing minimum)
and installs production dependencies from the lockfile. It copies only the source
and package manifests; local credentials, SQLite and node_modules are excluded.

Set these service variables privately in Railway:

| Variable | Value |
| --- | --- |
| `DO_CARD_AGENT_TOKEN` | Existing private agent-token file contents, or a fresh random token of at least 32 characters |
| `APNS_PRIVATE_KEY` | Complete `.p8` PEM contents, with real newlines |
| `APNS_TEAM_ID` | Apple team ID |
| `APNS_KEY_ID` | APNs key ID |
| `APNS_TOPIC` | `online.do.card.app` |
| `APNS_ENVIRONMENT` | `development` for the current Xcode Debug app; `production` for a production-signed app |
| `PORT` | `8787`, matching the configured domain target port |

The image already sets `HOST=0.0.0.0` and
`DO_CARD_DATABASE=/data/agent-focus.sqlite`. Environment
secrets take precedence over credential-file variables; existing local file-based
configuration remains supported. Do not commit keys or put secret values in CLI
arguments, logs, screenshots, or chat. Use Railway's private variable UI or pipe
values into `railway variable set NAME --stdin --skip-deploys`.

Generate a Railway HTTPS domain after the service is healthy. An unauthenticated
`GET /healthz` returns only `{"status":"ok"}` after a database query succeeds.
It verifies HTTP/database readiness, not Apple push delivery or phone execution.
Other API authentication is unchanged. This remains the existing single-owner
experiment; deployment does not add multi-user account isolation.

## Phone cutover

1. End any active session before changing the phone's connection.
2. Keep the old relay available until the new endpoint passes health/auth checks.
3. Set the local `docard_focus` MCP entry's `DO_CARD_RELAY_URL` to the new Railway
   HTTPS origin; retain the matching private agent-token file. Reload the MCP client.
4. Explicitly request a new phone invitation (`pair_phone`, `newPhone: true`) and
   open it on the phone. Approve the connection and native policy. The phone stores
   its relay URL, so changing the Mac URL alone cannot migrate the phone.
5. Check fresh phone status, then test an approved short focus session, stop,
   timed expiry, and Emergency Unlock. Test the server expiry backup with the old
   Mac relay stopped. Only a phone receipt/device observation proves execution.
6. Stop the old relay/tunnel after successful validation. Keep its database private
   for rollback; reconnect the phone to the old endpoint if rollback is needed.

The new volume starts with a fresh database. This flow does not copy live queued
commands or active sessions. If pairings must be migrated instead, plan a separate
consistent SQLite backup and phone URL migration; do not copy a live SQLite file
without its WAL state.

## Verification

`npm test` includes real process startup with environment secrets, a public health
check, protected APIs, a durable pairing across SIGTERM/restart, and legacy
credential-file startup. Existing tests cover APNs payloads, durable expiry jobs,
and authenticated MCP/relay behavior. Docker image building requires a running
Docker daemon or Railway's builder. Physical phone delivery must be tested after
the service is deployed and the phone is connected.

## Provisioned service (November 6, 2026)

- Project: [docard-focus](https://railway.com/project/f81af64f-f602-4749-9e53-c73d4494c63b)
- Service: `relay`, environment: `production` (an environment name; APNs remains
  `development` to match the current Debug phone app).
- Volume: `relay-volume`, 500 MB, mounted at `/data`.
- Reserved origin: `https://relay-production-94fa.up.railway.app`, target port 8787.
- Agent token, APNs private key and APNs metadata are stored privately in Railway.
- Deployment `56fe86d4-2396-499d-96b7-cb598f208eae` is successful. Public health,
  unauthenticated rejection, authenticated device discovery and a real stdio MCP
  handshake/pair_phone against the cloud relay have passed. The source upload was
  staged from only Dockerfile, .dockerignore, package manifests and src; no local
  credentials, SQLite or unrelated repository files were uploaded.
- The saved Codex `docard_focus` URL and default device ID point to Railway and
  the cloud-paired phone. A private config backup is retained locally. After the
  owner restarted Codex, its tool connection successfully reached Railway.
- Phone approval is complete. Physical background notification delivery and an
  authenticated phone rejection were verified after repairing the native push-token
  race described below. Actual lock/unlock initially exposed a missing cold-launch
  Family Controls authorization refresh. After repairing that startup path, the
  final clean build visibly blocked and unblocked X through Railway with DO Card
  terminated. See [physical test results](../../docs/testing/railway-lock-unlock.md).
  Timed expiry also passed with the local relay/tunnel stopped and DO Card closed.
- The live API confirms `sleepApplication: false`, `/healthz`, and `ALWAYS`
  restarts. CLI 5.71.0's planner reads the false sleep flag back as null and may
  repeatedly show that setting as drift; this is not evidence that sleeping is on.

## Phone verification follow-up

The owner completed the cloud pairing. Authenticated discovery reports one phone,
two selected apps, a 45-minute maximum and no active session. The existing chat's
MCP connection still returns the old local device, so reconnect/reload is required.

A diagnostic stop with deliberately mismatched approval/session IDs initially
returned `phone_registration_required`, including after reopening the app. A
temporary diagnostic build confirmed Apple returned a token while syncs were
running. `performSync` cleared the shared token after a successful pass, even when
that pass captured nil before a registration callback arrived. It could therefore
erase the token needed by the queued next pass. Retaining the process-local token
across successful syncs fixes that race and lets a new relay pairing register the
same token. This adds an idempotent registration request to subsequent syncs.

Both diagnostic and final iPhone Debug builds passed. The final build was installed
over the existing app without uninstalling; pairing, native selection, mode handle
and 45-minute maximum were preserved. All 89 Swift tests passed. Temporary logs were
removed. The UIKit runtime is outside the Foundation package-test seam, so the
real-phone red/green delivery check is the regression evidence for this repair.

With DO Card backgrounded (Settings foreground), request
`railway-background-check-0103e3cc-d7aa-4c38-a2bf-a42881527338` was accepted by APNs
at 2026-11-06 19:08:55 Taipei time. The phone returned `rejected` /
`mode_not_approved` and published a fresh snapshot; no session was active, maximum
remained 45 and the mode handle did not change. This verifies the actual cloud
relay/APNs/background-phone/receipt path without applying or releasing shields.
A fresh real stdio MCP connection also resolved the cloud-paired phone correctly.

Initially, this chat's pre-existing MCP processes still had the old tunnel URL;
the owner's Codex restart loaded the Railway address. A leftover old default phone
ID was then corrected in saved configuration. The physical tests used the explicit
cloud phone ID and the reconnected MCP tools. Another pairing is not needed.

A separate release-only server diagnostic could not run because SSH host
verification failed. Its temporary access key was removed; host verification was
not bypassed. Subsequent actual cloud focus-start/stop testing first found a native
blocking failure, then passed after the main-app authorization bootstrap was fixed.
The final clean-build cold-process test captured both the X shield and normal X
after the remote stop. Explicit start/stop sessions were stopped. A subsequent two-minute automatic expiry
test also passed: X remained shielded before its deadline, Railway received cleared
phone state 1.640 seconds after it, and X was visibly accessible at the first
post-expiry capture (+4.128 seconds). No stop was sent or DO Card opened. The local
launchd relay/tunnel jobs remain stopped. Native expiry and the cloud backup were
both enabled, so their individual contributions were not isolated.

## Ten-case physical regression suite

All ten deployed-command/physical-X cases passed with the local relay/tunnel off
and DO Card closed. This includes mode and maximum rejection, idempotency, stop
ownership, visible lock/unlock, expiry and unconfirmed-renewal rejection. See the
[case-by-case report](../../docs/testing/railway-ten-e2e.md). No additional product
changes were needed; a blank capture was rerun and manually verified.

## Standalone repository cutover

The standalone checkout is `/Users/chen/Documents/ChatGPT/Agent-blocking`. The saved
Codex `docard_focus` entry runs
`/Users/chen/Documents/ChatGPT/Agent-blocking/experiments/agent-focus/src/mcp-main.mjs`
and reads its token from that directory's ignored `.local/agent-token` (mode 600).
Run `npm ci` in the agent-focus directory before starting the MCP process. A private
Codex configuration backup was retained outside the repository. Existing running
MCP connections may retain their original process until reconnected; use a fresh
stdio connection to verify the configured executable immediately.

The existing Railway project, service, `/data` volume, secrets, HTTPS origin and
paired phone are reused. Repository migration needs no new pairing or native app
installation. The old DOCard-ios remote integration branch was removed after the
full branch history was copied to Agent-blocking. Other DO Card worktrees retain
their existing remotes.
