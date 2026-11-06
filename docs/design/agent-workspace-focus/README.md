# Direct focus picker across workspaces

The user expects “I need to focus” to immediately open a duration selector with a
suggestion, using the existing phone. A screenshot from an unrelated workspace
showed the agent incorrectly offering a new pairing instead.

Cause: all picker/status calls required a device ID held only in the original
chat's conversation. There was no discovery endpoint, default-phone setting or
pairing reuse guard. The existing phone remained paired and healthy.

Implemented 2026-11-06:

- `select_focus_session`, `select_focus_maximum` and `focus_status` accept omitted
  device IDs. An explicit ID wins; otherwise the MCP uses its shared configured
  default, then falls back to discovery only when exactly one phone exists.
- `DO_CARD_DEFAULT_DEVICE_ID` in the shared MCP environment persists the approved
  choice across chats/workspaces. The live Codex configuration now points to the
  already authorized iPhone 13. No credentials or personal ID are stored here.
- Authenticated `GET /v1/devices` returns paired IDs and observation timestamps
  only. It excludes unredeemed invitations and exposes no credentials, push
  tokens, token hashes or selected-app metadata.
- Multiple phones without a default require a choice. A missing configured phone
  fails without silently falling back to another phone.
- `pair_phone` returns `already_paired` instead of creating another invitation
  when a pairing exists. `newPhone: true` requires an explicit additional-phone
  request. First-time setup remains available when the relay has no phone.
- Server initialization instructions and tool descriptions direct the agent to
  open the focus picker immediately, without waiting for Linear lookup. A new
  chat lacking an ID is not evidence of being unpaired.
- The default suggestion is 30 minutes capped by the approved maximum. Opening,
  editing or discovering sends no blocking command. Explicit Start focus remains
  required; maximum changes remain a separate explicit request and tool.

Configuration example (existing shared MCP environment):

```toml
DO_CARD_DEFAULT_DEVICE_ID = "YOUR-EXISTING-PAIRED-DEVICE-UUID"
```

Reload the MCP client after changing its environment/tool definitions. This
setting is shared by workspaces using that MCP configuration, not automatically
copied to other computers or independently configured agent clients.

Validation:

- RED/GREEN through the existing initialized MCP + HTTP relay seam: a fresh chat
  with no phone ID opens a draft, reads status and reuses pairing without commands.
- 106 Node tests pass, including shared defaults with multiple phones, missing
  configured phones, ambiguous discovery, first-time setup and agent-only discovery.
- Fresh real stdio MCP process launched from an unrelated working directory with
  the live shared configuration opened a 30-minute draft for the configured
  phone, with both selected-app identities, and returned `already_paired` from
  pairing. The smoke check did not submit or confirm a start.
- Updated relay activated; global configuration validated as TOML and changed only
  by adding the default-device environment value. A private backup was retained.
- Spec and standards reviews found no remaining actionable issues.

Still needs user verification after Codex restart: the assistant in a fresh
workspace chooses the tool immediately in response to the natural-language
request and the host displays its UI. Tool-level success does not prove the
model's decision or host rendering in that separate chat.

Local evidence: `/tmp/docard-workspace-focus-{red,green,node}.log` and
`/tmp/docard-fresh-workspace-smoke.log`.
