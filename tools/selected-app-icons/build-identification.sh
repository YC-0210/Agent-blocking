#!/bin/bash
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "Usage: bash tools/selected-app-icons/build-identification.sh [IPHONE_HARDWARE_UDID]" >&2
  exit 2
fi
probe_destination='generic/platform=iOS'
if [ "$#" -eq 1 ]; then probe_destination="id=$1"; fi

probe_root=$(cd "$(dirname "$0")/../.." && pwd)
probe_entitlements_dir=$(mktemp -d /tmp/docard-data-access-entitlements.XXXXXX)
trap 'rm -rf "$probe_entitlements_dir"' EXIT

python3 - "$probe_root/DoCard/DoCard.entitlements" "$probe_entitlements_dir/Probe.entitlements" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as source:
    entitlements = plistlib.load(source)
entitlements['com.apple.developer.family-controls.app-and-website-usage'] = True
with open(sys.argv[2], 'wb') as destination:
    plistlib.dump(entitlements, destination)
PY

cd "$probe_root"
xcodebuild -project DoCard.xcodeproj -scheme DoCard -configuration Debug \
  -destination "$probe_destination" -derivedDataPath /tmp/DOCardIdentificationPhone \
  -allowProvisioningUpdates \
  "DO_CARD_AGENT_APP_ENTITLEMENTS=$probe_entitlements_dir/Probe.entitlements" \
  'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) DEBUG DO_CARD_APP_DATA_ACCESS_PROBE' \
  build

python3 tools/selected-app-icons/preflight.py \
  --profile /tmp/DOCardIdentificationPhone/Build/Products/Debug-iphoneos/DoCard.app/embedded.mobileprovision
