# Preserve selected icons between sessions

Fixed 2026-11-06. User reported that Instagram and Brawl Stars initially appeared,
but a new session reverted to the generic “2 selected apps” badge.

The live snapshot retained app counts but lacked `selectedAppIDs`. Reproduction
through initialized MCP + HTTP showed the cause: background and expiry snapshots
omit identities and replace the previous relay snapshot, deleting the main app's
authorized metadata. The initial regression failed with an empty `selectedApps`
array after a counts-only update.

## Protocol

- The existing selected-only native cache now has a random UUID
  `selectionIdentity`, bound to the exact local application tokens by the existing
  local fingerprint. Neither tokens nor their fingerprints are exported. The UUID
  is not derived from the selected apps. Legacy cache entries migrate under
  explicit data-access approval without another installed-app enumeration.
- The persisted phone status uses the same effective selection for counts, cached
  bundle IDs and the marker. Cache mismatch returns no marker or identities.
- Delivery distinguishes approval states: true publishes selected IDs and marker;
  false explicitly clears IDs (`[]`) and omits the marker; unknown publishes only
  the marker. Extension/expiry delivery uses unknown and does not query Apple's
  authorization service or export bundle IDs.
- The relay preserves prior IDs only for an omitted ID field with an identical
  UUID marker and application count. Counts alone never justify preservation.
  Changed/missing markers, inconsistent counts and explicit clearing drop icons.
- The relay reads the current prior snapshot after receiving the complete body,
  preventing an older, slow upload from restoring metadata cleared meanwhile.
- A cold `.notDetermined` native status is unknown rather than explicit denial;
  it does not delete the verified cache before authorization initializes.

This retains display metadata already authorized for the same selection. It does
not manufacture fresh data-access approval, restore revoked IDs, fetch an app
inventory in an extension, or change any blocking command, limit or deadline.
Previously stored IDs can only be cleared remotely once the phone communicates
the revocation or loses the matching selection marker.

## Validation

- RED/GREEN reproduction at the existing MCP + HTTP seam.
- 89 Swift tests and 112 Node tests pass (201 total).
- Coverage includes new-picker persistence across background start/expiry,
  same-count selection changes, unknown permission, explicit revocation, missing
  and malformed markers, inconsistent counts and a stalled HTTP-body race.
- Signed English Debug experiment build and SDK/profile preflight pass; unsigned
  Release build passes. Swift-format and diff whitespace checks pass.
- Spec and standards reviews found no remaining actionable issues.
- Relay backup retained before activation; updated relay restarted, signed build
  installed over the paired iPhone 13, and main app relaunched in English.
- Fresh live snapshot confirmed both selected bundle IDs and the new random
  selection marker after cache migration. No active session or limits changed.

Physical follow-up: after the main app publishes the migrated cache, start a short
user-confirmed session, let it expire with DO Card closed, and open another picker.
Its icons should remain. No session is automatically started by this fix or its
diagnostics. Live start → expiry → next-picker UI still requires user verification.

Local evidence: `/tmp/docard-persistent-icons-{red,green,swift,node,race,build,release}.log`.
