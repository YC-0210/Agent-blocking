#!/bin/bash
set -euo pipefail

# Version and checksum are reviewed together, never resolved from "latest" in CI.
version=2.10.0
checksum=29b675e10cc12080e445e9bfb2e2b4e4dfb9c0f2e30d5884120d258b5e1cd991
destination="${1:?Usage: bash ci/install-maestro.sh INSTALL_DIRECTORY}"
mkdir -p "$destination"
curl --fail --location --retry 3 --max-time 300 \
  "https://github.com/mobile-dev-inc/Maestro/releases/download/cli-$version/maestro.zip" \
  --output "$destination/maestro.zip"
printf '%s  %s\n' "$checksum" "$destination/maestro.zip" | shasum -a 256 -c -
unzip -q -o "$destination/maestro.zip" -d "$destination"
chmod +x "$destination/maestro/bin/maestro"
"$destination/maestro/bin/maestro" --version
if [[ -n "${GITHUB_PATH:-}" ]]; then
  printf '%s\n' "$destination/maestro/bin" >> "$GITHUB_PATH"
fi
