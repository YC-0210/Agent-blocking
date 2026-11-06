# Selected app icons: Apple API and policy findings

Researched 2026-11-06. Scope: native FamilyActivityPicker multiselection followed by automatic display of the actual selected app icons in a Codex web/MCP chat, without manual identity association. Primary Apple sources only. No account, signing, phone, or relay actions performed by this research agent.

## Decision

A blanket statement that automatic identification is impossible is outdated. Apple now documents a gated, non-tokenized data route on iOS/iPadOS 26.4+: `FamilyActivityData.installedApplications` returns applications containing **both a token and bundle identifier**. This supplies the missing automatic identity join. Development/testing is explicitly allowed in every region with an Apple-provided provisioning profile. Customer installations require both physical EU location and an EU Apple Account region. Therefore this is a plausible development experiment in Taiwan, but is not a supported Taiwan customer deployment route. It does not, by itself, provide downloadable icon bytes. [FamilyActivityData](https://developer.apple.com/documentation/familycontrols/familyactivitydata), [installedApplications](https://developer.apple.com/documentation/familycontrols/familyactivitydata/installedapplications), [approvedWithDataAccess](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess).

## What the standard picker and labels support

Apple describes `FamilyActivityPicker` as selecting apps, websites and categories without revealing those choices to the app. Its selection exposes opaque tokens. Apple expressly supports passing a selected token to `Label(applicationToken)` to display the corresponding app name and icon in native SwiftUI. `FamilyActivityIconView` is a type-erased `View`, not a documented `UIImage`, URL or image-data accessor. [Family Controls](https://developer.apple.com/documentation/familycontrols), [Displaying Activity Labels](https://developer.apple.com/documentation/familycontrols/displayingactivitylabels), [FamilyActivityIconView](https://developer.apple.com/documentation/familycontrols/familyactivityiconview).

Consequently, native multiselection and automatic native icon display already have an official path. An opaque token sent to a web client does not give that client an icon or identity resolver. This conclusion concerns the standard `.approved` route; the data-access route below changes identity access.

## Rendering a Label is an unverified experiment, not established icon export

Apple documents `ImageRenderer` for rasterizing SwiftUI content, but limits it to content SwiftUI draws directly. Contents composited through Core Animation, including many embedded UIKit/AppKit views and complex controls, are omitted or replaced with placeholders. Apple does not promise that `FamilyActivityIconView` is rasterizable. A generic `ImageRenderer` example is not evidence that Screen Time icons can be extracted, nor permission to export sensitive Screen Time content. [ImageRenderer](https://developer.apple.com/documentation/swiftui/imagerenderer).

No primary Apple source located in this research explicitly permits exporting token-backed label pixels as an off-device icon transport. Equally, the sources do not establish that every possible rendering experiment always fails. A controlled, local development test could establish rendering behavior on a particular OS, but would leave policy and production stability unresolved. User consent alone does not settle those separate constraints.

## Report and shield extensions are not supported extraction bridges

`DeviceActivityReport` gives a report extension data to render a view. Apple explicitly says its sandbox prevents network requests and moving sensitive content outside the extension's address space. Apple staff confirm that a report can display names, bundle identifiers and usage data for selected tokens; that is a display capability within the protected report. It is not an authorization to relay the information through App Groups, logs, callbacks or image extraction. [DeviceActivityReport](https://developer.apple.com/documentation/deviceactivity/deviceactivityreport), [Apple Frameworks Engineer explanation](https://developer.apple.com/forums/thread/722618).

`ShieldConfigurationDataSource` similarly receives names, bundle identifiers and domains to configure shields, and Apple documents the same network/out-of-address-space restrictions. It is invoked for shields rather than as an arbitrary picker enumeration service. `Application.bundleIdentifier` and `.localizedDisplayName` document their availability in this extension and `nil` outside it; newer `FamilyActivityData` explicitly supplies the data-access exception described below. [ShieldConfigurationDataSource](https://developer.apple.com/documentation/managedsettingsui/shieldconfigurationdatasource), [bundleIdentifier](https://developer.apple.com/documentation/managedsettings/application/bundleidentifier), [localizedDisplayName](https://developer.apple.com/documentation/managedsettings/application/localizeddisplayname).

`ShieldConfiguration.icon` is an image the developer supplies for the shield. Its `UIImage` type does not document a getter for the shielded application's installed icon. [ShieldConfiguration.icon](https://developer.apple.com/documentation/managedsettingsui/shieldconfiguration/icon).

## Data-access route: what is now expressly supported

The `Family Controls App and Website Usage` entitlement is `com.apple.developer.family-controls.app-and-website-usage`. Apple instructs developers to enable this capability on the Xcode target; explicit user authorization is required. `approvedWithDataAccess` permits actual installed-app bundle identifiers, visited domains, category names and the Device Activity export API. Only one app at a time can hold that status; granting another app data access resets the previous app to `.notDetermined`. [Entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.family-controls.app-and-website-usage), [approvedWithDataAccess](https://developer.apple.com/documentation/familycontrols/authorizationstatus/approvedwithdataaccess).

`DeviceActivityData.activityData(filteredBy:using:)` is expressly documented to export family activity data for another app or platform. It has the same authorization, entitlement and EU customer gates, with development/testing allowed in all regions. This is materially different from leaking a report extension's protected contents. [activityData(filteredBy:using:)](https://developer.apple.com/documentation/deviceactivity/deviceactivitydata/activitydata(filteredby:using:)).

For a development prototype, the supported conceptual join is: take the selected tokens, fetch installedApplications under data-access authorization, retain entries whose token is selected, then use their real bundle identifiers. No human-maintained token/name mapping is needed. Actual icon transport still needs an independently supported source or proven permitted rendering path. Public App Store artwork, if later investigated, would not necessarily match a device's alternate/tinted/current installed icon.

Apple's documentation metadata lists iOS and iPadOS 26.4 as the introduction versions for `FamilyActivityData` and `.approvedWithDataAccess` (verified from Apple's documentation JSON endpoints). Do not assume an older iPhone runtime supports these symbols.

## Entitlement availability and provisioning limits

For the ordinary Family Controls entitlement, the Account Holder requests distribution permission, including requests for Screen Time extensions. Apple reviews it and enables a managed capability; automatic signing can then update profiles. This is distinct from the new app-and-website-usage capability. [Requesting the Family Controls entitlement](https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement).

The new entitlement page says to enable the capability in Xcode. The authorization page says all-region development requires an Apple-provided provisioning profile. These primary sources do not establish a separate public approval form, guaranteed approval timeline, or this developer team's existing entitlement/profile eligibility. Do not equate standard Family Controls distribution approval with usable data access outside the EU. In a September 2026 forum thread about development succeeding but TestFlight returning `.approved`, Apple DTS specifically points to the EU customer gate. Only the staff reply, not the developer's reported setup, is used as authoritative evidence. [Apple DTS response](https://developer.apple.com/forums/thread/844623).

## DPLA and consent

Current DPLA section 3.3.3(P) restricts Family Controls to family supervision or individual focus/productivity/device management. Device/usage data is limited to those purposes, with sharing constrained to the provided family controls or the individual and their device; advertising, measurement and broker uses are excluded. General prior consent in 3.3.3(B) does not waive these specific terms. Section 3.3.3(A) also addresses conspicuous recording indicators. The agreement contains no general icon-export exception identified here. [Current Apple Developer Program License Agreement](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/).

Inference: relaying selected-app identities or rendered icons to an external MCP/chat service under the ordinary individual authorization should not be presented as permitted merely because the user requested it. Conversely, Apple's newer export API explicitly contemplates another app/platform, so an absolute assertion that Apple prohibits every Screen Time export would contradict that documentation. The relationship between the newer export capability, exact proposed service and agreement restrictions needs clarification before claiming production compliance.

## Remaining unknowns and next evidence

1. Whether this team's development profile actually carries the new entitlement, and whether the target phone has iOS 26.4 or later. This research agent did not inspect profiles or the device; parent-agent verified observations are recorded below.
2. Whether an all-region development build reaches `.approvedWithDataAccess` on the actual target device. Apple documents the possibility; this is not a promise that the current setup qualifies.
3. Whether `Label(token).labelStyle(.iconOnly)` produces real icon pixels with a supported renderer on that runtime. No image capture was performed; placeholder success must not be counted as icon success.
4. Whether Apple permits the exact selected-icon export/MCP use case, including a remote service, under the proposed authorization and entitlement. An Apple Developer Support/DTS clarification should distinguish ordinary tokens from the new explicit export capability.
5. No documented public bitmap/URL property for installed app icons was found in `Application`, `FamilyActivityData` or `FamilyActivityIconView`. This is a bounded search finding, not proof that no future or separately entitled Apple API exists.

Practical status: **Taiwan production web-chat icon flow: no supported end-to-end path established. Taiwan development research: a documented automatic identity route exists and merits an isolated gated prototype; raw icon delivery and applicable export permissions remain unresolved.**

## Workspace evidence supplied by the parent agent

These are reported local observations from the parent agent, separate from the Apple-source research above:

- Target iPhone: iOS 27.0.1 (24A446), Developer Mode enabled. The runtime is newer than the API introduction requirement.
- Installed toolchain: only Xcode 26.2 (17C52). Its FamilyControls Swift interface lacks `FamilyActivityData` and `.approvedWithDataAccess`; the present SDK cannot directly compile the new API route.
- Current embedded profile includes `com.apple.developer.family-controls = true`, but lacks `com.apple.developer.family-controls.app-and-website-usage`. Existing ordinary Family Controls authorization therefore does not establish eligibility for the new route.
- No account or toolchain changes have been made.

A local type-check probe against the installed iPhoneOS SDK confirms the toolchain
blocker: `FamilyActivityData` is not in scope and `AuthorizationStatus` has no
`approvedWithDataAccess` member. The probe did not run on the phone or access any
selected-app data. Local evidence: `/tmp/docard-selected-icons-sdk-probe.swift`
and `/tmp/docard-selected-icons-sdk-probe.log`.

The next useful proof is an isolated build with an SDK containing the APIs, a qualifying Apple-provided development profile, and explicit data authorization, followed by a local selected-token-to-bundle-ID join. This proves identity access only; it must not be reported as completed icon export. Any later catalog artwork pipeline needs independent permission/terms verification as well as image correctness; artwork availability alone is insufficient.
