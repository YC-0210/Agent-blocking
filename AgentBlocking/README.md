# Agent Blocking for iPhone

Agent Blocking is a separate iOS app for agent-controlled focus sessions. It uses
the repository's focus engine and native Screen Time picker. The app lets you
choose apps, categories and sites, approve a maximum and allowed hours, see the
active session, and end it locally with Emergency Unlock.

## Build and run

Open [AgentBlocking.xcodeproj](AgentBlocking.xcodeproj) and run the
**AgentBlocking** scheme on an iPhone with iOS 18 or later. The project uses
automatic development signing. After editing targets or signing settings in
`project.yml`, regenerate the project with `xcodegen generate --spec AgentBlocking/project.yml`
from the repository root.

| Target | Bundle ID | Shared App Group |
| --- | --- | --- |
| App | `online.do.card.agentblocking` | `group.online.do.card.agentblocking` |
| Notification service | `online.do.card.agentblocking.FocusNotification` | Same group |
| Expiry monitor | `online.do.card.agentblocking.FocusMonitor` | Same group |
| Shield configuration | `online.do.card.agentblocking.FocusShield` | None |

The app and its two stateful extensions use this group for their private shared
container and Keychain items. The adapter's standalone group is declared in
`DoCard/AgentFocus/AgentFocusDevice.swift`; the three group entitlements come from
`AgentBlocking/project.yml`. The focus targets compile with `AGENT_BLOCKING`.
The new app asks for its own Screen Time grant and keeps its own app selection.

## Connect to an agent

The dedicated [Agent Blocking Railway project](https://railway.com/project/63fb23ae-b160-4e9c-bc70-7945056eadcc)
uses `https://relay-production-ebfb.up.railway.app`. Its relay uses a private
500 MB volume mounted at `/data` and runs the development APNs topic for the
signed iPhone build. The saved Codex entry is `agent_blocking`. Open a fresh
Codex connection before using its tools.

The service deploys from a CLI source upload. The service and volume settings
are in [agent-blocking.ts](../experiments/agent-focus/.railway/agent-blocking.ts).
Use an explicitly linked Agent Blocking directory when applying that file.

### Recreate the setup

1. Deploy the relay using the [Railway guide](../experiments/agent-focus/RAILWAY.md)
   as a separate service. Give it a fresh agent token and its own persistent
   database volume mounted at `/data`. Use the Dockerfile in
   `/experiments/agent-focus` and the `/healthz` health check. The existing
   `.railway/railway.ts` targets the original DO Card relay.
2. Set `APNS_TOPIC=online.do.card.agentblocking` and use an APNs key that can
   send to this topic. Use `APNS_ENVIRONMENT=development` for the Debug build
   and `production` for a distribution build. Check `GET /v1/phone-app` on the
   new relay returns the Agent Blocking bundle ID.
3. In the relay directory, run `npm ci` to build the MCP picker. Configure a
   separate MCP server with this template. Replace the absolute paths and relay
   origin with your setup. Store the matching agent token in a private file.

   ```toml
   [mcp_servers.agent_blocking]
   command = "node"
   args = ["/absolute/path/Agent-blocking/experiments/agent-focus/src/mcp-main.mjs"]

   [mcp_servers.agent_blocking.env]
   DO_CARD_PHONE_APP = "agent-blocking"
   DO_CARD_RELAY_URL = "https://your-agent-blocking-relay.example"
   DO_CARD_AGENT_TOKEN_FILE = "/absolute/private/path/agent-blocking-token"
   ```

4. Call `pair_phone` on the new MCP server. Open its `agent-blocking://setup`
   link on the iPhone or paste the relay address and invitation code. Grant
   Screen Time, choose apps and approve the limits in Agent Blocking. Allow
   notifications for background delivery. Confirm the phone appears in
   `focus_status` before starting a session. Optionally set
   `DO_CARD_DEFAULT_DEVICE_ID` to that phone's returned ID.
5. Start a short focus session from the MCP picker. Confirm the selected app
   shows the shield, then stop the session and open that app again. Repeat with
   automatic expiry and Emergency Unlock on a physical phone.

For TestFlight and App Store distribution, follow the [release runbook](RELEASE.md).
It covers the separate production APNs relay, Apple distribution signing, and the
physical test checklist. See the [Agent Blocking privacy policy](PRIVACY.md).
