# Selected app icon development probe

This is an incomplete **local experiment**, not chat icon delivery. It tests two
independent questions without changing the selected apps or sending data to MCP:

1. Can `ImageRenderer` capture a selected token's native icon? Compare the native
   icon and rendered image side by side. A returned `UIImage`, blank image or
   generic placeholder is **not** a successful icon capture.
2. With the newer SDK, development capability and approved data access, can the
   selected tokens be joined to installed bundle identifiers automatically?
   Identifiers alone do not supply icon bytes.

## Run the rendering experiment

Build the normal Debug DoCard scheme. Install over the existing experiment
without uninstalling it. Launch with the argument `--selected-app-icon-probe`:

```sh
xcrun devicectl device process launch --device DEVICE_ID --terminate-existing \
  online.do.card.app --selected-app-icon-probe
```

The debug-only sheet reads the saved selection through `editableSelection()`.
Finish setup and end any active session first. Tap **Try rendering selected
icons** and inspect the right image against the native left icon. No captured
images or identifiers are persisted, logged, shared or uploaded. Close the sheet
with Done. Release builds do not include this view or launch behavior.

## Automatic identification prerequisites

```sh
python3 tools/selected-app-icons/preflight.py \
  --profile /path/to/DoCard.app/embedded.mobileprovision
```

The script compiles the actual API usage against the selected SDK and checks
that the supplied development profile contains both Family Controls capabilities.
It does not change the account or provisioning. It does not check expiration,
device membership or every signing constraint; Xcode signing must still succeed.

The current Xcode 26.2 SDK fails this check. Install/select a newer Xcode with
these APIs, enable **Family Controls App And Website Usage** for a qualifying
development target and regenerate its profile. Only then consider adding
`DO_CARD_APP_DATA_ACCESS_PROBE` to that Debug target's Swift compilation conditions.
The corresponding entitlement is
`com.apple.developer.family-controls.app-and-website-usage`.

The probe intentionally **does not request or upgrade authorization**. The main
experiment's ordinary authorization flow is unchanged. Before requesting data
access, adapt all authorization consumers to recognize the new approved status;
do not enable the capability casually on the live phone build. The gated code
requires `.approvedWithDataAccess` and matches only selected application tokens.
Unselected applications are discarded without logging or persistence.

## Completion criteria and remaining work

- Physically inspect rendered results; simulator placeholders cannot prove capture.
- Verify the SDK/profile-gated identification code on the physical development build.
- Establish an allowed, reliable icon source/export path before adding any relay
  payload or chat markup. No report/shield sandbox extraction or private API is used.
- Categories and websites must remain distinct from individually selected apps.
- Production Taiwan availability is not established: Apple's data access route
  restricts customer installation to the EU. Development testing is documented
  worldwide with a qualifying profile.

See [Apple research](../../docs/research/selected-app-icons-apple.md) for sources
and unresolved policy questions. No claim of end-to-end icon delivery is made.

## Local validation, 2026-11-06

- Signed Debug build succeeded with the existing SDK and ordinary profile.
- Release build with signing disabled succeeded; the probe is excluded by `DEBUG`.
- Installed over the existing paired iPhone 13 experiment and successfully launched
  with `--selected-app-icon-probe`.
- `swift-format lint --strict` passed for both changed Swift files.
- Preflight failed both newer API compilation and usage entitlement checks, as
  expected. The gated identity code has **not** been compiled with a supporting
  SDK or run on the phone.
- Native image correctness awaits visual inspection on the physical phone.
  No automated test can substitute for this evidence; no new internal testing seam
  was introduced for the diagnostic screen.
