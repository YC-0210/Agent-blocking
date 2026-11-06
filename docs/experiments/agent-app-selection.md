# Edit agent app selection while idle

Branch: `codex/agent-app-selection`, based on integration `9ef5da0`.

The paired idle screen exposes “Choose apps and websites.” It loads the private
saved selection into Apple's FamilyActivityPicker. Cancel discards the draft;
Save requires Screen Time approval, a nonempty selection and the existing app
limit. English and Traditional Chinese copy are included.

The presentation hides the editor action while session status is unknown,
applying, active or awaiting expiry reconciliation. Phone storage independently
checks idle state, pairing and the mode captured when the editor opened under
the same process lock used by command execution. A concurrent start prevents
saving; an approval/maximum change invalidates the draft. Saving preserves the
latest time limits, hours, timezone, pairing, emergency revision and replay
history, and rotates the mode to invalidate queued starts for the old selection.
The app then syncs the new mode to the relay. No selection tokens leave the phone.

## Verification

- Added a public phone-interface regression before implementation; it initially
  failed to compile because selection editing was absent.
- `swift test`:77 tests pass, including persistence across reopen, unchanged
  limits, no shield application on save, stale draft/wrong pairing rejection,
  stale queued start rejection, the next start using the revised selection, and
  edit rejection after a session starts.
- Debug iOS app and extensions: `BUILD SUCCEEDED`, signing disabled for this
  worktree's compile check. Log: `/tmp/docard-selection-build.log`.
- `git diff --check`: clean.

No merge, phone installation, relay/MCP restart or integration-worktree change
was performed. Native picker interaction and physical shields remain unverified.

## Phone walkthrough after integration

1. Idle: open the selector; verify the saved apps are selected. Edit and Cancel;
   reopen and confirm the original selection remains.
2. Change the selection and Save. Relaunch and verify it persists. Confirm maximum,
   hours and pairing remain unchanged; the next fresh agent picker starts a
   session using only the revised selection.
3. Start a session while the editor is open. Save must fail without changing its
   apps or deadline. During an active session the idle edit action is hidden.
4. Verify empty selection cannot save, Traditional Chinese labels fit, Emergency
   Unlock remains usable, and a picker opened before the change is rejected.
