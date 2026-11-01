#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

results_dir="${CI_RESULTS_DIR:-$repo_root/.build/ios-ci/results}"
build_dir="${CI_BUILD_DIR:-$repo_root/.build/ios-ci/build}"
runtime="${CI_SIMULATOR_RUNTIME:-com.apple.CoreSimulator.SimRuntime.iOS-26-2}"
expected_count="${EXPECTED_SCHEDULE_TEST_COUNT:-36}"
simulator_id=""

mkdir -p "$results_dir" "$build_dir"
# Repeated local runs must not reuse an earlier success marker or summary.
rm -f -- "$results_dir/ci-passed" "$results_dir/test-summary.json" \
  "$results_dir/tests.log" "$results_dir/release.log"

cleanup() {
  # Delete only the disposable simulator created by this invocation.
  if [[ -n "$simulator_id" ]]; then
    xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

{
  xcodebuild -version
  xcrun swift --version
  printf '\nRequested runtime: %s\n' "$runtime"
  xcrun simctl list runtimes
} | tee "$results_dir/environment.log"

xcrun simctl list runtimes --json > "$results_dir/runtimes.json"
python3 - "$results_dir/runtimes.json" "$runtime" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    runtimes = json.load(stream)["runtimes"]
if not any(item["identifier"] == sys.argv[2] and item.get("isAvailable") for item in runtimes):
    sys.exit(f"Required simulator runtime is unavailable: {sys.argv[2]}. See environment.log.")
PY

simulator_id="$(xcrun simctl create "DOCard CI ${GITHUB_RUN_ID:-local}-$$" \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro "$runtime")"
printf 'Disposable simulator: %s\n' "$simulator_id" | tee -a "$results_dir/environment.log"
xcrun simctl boot "$simulator_id"
xcrun simctl bootstatus "$simulator_id" -b

# Each invocation owns a new bundle; repeated local runs may keep the other logs.
result_bundle="$results_dir/schedule-tests-$(date +%Y%m%d-%H%M%S)-$$.xcresult"
common_args=(
  -project DoCard.xcodeproj
  -scheme DoCard
  -derivedDataPath "$build_dir/DerivedData"
  -clonedSourcePackagesDirPath "$build_dir/SourcePackages"
  -onlyUsePackageVersionsFromResolvedFile
  -jobs 2
  CODE_SIGNING_ALLOWED=NO
)

# pipefail preserves xcodebuild's failure when its output is also written by tee.
test_status=0
xcodebuild test "${common_args[@]}" \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator_id" \
  -destination-timeout 120 \
  -parallel-testing-enabled NO \
  -only-testing:DoCardTests/ScheduleTests \
  -resultBundlePath "$result_bundle" \
  2>&1 | tee "$results_dir/tests.log" || test_status=$?

# Keep a machine-readable summary on assertion failure as well as success.
if [[ -d "$result_bundle" ]]; then
  xcrun xcresulttool get test-results summary --path "$result_bundle" --compact \
    > "$results_dir/test-summary.json" || true
fi
if [[ "$test_status" -ne 0 ]]; then
  exit "$test_status"
fi

# A successful command with zero, missing, or skipped tests must not turn CI green.
python3 - "$results_dir/test-summary.json" "$expected_count" <<'PY'
import json
import sys

with open(sys.argv[1]) as stream:
    summary = json.load(stream)
expected = int(sys.argv[2])
if not (
    summary.get("result") == "Passed"
    and summary.get("totalTestCount") == expected
    and summary.get("passedTests") == expected
    and summary.get("failedTests") == 0
    and summary.get("skippedTests") == 0
):
    sys.exit(f"Expected {expected} passing schedule tests, none failed or skipped. Got: {summary}")
print(f"Verified {expected} schedule tests passed, with none failed or skipped.")
PY

xcodebuild build "${common_args[@]}" \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  2>&1 | tee "$results_dir/release.log"

touch "$results_dir/ci-passed"
