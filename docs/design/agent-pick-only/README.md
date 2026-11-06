# Pick apps, then choose time in chat

Owner decision: allow multiple selected apps. The person only picks apps and taps
Done on iPhone. Chat shows a count (for example3 selected apps), without app naming,
identity confirmation, groups or manual refresh. This supersedes the association
form in ../agent-app-identities/README.md. Native names/icons remain phone-private.

## Behavior

- Choose apps opens Apple's native picker directly. One Done action saves the
  nonempty private selection, syncs, and dismisses the sheet. Cancel discards edits.
  Multiple apps, categories and websites retain existing authorization/limits.
  Active-session review is read-only; Emergency Unlock remains accessible.
- Saved edits remain bound to their original pairing and mode generation. Another
  start or settings change prevents stale saves. Existing duration/hours/maximum
  are preserved; changing selections invalidates earlier queued starts.
- The existing phone ownership lock derives counts from the saved default private
  selection while idle, or current session selection while active. Counts are not
  inferred from legacy aliases, icon mappings or category expansion.
- An open, unsent chat session draft polls authenticated phone metadata every3s.
  New counts/mode/limits update its revision, preserving the chosen minutes. It
  cannot mutate an already submitted command or overwrite a simultaneous edit.
  Phone save/poll does not start anything; Start focus still requires an explicit
  user click on the current revision. Maximum adjustment is a separate tool.
- Chat shows apps, categories and websites separately (a category does not imply a
  known expanded app count). No identities or tokens are obtained from the picker.
  Missing counts require phone sync; older protocol clients remain compatible.
- The visible count is also the entry point for changing selections on iPhone.
  If a desktop host cannot open its phone URL, the fallback says to open DO Card.
  There is no standalone review button or manual refresh action.

## Return to chat

Done dismisses the iPhone picker and syncs the count. Chat updates automatically
while open, or when its iframe resumes. A desktop chat cannot be foregrounded by
an iPhone, and the current MCP Apps host supplies no verified return-to-chat URL.
No private Codex URL scheme is invented. On the same phone, return to the chat
client using iOS app switching; no second in-app setup form is required.

## Verification

Agreed seams: persisted phone/delivery API with injected native summary boundary;
HTTP relay; initialized MCP; real picker program at host/DOM boundary; isolated
AppBridge/browser and simulator UI fixtures. These do not prove real selected-app
shield behavior. Physical multiple-app save, automatic count sync and exact
shielding remain the owner's hardware checks after installation.

## Results

- 85 Swift tests pass: default-selection counts, persisted edits/limits, metadata
  delivery, privacy and all prior ownership/expiry regressions.
- 95 Node tests pass: strict count validation, automatic metadata/revision adoption,
  unchanged draft time, no command on polling, stale confirmation rejection, and
  count-refresh versus local-edit conflict preservation.
- 1 simulator UI test passes: direct native picker, no identity/name form, empty
  selection cannot finish, Cancel returns, Emergency Unlock remains accessible.
- The actual bundled UI in an isolated AppBridge/MCP/relay host automatically
  updates3→5 selected apps after a simulated phone save, preserves17 minutes,
  has no manual refresh/review/identity controls, waits for explicit Start, and
  separates the maximum picker. No page errors. Fixture screenshots are not proof
  of physical selection or blocking.
- Signed Debug iPhone app/all extensions and Release compile validation (signing
  disabled) both report `BUILD SUCCEEDED`.

RED evidence: `/tmp/docard-pick-only-{phone,relay,mcp,ui,edit-race}-red.log`.
Final evidence: `/tmp/docard-pick-only-{swift,node,device,release,native-ui,ui-smoke}.log`.

### Standards review

Found a lost sync request when Done overlapped an older upload. Corrected with
a MainActor continuation queue: each caller waits for a pass started after its
request. New arrivals receive the next batch, without waiting for global quiet.
Re-review found no remaining substantive issue. This UIKit runtime scheduling
remedy is supported by compilation/source review; a live overlapping-network
phone test remains separate from the package suite.

### Spec review

Also found a metadata refresh could discard a concurrent local time edit. The
regression failed before the fix and passes now. Metadata-only revisions rebase
the pending edit; real conflicts preserve typed minutes and require explicit
retry. Re-review found no remaining substantive issue in these corrections.

### Activation

Backed up live SQLite to private `.local/agent-focus.before-pick-only.sqlite`,
restarted the relay for count metadata, and overlay-installed the signed build.
Existing pairing, private selections and approved time limits are retained.
The existing MCP process must reload before new drafts can use count-aware
automatic metadata refresh. No live session is started by this installation.
