# DO Card agent focus experiment

Codex on your Mac reads a Linear issue and controls a separate agent focus mode on your iPhone. No card is needed. The phone owns app selection, approved hours, duration limits and expiry. The everyday agent screen contains Emergency Unlock only.

This branch contains working code and local automated tests, not a deployed service or a verified real-phone result. Apple signing, APNs credentials, an HTTPS endpoint and a physical iPhone are required to finish cellular validation.

This worktree implements the **visible Notification Service Extension** delivery path.
The relay immediately sends a mutable alert; a small extension fetches and applies the
command without opening the main app when iOS allows it. This still needs physical-phone
validation. See [isolated setup and device checks](../../docs/testing/notification-extension-focus.md).
Use a separate relay port (8788), database, tunnel and MCP entry for this worktree.

## What runs where

- **Codex on Mac:** connected Linear tools plus this local stdio MCP server.
- **Relay:** Node HTTP server, persistent SQLite database and APNs sender. For the experiment it can run on the same Mac behind an HTTPS tunnel. Keep the Mac awake and both processes running.
- **iPhone:** native app selection and policy approval, command execution, independent local expiry and Emergency Unlock. No Linear credentials or Screen Time histories leave the phone.

This branch opens Agent Focus directly on launch; the legacy home, onboarding and
subscription screens are not shown. StoreKit refresh and subscription expiry do not
participate in the experiment lifecycle. Native Screen Time and policy approval remain
required by the phone.

This supersedes the no-device-sync rule in ADR-0008 only for the explicitly enabled agent experiment. Existing card and scheduled modes keep their behavior. Finish existing sessions and disable existing schedules before enabling agent mode. No SwiftData models or migrations change.

## 1. Create your Apple push key

