# Local first-release upgrade check

The fixture was generated using the preserved 1.30.1 source. It is artificial data: two profiles,
two legacy single schedules, three completed sessions, and one five-minute break. There are no
old gallery or NFC/Emergency Unlock event tables. The fixture has no real app-selection tokens.

The normal `Upgrade1301Tests` XCTest method copies a fresh fixture, opens it through
`AppModelStore.open`, runs the production startup schedule conversion, explicitly saves, and
checks exact values and relationships. Normal standalone XCTest runs do not depend on an earlier run.

The local runner executes that same method twice with an explicit phase: initial migration,
then reopening the saved result in a different process. It verifies different process IDs and
stable migrated schedule IDs. It restarts the dedicated simulator between phases to avoid the
observed Busy/preflight launch error; it never erases it. Simulator startup is additional overhead.

## Run against the current build

Run from the app repository. Use a dedicated simulator UUID. Choose a NEW results directory:

```sh
python3 scripts/upgrade1301/run_local.py \
  --simulator C4E475AF-6F60-4D75-9739-17F2FD08FF67 \
  --derived-data /tmp/docard-upgrade1301/DerivedData \
  --results /tmp/docard-upgrade1301/results-1 \
  --prove-failure
```

`--source-packages PATH` can reuse a local Swift package checkout cache. `--skip-build` is only
for an already matching `build-for-testing` output. The script otherwise builds current source.
It checks that each positive phase actually executed one test with zero failures/skips.

`--prove-failure` changes only Work's name in a disposable copied built-app database. The original
fixture and expected values are unchanged. The script requires an assertion failure mentioning
`Altered Work`, so a launch/build failure cannot count as proof. It then runs the unchanged
fixture again. Logs, Xcode result bundles, summaries, process IDs and durations are retained.

## Regenerate with old source

The archived iPhone binary cannot execute in an iOS simulator. The generator copies the verified
historical source into a temporary work directory, checks the four pinned database-related source
hashes, and adds the data writer only to that copy. It never edits the old models or substitutes
current `AppSchemaV1` types. It retains the old model module and unversioned two-model configuration.

```sh
python3 scripts/upgrade1301/generate_fixture.py \
  --old-source '/Users/chen/Desktop/大學/project/DO/Code/Other version /DO-founder' \
  --work-dir /tmp/docard-upgrade1301/generation \
  --output-bundle /tmp/docard-upgrade1301/new/Upgrade1301.bundle
```

This requires Xcode 26.2 and the installed iOS 26.3 simulator runtime used in verification.
`--runtime` can specify another installed runtime, which creates a distinct coverage case.
The generator creates and removes its OWN temporary simulator. It preserves its work copy, logs
and result bundle, validates old data and store metadata, stops the writer before copying the
complete store package, and writes provenance. Existing output bundles are never overwritten.
Review regenerated provenance and results before replacing `DoCardTests/Fixtures/Upgrade1301.bundle`.
The fixture contains the main database plus its WAL/SHM files; copying just one file is insufficient.

## Meaning and limits

A pass proves compatibility and preservation for this source-generated database on the recorded
runtime. It does not certify every real first-release store, actual App Store installation,
UI rendering, real app-selection tokens, shields or NFC. The historical source/archive match is
supported by upload records, matching copies and archived model symbols, but not a source checksum
for every archived app file. Old field values must survive; newly generated schedule IDs need
stability after conversion, and new history fields are defaults, not recovered historical facts.

## GitHub Actions

`ci/run-ios-ci.sh` reuses its one Debug build for the regression tests and this runner with
`--skip-build`. It creates its own disposable simulator, retains the migrated data between
phases, validates both phases before Release, and uploads their separate evidence even on failure.
Normal CI uses the committed fixture; regeneration and `--prove-failure` remain manual.
See `docs/ios-ci.md` for counts, result gates and runtime coverage.

Stored-model fields, schema versions, migration stages and reset policy are unchanged.
