# Remote minimum app version

The iOS app reads `https://do-card.online/app-config.json` at launch and whenever it
returns to the foreground. The existing live endpoint currently serves minimum
`1.40.0`; adding this client does not change that remote setting. The file beside
this document is a deployment example, not a bundled policy or the live setting.

The website deployment owns `/app-config.json`. Publish JSON over HTTPS with
`Cache-Control: no-cache` (or `max-age=0, must-revalidate`). Never put this setting
behind authentication or point the client at a private GitHub raw URL.

```json
{
  "minimumVersion": "2.1.1",
  "updateMessage": "請更新至最新版以繼續使用 DO Card。",
  "enabled": true
}
```

Versions contain one to three numeric components and are compared numerically:
`2.10.0` is newer than `2.9.0`, and `2.1` equals `2.1.0`. Only the marketing version
(`CFBundleShortVersionString`) is compared; build numbers do not affect the policy.
Missing `enabled` means enabled, for compatibility with the existing endpoint.
Set `enabled` to false, or lower `minimumVersion`, to roll back an update requirement.

A required update replaces normal app navigation with an App Store button and a
Retry button. It cannot be dismissed. To preserve the app's recovery paths, the
gate waits until onboarding/Family Controls authorization and any active focus
session have finished. Active manual and scheduled sessions keep their existing
NFC stop, timer, Settings and Emergency Unlock UI. No purchase is required to
access recovery. Background schedules and Shortcuts keep existing behavior; this
is an in-app navigation gate, not a backend API or extension kill switch.

The policy is memory-only. Each check bypasses URL caches. Offline, timeout,
non-200, oversized or malformed responses permit normal use, including after a
previously successful check. A later successful check can require an update again.
Checks are coalesced while one request is in flight. Nothing writes to SwiftData,
App Group subscription/session state or analytics. The destination is the verified
DO app listing `https://apps.apple.com/app/id6758519666`; remote JSON cannot redirect
users to an arbitrary website.

## Release sequence

1. Ship a release containing this client while leaving the remote minimum low.
2. Confirm the replacement release is downloadable in every supported storefront
   and supports the iOS versions of users who will be gated.
3. Change the website's remote minimum to that release's marketing version.
4. Verify an older supported build shows the gate, the required build opens
   normally, and rollback works. An old build without this client cannot be gated.

The existing CI portfolio includes `AppUpdateTests` and `AppUpdateNetworkTests`.
Run `bash ci/run-test-pipeline.sh --core-only` for deterministic, StoreKit, upgrade
and Release checks. The optional `--maestro` adds existing locking journeys.
Tests use controlled HTTP responses; they never raise the production minimum.
Before App Store submission, run Tier 1 physical-device checks plus: real App Store
navigation, offline launch, foreground recheck, remote rollback, card-ending an
active manual/scheduled session and Emergency Unlock with an update pending.
Simulator results do not prove physical NFC or OS shields.
