#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
mode="${1:---core-only}"
if [[ "$mode" != --core-only && "$mode" != --maestro ]]; then
  printf 'Usage: bash ci/run-test-pipeline.sh [--core-only|--maestro]\n' >&2
  exit 2
fi
export PYTHONDONTWRITEBYTECODE=1
export CI_RESULTS_DIR="${CI_RESULTS_DIR:-$repo_root/.build/test-pipeline/results-$(date +%Y%m%d-%H%M%S)-$$}"
export CI_BUILD_DIR="${CI_BUILD_DIR:-$repo_root/.build/ios-ci/build}"
# A prior report or marker must never satisfy a new whole-pipeline invocation.
if [[ -e "$CI_RESULTS_DIR" ]]; then
  printf 'Use a new results directory: %s\n' "$CI_RESULTS_DIR" >&2
  exit 1
fi
mkdir -p "$CI_RESULTS_DIR"
summary() {
  python3 ci/ios-ci-summary.py "$CI_RESULTS_DIR" > "$CI_RESULTS_DIR/pipeline-summary.md" || true
  if [[ "$mode" == --maestro ]]; then
    if [[ -f "$CI_RESULTS_DIR/maestro/maestro-passed" ]]; then
      printf '\nMaestro: all four locking journeys passed.\n' >> "$CI_RESULTS_DIR/pipeline-summary.md"
    else
      printf '\nMaestro: not completed successfully.\n' >> "$CI_RESULTS_DIR/pipeline-summary.md"
    fi
  fi
}
trap summary EXIT
python3 ci/test-ios-ci.py
if [[ "$mode" == --maestro ]]; then
  python3 ci/test-maestro-results.py
fi
bash ci/run-ios-ci.sh
if [[ "$mode" == --maestro ]]; then
  artifact="$CI_BUILD_DIR/maestro-app"
  bash ci/package-maestro-app.sh "$CI_BUILD_DIR/DerivedData/Build/Products/Debug-iphonesimulator/DoCard.app" "$artifact"
  test "$(cat "$artifact/build-architecture.txt")" = "$(uname -m)"
  # Match GitHub's artifact transport: install the archived/unpacked build.
  ditto -x -k "$artifact/DoCard.app.zip" "$artifact"
  python3 ci/run-maestro.py --app "$artifact/DoCard.app" --results "$CI_RESULTS_DIR/maestro"
fi
printf '%s\n' "$mode" > "$CI_RESULTS_DIR/pipeline-passed"
printf '\nRequested pipeline stages passed. Results: %s\n' "$CI_RESULTS_DIR"
