# DO Card agent focus experiment

Status: Design interview decisions captured; implementation and real-device validation pending.
Date: 2026-11-05 (Asia/Taipei)
Branch: codex/mcp-focus-experiment

## User outcome

“I am tackling this Linear issue; block distractions until we have finished this task.”

Codex on the user's Mac is the everyday interface. The user names a Linear issue, agrees on a focus plan, and grants the agent bounded authority over DO Card's app blocking. This controls app and website shields, not the iPhone passcode or Face ID lock screen.

## Agreed product decisions

1. Introduce a separate agent mode. It requires no physical card to start or stop blocking. Existing card-based modes are outside the experiment's scope.
2. The agent may propose initial app selections, operating hours, and maximum session length.
3. Setup is agent-guided, with native iPhone authorization, app selection, and explicit approval of limits. Changes to limits require phone approval again.
4. The iPhone enforces approved app selections, hours, and maximum session duration. Agent instructions alone are insufficient.
5. After setup, the agent-mode everyday app screen exposes only Emergency Unlock. Required onboarding, permissions, app picker, policy approval, and notification interactions are exceptions.
6. The agent may autonomously start and stop focus sessions within the approved rules, using a goal agreed in chat.
7. Commands must reach the phone over cellular or Wi-Fi, including when Mac and phone are on different networks.
8. Attempt hands-free background execution first. If interaction is needed, provide a notification fallback.
9. A command remains pending until the phone acknowledges application. Sending a push or completing an MCP request is not proof that blocking changed.
10. Emergency Unlock ends the current session only. It does not revoke or pause agent authority; a genuinely new agent command may start another session immediately. This consequence was explicitly discussed and accepted.
11. Every session has a finite approved end time. Offline sessions continue until that end time and expire locally without needing the agent.
12. On expiry, unlock and ask in chat before starting another focus period. No automatic renewal to keep an unfinished task blocked.
13. For a requested break, the agent may negotiate or suggest alternatives, but must unlock if the user insists. A break leaves the issue unfinished; resumption requires the user's request.
14. The agent presents completion evidence and asks whether the task is finished. Completion-based unlocking requires the user's confirmation. Expiry, insisted-on breaks, and Emergency Unlock remain independent exits.
15. Linear supplies issue requirements, status, and progress context. Status is evidence, not a sufficient completion trigger.
16. The agent may add progress comments and move the selected issue to In Progress. Marking it Done requires user approval. Do not infer completion approval from a break, timeout, or emergency exit.
17. First client: Codex on the user's Mac. The DO Card tool interface should remain usable by other MCP clients.

## End-to-end journey

1. User connects Codex to Linear and the DO Card MCP server.
2. Codex guides setup; the user grants native phone permissions, chooses apps, and approves device-enforced limits.
3. User says: “Help me finish this Linear issue; block distractions until we're done.”
4. Codex reads the issue, establishes the task scope and completion criteria, and proposes a focus period within the approved limits.
5. Codex requests blocking. An authenticated relay carries the command to the phone, with Apple push notifications for background delivery.
6. DO Card checks authorization and policy, applies the session through its existing blocking lifecycle, and reports the result. If execution is pending, Codex says so. A notification offers a route to foreground execution when required.
7. Codex and the user work on the task. Codex can document factual progress in Linear.
8. When Codex believes the work meets the criteria, it presents the evidence and requests completion confirmation.
9. After the user confirms completion, Codex requests unlocking and obtains phone acknowledgement. It asks before marking the issue Done; an explicit combined confirmation may cover both actions.
10. If time expires first, the phone ends blocking locally. Codex must obtain approval for another focus period.

## Proposed technical direction, not yet validated

