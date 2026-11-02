#!/bin/bash
set -euo pipefail

kind="${DOCARD_RUNNER_KIND:?Set DOCARD_RUNNER_KIND to self-hosted or github-hosted}"
case "$kind" in
  self-hosted)
    [[ "$(id -un)" == docardci ]] || {
      printf 'Self-hosted CI must run in the dedicated docardci account.\n' >&2
      exit 1
    }
    # Use the selected local Xcode, not a GitHub image-specific bundle name.
    export DEVELOPER_DIR="${DOCARD_CI_XCODE_PATH:-$(xcode-select -p)}"
    ;;
  github-hosted)
    export DEVELOPER_DIR=/Applications/Xcode_26.2.app/Contents/Developer
    ;;
  *) printf 'Unsupported runner kind: %s\n' "$kind" >&2; exit 1 ;;
esac

[[ "$(uname -s)" == Darwin && "$(uname -m)" == arm64 ]] || {
  printf 'This pipeline requires a macOS ARM64 runner.\n' >&2; exit 1;
}
[[ -d "$DEVELOPER_DIR" && "$DEVELOPER_DIR" != *$'\n'* ]] || {
  printf 'Select an installed Xcode 26.2 with xcode-select or DOCARD_CI_XCODE_PATH.\n' >&2
  exit 1
}
version="$(xcodebuild -version)"
printf '%s\n' "$version"
[[ "${version%%$'\n'*}" == 'Xcode 26.2' ]] || {
  printf 'Expected Xcode 26.2; update the toolchain deliberately.\n' >&2; exit 1;
}
xcodebuild -checkFirstLaunchStatus
runtime="${CI_SIMULATOR_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-2}"
xcrun simctl list runtimes --json | python3 -c '
import json,sys
runtimes=json.load(sys.stdin)["runtimes"]
if not any(r["identifier"] == sys.argv[1] and r.get("isAvailable") for r in runtimes):
    sys.exit("Required simulator runtime is unavailable: " + sys.argv[1])
print("Available runtime: " + sys.argv[1])
' "$runtime"
printf 'Runner kind: %s; account: %s; architecture: %s\n' "$kind" "$(id -un)" "$(uname -m)"
df -h "${RUNNER_TEMP:-/tmp}"
if [[ -n "${GITHUB_ENV:-}" ]]; then
  printf 'DEVELOPER_DIR=%s\n' "$DEVELOPER_DIR" >> "$GITHUB_ENV"
  if [[ -n "${CI_JOB_STAGE:-}" ]]; then
    case "$CI_JOB_STAGE" in core|maestro) ;; *) exit 1 ;; esac
    job_root="${RUNNER_TEMP:?}/docard-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}"
    {
      printf 'CI_RESULTS_DIR=%s/%s-results\n' "$job_root" "$CI_JOB_STAGE"
      printf 'CI_BUILD_DIR=%s/core-build\n' "$job_root"
      printf 'MAESTRO_APP_DIR=%s/app\n' "$job_root"
    } >> "$GITHUB_ENV"
  fi
fi
