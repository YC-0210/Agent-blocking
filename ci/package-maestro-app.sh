#!/bin/bash
set -euo pipefail
app="${1:?Usage: bash ci/package-maestro-app.sh APP OUTPUT_DIRECTORY}"
output="${2:?Supply an output directory}"
test -f "$app/Info.plist"
mkdir -p "$output"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/DoCard.app.zip"
uname -m > "$output/build-architecture.txt"
