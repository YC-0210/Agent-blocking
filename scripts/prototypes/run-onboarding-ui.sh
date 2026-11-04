#!/bin/bash
# Throwaway simulator UI review, no PostHog integration.
set -eu
cd "$(dirname "$0")/../.."
onboarding_device="${1:-}"
if [ -z "$onboarding_device" ]; then
  onboarding_device=$(xcrun simctl create 'DO Card Onboarding UI Review' \
    com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro \
    com.apple.CoreSimulator.SimRuntime.iOS-26-2)
  xcrun simctl boot "$onboarding_device"
fi
onboarding_build="${TMPDIR:-/tmp}/docard-onboarding-ui-build"
xcodebuild -project DoCard.xcodeproj -scheme DoCard -configuration Debug \
  -sdk iphonesimulator -destination "platform=iOS Simulator,id=$onboarding_device" \
  -derivedDataPath "$onboarding_build" CODE_SIGNING_ALLOWED=NO build
xcrun simctl install "$onboarding_device" \
  "$onboarding_build/Build/Products/Debug-iphonesimulator/DoCard.app"
xcrun simctl launch --terminate-running-process "$onboarding_device" online.do.card.app \
  --onboarding-ui-prototype -AppleLanguages '(zh-Hant)' -AppleLocale zh_TW
open -a Simulator --args -CurrentDeviceUDID "$onboarding_device"