1. Sign in to [Apple Developer: Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Open the App ID `online.do.card.app` and enable **Push Notifications**. Keep Family Controls and the App Group enabled.
3. Under **Keys**, create an **Apple Push Notification service (APNs)** key. Choose development access for the first Xcode Debug test and a topic matching the App ID. Your Account Holder/Admin may need to do this.
4. Download the `.p8` key and keep it outside the repository. Record the **Key ID** and **Team ID**. The APNs key is different from an App Store Connect API key.
5. In Xcode, use your authorized development team and automatic signing. Refresh provisioning profiles to include push. Debug uses the development push environment; Release uses production. Match the relay environment and key configuration to the installed build.

See [Apple's key setup instructions](https://developer.apple.com/help/account/keys/create-a-private-key/) and [APNs requests](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns). Do not paste the key or agent token into chat, Linear, or Git.

## 2. Prepare and start the relay

From this directory (`experiments/agent-focus`):

```sh
npm ci
node scripts/init-local.mjs
```

Edit `.local/relay.env`: fill in the absolute `.p8` path, Key ID and Team ID. The generated agent token remains in a separate private file. Then:

```sh
node --env-file=.local/relay.env src/relay-main.mjs
```

The server binds to `127.0.0.1:8787`. It fails clearly if APNs configuration is missing. The local SQLite database persists pairings, sequence numbers and command receipts across restarts. Keep `.local/` backed up privately if you need to retain the pairing; it is excluded from Git.

## 3. Give the phone an HTTPS address

For a temporary experiment, install `cloudflared` using [Cloudflare's instructions](https://developers.cloudflare.com/tunnel/get-started/), then run in another terminal:

```sh
cloudflared tunnel --url http://localhost:8787
```

Copy the printed `https://...trycloudflare.com` address. No Cloudflare account/domain is needed for a quick tunnel. Do not enable browser/email access challenges: the phone uses authenticated HTTP requests, not an interactive browser. The relay itself checks credentials on every protected route.

Quick tunnels are temporary and their address changes on restart. A changed address needs a fresh phone pairing; end an active session before reconfiguring. Use a stable HTTPS hostname for longer testing. These are development tunnels, not a production hosting plan. [Cloudflare Quick Tunnels](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)

## 4. Connect Codex

Add a local stdio MCP server with these settings, substituting your actual absolute checkout path and tunnel address:

```toml
[mcp_servers.docard_focus]
command = "node"
args = ["/absolute/path/DOCard-ios-mcp/experiments/agent-focus/src/mcp-main.mjs"]

[mcp_servers.docard_focus.env]
DO_CARD_RELAY_URL = "https://YOUR-HOST.trycloudflare.com"
DO_CARD_AGENT_TOKEN_FILE = "/absolute/path/DOCard-ios-mcp/experiments/agent-focus/.local/agent-token"
```

Use Codex's MCP configuration UI or your existing configuration workflow; reload the client to discover the tools. Keep Linear connected separately. The Linear connector in this chat already works; it is not embedded in the phone or relay.

Tools:

- `select_focus_session`: the first action for “I need to focus” or “I need to lock in.” Omit `deviceId` to
  reuse the paired phone across workspaces. Opens a suggested 30-minute draft,
  capped by the approved maximum; the user can adjust and must press Start focus.
- `pair_phone`: reuses an existing pairing by default. Creates a private, one-use
  10-minute invitation only if no phone exists, or with `newPhone: true` after an
  explicit request to connect an additional phone. A new chat is not a new pairing.
- `focus_status`: last phone-observed policy/session, with `observedAt`; it may be
  stale. Omit `deviceId` to resolve the same shared phone and return its ID.
- `start_focus`: supports sessions from 2 minutes up to the phone-approved maximum.
  Native monitoring uses an earlier window start to satisfy Apple's 15-minute monitoring
  minimum without extending the approved blocking deadline. Use the approved `modeID`, duration, fresh session ID, and stable request ID. Refresh focus_status before each start; Emergency Unlock rotates the handle. Reuse the same request ID on retries.
- `stop_focus`: targets one session; `completed` requires `completionConfirmed: true`, and `break` requires `userInsisted: true`.
- `command_status`: pending/applied/rejected/expired command result. Only the phone can acknowledge application.
- Prompt `focus_on_linear_issue`: guides Codex through Linear requirements, focus, breaks and completion approval.

Confirmation flags represent what the user said in chat. The MCP server cannot independently prove that an AI agent reported that conversation truthfully. The phone independently enforces scope, hours and duration, and exposes Emergency Unlock.

## 5. Pair and approve on the phone

1. Install this branch's Debug build on a physical iPhone via Xcode. Agent mode in this experiment does not require a subscription. Screen Time authorization and phone-approved limits are still required.
2. End existing card/manual sessions and disable schedules first. Prefer a dedicated test phone. This experiment never clears a legacy shield store.
3. For first-time setup, ask Codex to call `pair_phone`. For an additional phone,
   explicitly request it (`newPhone: true`). Existing pairings are reused. Open
   a newly issued `docard-agent://setup?...` link on the iPhone. The invitation
   also returns the plain relay URL and code.
4. On the phone, approve Screen Time, choose apps/websites with Apple's picker, and approve hours and maximum session length. The agent can help you choose a plan in chat; the native picker is the actual app-selection authority. The prototype defaults to 45 minutes and full-day hours until you approve different values. Hours currently describe one daily, same-day interval.
5. Tap **Approve and connect** and allow notifications. The normal screen becomes agent instructions plus **Emergency Unlock**.
6. Ask Codex for `focus_status`, which provides the phone-approved `modeID`. Then use the Linear focus prompt or say: “Help me tackle this Linear issue. Block distractions until we finish.”
7. Starts remain pending until the phone applies them. The relay immediately sends a visible mutable notification. The bundled notification extension attempts to fetch and apply the command automatically, then shows a generic result. If it stays pending, open DO Card for the foreground fallback. Notification settings and iOS execution limits still apply. Commands expire after two minutes, so a much later tap cannot unexpectedly block you.
8. Changing limits or the connection requires a new setup invitation and fresh phone approval, with no agent session active.

## Agreed task behavior

- Read Linear as task context; move the selected issue to In Progress and add factual progress comments as appropriate.
- Present evidence and ask the user to confirm completion before completion-based unlocking. Ask separately before marking Done, unless the user explicitly approves both together.
- The agent may negotiate breaks but must unlock when the user insists. Resuming requires the user's request.
- At the session end, the phone unlocks without needing internet. Ask before starting another period; set `renewalConfirmed` only after approval. The phone rejects an unconfirmed renewal after expiry.
- Emergency Unlock ends this session and rejects earlier queued commands, but does not disconnect the agent. Emergency Unlock rotates the opaque modeID to invalidate all earlier queued starts, even if the relay clock differs. Read focus_status again; a genuinely new command using that current handle can start another session without reconnecting or reapproving limits.
- Codex does not continuously monitor Linear while it or the Mac is inactive. No autonomous background agent scheduler is installed.

## Verification

From the repository root:

```sh
swift test
npm --prefix experiments/agent-focus test
xcodebuild -project DoCard.xcodeproj -scheme DoCard -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

Tests use the real phone command controller, a real SQLite relay over HTTP, a real initialized MCP client/server (plus stdio process), and a local HTTP/2 APNs stand-in at the Apple system seam. They do not mock internal modules. Only external platform effects, clocks, credentials and temporary storage are supplied by fixtures.

Passing these tests does not prove actual Apple shields, APNs delivery, cellular access or exact-second background expiry. DeviceActivity callback timing is controlled by iOS. The phone also reconciles on foreground/push and fails open if recovery cannot register local expiry; it never claims an infinite session is safe.

Before claiming the experiment works, run the physical-device scenarios in `docs/experiments/agent-focus-design.md` and record outcomes. No App Store or TestFlight submission is part of this implementation.

## Shared timelines and separate maximum tool

The agent now opens `select_focus_session` for session duration, or
`select_focus_maximum` ONLY when you ask to change the saved maximum. Both use the
same draggable timeline in MCP Apps-compatible clients. Ask “make it 20 minutes” to
revise an open session picker, or “change my maximum to 60 minutes” to open the separate
maximum picker. Review and click Start/Save; opening or dragging sends no phone command.
Maximum changes affect future sessions only, with a phone acknowledgement before saved.

After merging this branch with the delivery work, install the updated phone build,
run `npm ci` in the final experiment directory, and reload its MCP server. The UI is
bundled during install; `npm run build:ui` rebuilds it. Keep agent credentials outside
the UI and use the final checkout's existing private configuration. The live phone and
MCP configuration are not changed by the isolated UI development host.

For the test host, run `npm run dev:ui` and open http://127.0.0.1:8792 . It has a clearly
labelled in-memory test phone and no access to the real phone. Full protocol/trust and
merge instructions: `docs/experiments/agent-timeline-tools.md`.

## Demo language

Normal picker builds follow the chat host's language, with browser/device language
fallback and English for unsupported languages. The native app follows its iOS
app/device language. For the current English demo, build the picker with:

```sh
DO_CARD_DEMO_LANGUAGE=en npm run build:ui
```

This explicit demo override survives host locale updates. To restore automatic
selection, run `npm run build:ui` without the variable. Open a fresh chat picker
to load the rebuilt resource. Existing open pickers retain their loaded code.

Launch the installed phone app in English temporarily, without changing device
or persisted app-language preferences:

```sh
xcrun devicectl device process launch --device IPHONE_HARDWARE_UDID \
  --terminate-existing online.do.card.app -- -AppleLanguages '(en)' -AppleLocale en_US
```

These are Apple's documented language-testing launch arguments. A normal app
relaunch without them returns to its app/device language. No phone rebuild is
needed for this temporary demo setting.


Validation: 100 Node tests pass, including automatic language selection and the
English demo override under a Traditional Chinese host. An isolated browser with
`zh-TW` locale verified English session and maximum controls. The demo resource
was rebuilt with `DO_CARD_DEMO_LANGUAGE=en`; the paired iPhone was relaunched
with English arguments and a fresh live chat picker opened.
