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

After installing/selecting the newer Xcode, accepting its license and completing
its first-launch setup, build the opt-in identification experiment with:

```sh
bash tools/selected-app-icons/build-identification.sh IPHONE_HARDWARE_UDID
```

This generates a temporary copy of the main app's entitlements with the usage
capability added. It enables the compile gate for the build and asks automatic
signing to update the development profile. Extensions retain their own existing
entitlements. Normal Debug and Release builds retain their original entitlements.
If the team cannot provision this capability, signing must fail; do not remove the
entitlement or force signing to make the test appear to pass. The script finishes
by checking the embedded profile and SDK. It does not install or launch the app.
Omit the hardware UDID to build for a generic physical iOS device while waiting
for the paired phone to be unlocked.

```sh
python3 tools/selected-app-icons/preflight.py \
  --profile /path/to/DoCard.app/embedded.mobileprovision
```

The script compiles the actual API usage against the selected SDK and checks
that the supplied development profile contains both Family Controls capabilities.
It does not change the account or provisioning. It does not check expiration,
device membership or every signing constraint; Xcode signing must still succeed.

The original Xcode 26.2 SDK failed this check. Use a newer Xcode with
these APIs, enable **Family Controls App And Website Usage** for a qualifying
development target and regenerate its profile. Only then consider adding
`DO_CARD_APP_DATA_ACCESS_PROBE` to that Debug target's Swift compilation conditions.
The corresponding entitlement is
`com.apple.developer.family-controls.app-and-website-usage`.

When compiled with that flag, the probe has an explicit **Allow local app
identification** button. It checks that the phone is idle, then opens Apple's
individual authorization prompt. Nothing requests additional access automatically.
The shared authorization checks recognize `.approvedWithDataAccess` in this gated
build so the extra permission is not mistaken for revocation. The normal build
continues to use ordinary approval. The identification code requires the new
status and matches only selected application tokens. Unselected applications are
discarded without logging or persistence.

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

The subsequent physical screenshot showed real native Instagram and Brawl Stars
icons on the left and generic prohibition placeholders on the right. Therefore
the rendering route **failed on this device**. Returning two images was not a
successful icon capture. Automatic identification remains a separate experiment.

Authorization preparation: the ordinary signed Debug build succeeds and all 85
existing core tests pass. These checks do not validate the gated new SDK symbols
or the data-access permission transition; those require the pending Xcode update
and a qualifying development profile. The prepared build has not been installed
over the local rendering experiment.

After the Xcode update: Xcode 27.2 (27B52) successfully type-checks the API and
builds the full Debug app with `DO_CARD_APP_DATA_ACCESS_PROBE` and signing
disabled. All 85 existing core tests also pass under the updated toolchain.
The first signed attempt failed because Xcode reported **No Accounts** and the
cached profile lacked the usage capability.

After account sign-in and phone unlock, the signed Debug identification build
succeeded. SDK and embedded-profile preflight both passed. Independent checks
confirmed the signed app and embedded profile include ordinary Family Controls,
App And Website Usage and development debugging entitlements. The profile is
unexpired and includes the target iPhone. Installed over the existing experiment
and successfully launched with `--selected-app-icon-probe`.

Device data-access authorization and selected-token identity matches still await
the user tapping **Allow local app identification** and approving the Apple prompt.
This installation does not establish successful identity matching or chat icons.
