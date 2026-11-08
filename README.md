# Agent Blocking

Agent Blocking is an iPhone app that lets you start a focus session from Codex
and block the apps and websites you choose. You pick what to block on your phone,
set a maximum session length and allowed hours, and confirm when a session starts.

- **Choose what to block.** Select apps, categories, and websites with the native
  Screen Time picker.
- **Start and stop from Codex.** Pair your iPhone with the `agent_blocking` MCP
  server. A Railway relay delivers commands through Apple Push Notification
  service, so the iPhone can apply them while Agent Blocking is closed.
- **Stay in control.** Blocks clear automatically when a session expires. You can
  also end the session on your phone at any time with Emergency Unlock.

## Getting started

Agent Blocking is being tested as an Xcode development build on iPhone with
iOS 18 or later. The standalone app project and setup guide are in the local
development checkout under `AgentBlocking/`.

1. In the development checkout, open `AgentBlocking/AgentBlocking.xcodeproj`
   and run the **AgentBlocking** scheme on your iPhone.
2. Follow `AgentBlocking/README.md` to configure signing, the Railway relay,
   and the Codex MCP server.
3. In Codex, use `pair_phone` to generate a one-time pairing link. Open it on
   your iPhone, grant Screen Time and notification permissions, then choose what
   to block and set your session limits.
4. Tell Codex “I need to focus,” choose a duration, and confirm the session.

## Repository layout

- [DoCard/AgentFocus/](DoCard/AgentFocus/) contains the shared focus engine.
- [experiments/agent-focus/](experiments/agent-focus/) contains the MCP server,
  Railway relay, and tests.

## License

[MIT](LICENSE). The project builds on [Foqos](https://github.com/awaseem/foqos)
by [Ali Waseem](https://github.com/awaseem).
