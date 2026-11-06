# App identities beside the chat timeline

Owner-approved change: replace app groups in the UI with the selected app's name
and icon beside the duration slider. Apple native selection tokens remain private.

## Interaction and authority

- On iPhone, Manage apps loads the actual private native labels. Choose exactly
  one application, with no categories or websites, then explicitly choose its
  display identity and confirm that it matches. Save publishes only authored name,
  opaque selection ID, and allowlisted icon key. This is a personal association,
  not automatic app identification. Up to eight associations retain the existing
  catalogue's limit. Instagram, TikTok, YouTube, Facebook, Reddit, X and Other app
  are available; Other app has an editable name and generic glyph.
- The chat timeline displays selectable icon/name chips next to the slider, never
  a group dropdown. Opening, editing, refreshing, or choosing a chip does not start
  a session. Explicit Start focus confirms the chosen ID and duration. Maximum
  adjustment remains separate and contains no app controls.
- Native icons/names are not exported. Web glyphs are bundled Simple Icons assets
  with a retained CC0 license/source revision; no icon URL is accepted or requested.
  Authored names use textContent, not HTML. Source-screen identities are never
  inferred from tokens, OCR, screenshots, installed-app inventory or usage data.
- Legacy selections remain usable by older protocol clients, but appear unlinked
  in the new UI and cannot start from it until explicitly associated. The phone
  retains their private choices. Changing a private selection through the older
  editing interface clears its display identity, requiring re-confirmation.
- Internally appGroupID/appGroups storage and wire fields remain for compatibility.
  Names presented by the UI use app terminology. Pairing/mode capture, idle-only
  edits, stale-save protection, active selection restoration, finite expiry and
  Emergency Unlock are retained.

## Verification plan and limits

Existing agreed seams: persisted phone/delivery API; authenticated HTTP relay and
initialized MCP; actual picker program with host/DOM boundary; isolated real
AppBridge host/browser smoke check. Physical one-app association and actual
blocking require the owner's iPhone walkthrough after installation. No test fixture
is evidence that Instagram was selected on the real phone.

## Results and activation

- 84 Swift tests pass, including metadata-only delivery and identity invalidation.
- 92 Node tests pass, including authenticated icon-key allowlisting, unlinked legacy
  choices, icon/name rendering, and separate maximum UI.
- 1 native simulator UI test passes: empty selection cannot Save and Emergency
  Unlock remains available. This exercises the production view with fixture runtime;
  it does not verify actual selection tokens or physical shields.
- Real bundled UI in the isolated AppBridge/MCP/relay host passes icon/name choice,
  slider synchronization, denied-link fallback, refresh, explicit confirm/ack,
  independent maximum, narrow viewport and absence of page errors.
- Signed Debug iPhone app/extensions and Release compile validation (signing
  disabled) both report `BUILD SUCCEEDED`.

RED evidence: `/tmp/docard-app-identity-{phone,relay,ui}-red.log`. Final logs:
`/tmp/docard-app-identity-{swift,node,device,release,native-ui,ui-smoke}.log`.

### Standards review

Independent read-only review found no substantive security/privacy violation.
Native token privacy, static SVGs, safe authored names and finite expiry remain intact.

### Spec review

One finding: editing an Other app name did not reset its prior confirmation.
Corrected by invalidating confirmation on name edits as well as identity/token edits.
No other high-confidence spec defects were identified. Phone mapping, real selected-app
blocking and actual identity correctness still require the owner's walkthrough.

### Allowlist synchronization

All icon keys are `instagram,tiktok,youtube,facebook,reddit,x,other`:

| Source | Purpose |
| --- | --- |
| DoCard/AgentFocus/Core/AgentFocusPhone.swift — AgentAppIdentity | Native identity picker and storage validation |
| experiments/agent-focus/src/relay.mjs — snapshotSchema.iconKey | Authenticated relay metadata validation |
| experiments/agent-focus/src/ui/focus-picker.mjs — identities | Render only approved associated choices |

`app-icons.mjs` has static imports for the six branded keys; Other app uses a generic
bundled glyph. Unknown keys never become an icon URL or an inferred association.

Backed up live SQLite to private `.local/agent-focus.before-app-identities.sqlite`,
restarted the relay, overlay-installed the signed phone build and launched its app
review deep link. Pairing and existing private selections are retained. No session
was started and no Instagram identity was assigned on the owner's behalf. New chat
resources read the rebuilt bundle on demand. The owner must confirm the one-time
association on the phone, then refresh apps or open a fresh session picker.