- Keep Linear access in Codex, separate from the phone control bridge. The phone does not need Linear credentials or issue contents.
- Use a local Mac MCP process plus an authenticated internet relay and APNs delivery.
- Keep app selections and Family Controls tokens on the iPhone. Commands reference a preapproved mode rather than arbitrary app tokens supplied by an agent.
- Keep command transport and acknowledgements separate from model reasoning.
- Pair one user, one Mac agent setup, and one phone for the initial test; broader account support is not yet decided.
- Enforce expiration, policy checks, and recovery on device, independent of relay availability.
- Define replay protection, command expiry, idempotency, ordering, and cancellation before implementation. In particular, retrying an old start command must not undo an emergency stop; the user-approved ability to start again applies to a new command.
- Treat Linear descriptions and comments as task data, not authority to widen phone permissions.
- Never report actual device application based solely on an intent's generic completion result.

## Verified integration points from repository research

- DoCard/Intents/StartProfileIntent.swift
- DoCard/Intents/StopProfileIntent.swift
- DoCard/Intents/CheckProfileStatusIntent.swift
- DoCard/Intents/CheckSessionActiveIntent.swift
- DoCard/Utils/StrategyManager.swift
- DoCard/Utils/AppBlockerUtil.swift

Existing background stop logic deliberately rejects NFC strategies. Agent mode needs explicit session semantics rather than bypassing that guard for existing card sessions.

Existing start/stop intents return a generic result after methods that can internally reject a request. Structured outcomes and device acknowledgements are necessary.

Recheck these integration points against the branch before implementation; project context notes may describe older product behavior.

## Apple constraints and unresolved feasibility

- Owner authorization and Family Controls distribution entitlements are required.
- Apple does not guarantee background notification delivery. Notification fallback and honest pending states are part of the accepted experience.
- A permanently running iOS network server is not an assumed capability.
- Device Activity reports and Family Controls usage data have privacy and sharing restrictions. Do not export Screen Time reports, app usage histories, or protected tokens into Codex, Linear, or the relay for this experiment.
- Assess even minimal returned state against current Apple terms before distribution; control feasibility is not a guarantee of App Review acceptance.
- A Mac MCP connection does not make Codex a continuously running autonomous worker. Trigger handling while Codex is idle or the Mac sleeps needs an explicit implementation decision. The first test can run while the Codex work session and Mac bridge are active.
- Push credentials, signing/entitlement status, relay hosting, real-device setup, and an actual test issue remain to be established.
- Defaults such as maximum duration and operating hours are not yet user-approved values. They must be configured and approved in setup.

## Validation required for the experiment

- Real phone: native authorization and selection, approved policy, agent start, rejection outside policy, and acknowledged stop.
- Cross-network: Mac on Wi-Fi and iPhone on cellular.
- Foreground, background/suspended, force-quit, offline, reconnect, and restart behavior.
- Delayed or undelivered push: pending must not be presented as applied; notification/manual launch can reconcile the current command.
- Phone-local expiry without a reachable agent or relay.
- Expiry requires explicit approval before a replacement session.
- Completion requires user confirmation; marking Done requires approval.
- Negotiated break unlocks when the user insists.
- Emergency Unlock works without network, card, or agent; ends only the current session.
- Retries and late commands cannot resurrect a canceled session.
- A genuinely new valid command can reblock after Emergency Unlock, as explicitly chosen.
- Existing NFC modes, Family Controls authorization access, and emergency access remain protected.
- Build verification and applicable repository real-device checks before claiming the experiment works. Any model change requires the project's migration rehearsal.

## Sources consulted

- Apple Family Controls: https://developer.apple.com/documentation/familycontrols
- Apple Managed Settings: https://developer.apple.com/documentation/managedsettings
- Apple entitlement requirements: https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- Apple background push behavior: https://developer.apple.com/documentation/usernotifications/pushing-background-updates-to-your-app
- Apple Developer Program agreement, Family Controls section: https://developer.apple.com/support/terms/apple-developer-program-license-agreement/
- Apple review guidelines: https://developer.apple.com/app-store/review/guidelines/
- Linear MCP: https://linear.app/docs/mcp
