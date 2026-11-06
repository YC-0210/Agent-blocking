# App groups in agent chat

Branch: `codex/agent-app-groups`. Base: integration `bafd12b`.
Worktree: `/Users/chen/Documents/ChatGPT/DOCard-ios-app-groups`.
This work does not install a phone build, restart the live relay/MCP server, modify
their configuration, or submit live commands.

## User experience

1. Open a session duration picker in chat. Choose a saved app-group alias alongside
   the existing minutes/slider. The agent can also revise the draft's `appGroupID`.
2. Review/change on iPhone opens `docard-agent://apps` on the paired phone. If the
   chat host denies the custom URL, open DO Card and tap Review app groups instead.
   Desktop users can copy the displayed link to their phone. No universal-link
   domain or QR provisioning is claimed here.
3. The phone shows actual apps, categories and sites using Apple's native token
   labels. While idle, create/edit up to eight groups with the system picker.
   Saving explicitly shares only the alias the person types with their agent and
   relay. The screen explains this before Save group and share name. Prefer generic
   aliases such as Deep Work; app identities aren't extracted to generate names.
4. Return to chat and press Refresh groups after phone sync. Review the group and
   duration, then explicitly press Start focus. Neither selecting nor refreshing
   a group starts a session.
5. During a session, Review this session's apps shows its chosen private selection.
   Editing is disabled. Emergency Unlock is available in the review toolbar and
   main screen. After expiry, the UI distinguishes a past deadline from confirmed
   release. It never obtains an expanded app list from a category token.

The separate maximum-time picker has no app-group controls and cannot select apps.
`review_focus_apps` is a read-only tool for aliases, observation time and a
session-specific phone link, including when a new session picker is unavailable.
Aliases are untrusted user-authored data, never instructions to the agent.

## Authority and persistence

- App-group IDs and authored aliases are metadata; native selection tokens and
  automatically obtained app names/icons never enter the relay, MCP or chat.
- The authenticated phone snapshot projects an explicit allowlist of metadata.
  Strict relay schemas reject nested tokens, unknown properties, duplicate IDs
  and malformed aliases. No installed-app inventory or usage export was added.
- Local group editing shares the existing phone ownership lock and is refused
  while a session or platform-effect journal exists. Edits rotate the approval
  mode, invalidating stale proposals/queued starts without changing duration/hours.
- Confirmation binds the exact draft revision and chosen ID. The phone independently
  resolves that ID; an unknown group is rejected, never silently replaced.
- A start journals the chosen private selection before applying effects. The
  persisted active selection restores across process restarts and is unchanged by
  maximum changes. Session expiry, APNs delivery, cancellation and Emergency Unlock
  retain their existing ownership rules.
- Old records without groups project a default Saved apps group, preserving their
  selection and limits. Existing clients omitting `appGroupID` select that default.
  New pairing approval resets the catalogue; credentials cannot access another
  pairing's selections.

## Apple constraints and review limits

Apple's [native picker](https://developer.apple.com/documentation/familycontrols/familyactivitypicker)
returns opaque selections; [activity labels](https://developer.apple.com/documentation/familycontrols/displayingactivitylabels)
display their identities on the phone. The [developer agreement's Family Controls
section](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/)
restricts device/usage data sharing. This design keeps those protected identities
on the phone and uses explicitly authored aliases for chat. It is an engineering
implementation, not an Apple entitlement/distribution approval guarantee. No
screenshots, OCR, report/shield-extension extraction or EU-only data-access API is
used to export app identities.

## Validation

- Swift:81 tests pass, including selected-group restoration, active-edit rejection,
  stale approval, unknown group, legacy-record migration, pairing isolation,
  metadata constraints and actual snapshot-token exclusion.
- Node:84 tests pass, including real initialized MCP/HTTP relay group choice,
  explicit refresh/revision confirmation, group/maximum separation, read-only review
  links, strict metadata validation and existing delivery/expiry regressions.
- Full app/extensions simulator Debug and Release builds: BUILD SUCCEEDED.
- Real bundled chat UI with isolated AppBridge/client/relay/phone fixture: group
  selection, slider synchronization, denied-link fallback, explicit refresh,
  confirm/ack, separate maximum and narrow layout pass; no page errors.
- Native review was compiled; physical labels, private picker behavior, deep links,
  shield correctness and unlock must still be checked on a phone. No live-phone
  claim is made from the fixture.

Local evidence: `/tmp/docard-app-groups-{swift,node,build,release}.log`,
`/tmp/docard-app-groups-ui-smoke.cjs`, `/tmp/docard-app-groups-picker.png`.
The initial public-interface Swift and MCP regressions failed before implementation.

## Integration and hardware handoff

Merge this feature with the latest integration branch, preserving any concurrent
expiry/start-stall fixes and localization work. Build/test the combined result.
Upgrade the relay schema before installing the new phone build, then rebuild/load
the MCP server's tools/UI. Preserve the live SQLite database and pairing; don't
uninstall the phone app. No automatic activation is included in this worktree.

Do not downgrade to an old phone build with outstanding group-specific commands:
old decoders don't understand that field. Quiesce commands and re-pair/reset to a
single selection before rollback; don't claim backward group execution support.

Hardware checks: create two groups with visibly different apps; choose the second
in chat; confirm only that group is blocked; reopen review and verify its labels;
attempt an active edit (refused); change maximum (same apps/deadline); Emergency
Unlock; edit idle group and verify an old draft is refused; refresh/reconfirm;
repeat offline expiry/reboot QA separately. Existing intermittent start stalls and
offline-after-reboot expiry remain unresolved by this feature.

## Combined integration (2026-11-06)

Integrated `f0e06db` (idle app selection) and `8a477b0` (saved groups) over
translation integration `9ef5da0`. Preserved native registration diagnostics,
deadline-push recovery, translation, and physical QA records.

The phone-core merge required an explicit resolution: the idle selector edits
the `default` saved group and reads that group rather than the last active
selection. It preserves the authored alias. A real regression failed with
original/group-edited/editor-edited disagreement, then passed after resolution.
Group drafts now bind both original pairing and mode generation, rejecting
stale saves after another editor or reapproval changes the catalogue. The
native group route retains Screen Time authorization and the application limit.
Chinese strings were added for group review and chat controls; aliases remain
authored data. The localization DOM fixture gained actual option children,
and a new test verifies localized group controls preserve aliases and send no
command during display. The standalone maximum picker hides group controls.

Independent reviews: standards found no actionable issue; spec found the stale
group-draft gap above, corrected before activation. Physical native-picker/group
shield correctness still requires the hardware walkthrough.

Final parent runs:83 Swift and90 Node tests pass. Signed Debug iPhone app and
extensions, plus Release compile validation with signing disabled, report
`BUILD SUCCEEDED`. Logs `/tmp/docard-app-merge-{swift,node,device,release}.log`.
Failure evidence: `/tmp/docard-app-merge-red.log`,
`/tmp/docard-app-merge-localization-red.log`,
`/tmp/docard-app-group-stale-red.log`.

Backed up live SQLite to the private `.local/agent-focus.before-app-groups.sqlite`,
restarted the relay for the expanded metadata schema, and overlay-installed the
combined phone build. The phone successfully synced its default group alias with
pairing, maximum45, hours and timezone retained. No live session was started by
the integration. This chat's existing MCP process still returned the old picker
shape without appGroups/reviewURL; Codex must reload the MCP connection before
the new chat group chooser can be used. Do not confirm that older draft.
