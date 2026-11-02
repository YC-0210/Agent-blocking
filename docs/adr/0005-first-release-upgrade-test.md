# 0005 — Read a source-generated first-release store through the production opener

Status: implemented, awaiting review. 2026-11-02.

## Decision

Create artificial saved data using an isolated copy of the preserved `DO-founder` 1.30.1
source. Its March 17 archive records an App Store upload with no errors; the `DO.1` archive
has the identical binary and its debug symbols point to the original `DO.1` source folder.
Four database-related source files match in both folders and Git revision `346118b`.
Archived getters represent all stored profile/session properties checked. This supports
the historical data-model baseline; it is not proof of every archived source byte.

The writer compiles the actual old types in their original `DoCard` module. It opens an
unversioned two-model on-disk store, without current `AppSchemaV1` definitions or an explicit
migration plan. It saves, fetches and verifies two profiles, their single schedules, three
completed sessions and one break. The generated store reports version 1.0.0 and exactly the
two old entities. The complete package is captured after the writer process stops, including
WAL/SHM companions. Provenance records source and data hashes, runtime and toolchain.

`AppModelStore.open(configuration:)` contains the existing production ModelContainer open
operation: current schema V5 and the unchanged AppMigrationPlan. The app calls it with its
existing configuration, including on its existing fallback retry. Upgrade tests call it
with a disposable copied store. Opening errors propagate to the test; it cannot silently
accept the app's empty-database reset as a successful migration. No recovery policy changes.

The reader runs the production startup single-schedule conversion, explicitly saves, and
compares exact old fields and relationships through SwiftData. New schedule IDs must be
valid/distinct and stable on reopen. Same-day next-day flags default to false. Old sessions
did not save trigger source/end reason: manual/nil are migration defaults, not recovered
historical facts. New NFC/unlock event and gallery tables must be queryable and empty.

The ordinary XCTest method always starts from a fresh fixture. A runner invokes it
again with an explicit `reopen` phase, verifies a different process ID and stable schedule
IDs, and records separate result bundles. The runner restarts only its dedicated simulator
between phases, preserving data, to avoid an observed Busy/preflight launch failure.

GitHub Actions extends the existing Mac job. One Debug `build-for-testing` output supplies
the schedule/unlock regression run and both upgrade processes through `test-without-building`.
The job owns a disposable simulator and keeps its data until both phases finish. The result
gate requires the exact method in both Xcode trees, complete passing summaries, successful
process execution and distinct process IDs before Release compilation. Logs and phase results
remain available on failure. Regeneration and deliberate-error proof remain manual initially.
This avoids a second Debug build while adding simulator restart overhead to each CI run.

The deliberate-error proof modifies Work's name in a disposable copied built-app fixture.
It requires the intended field assertion failure, rather than accepting an environment
failure, and then reruns the intact fixture. Original fixture hashes remain unchanged.

## Alternatives rejected

- Generate old data from today's V1 reconstruction: could allow the same historical-model
  mistake in both input creation and migration to escape detection.
- Use the March 28 archive merely because its label says 1.30.1: its upload was rejected
  and its source includes later subscription/report data models.
- Use an in-memory store: skips the persisted historical schema and its migration.
- Accept successful app launch or record counts alone: can miss an empty-store fallback,
  changed settings, broken relationships or altered history.
- Add stored fields or adjust migration stages for test access: unnecessary for this seam.
- Treat a new ModelContext as a new app process: the local runner explicitly reopens in
  another process instead.

## Scope and limits

The only production edits are the new opener and two calls in `DoCardApp.swift`. Stored model
fields, schema versions, migration stages, subscription policy, Family Controls, separate
App Group slots remain unchanged. Existing schedule/unlock test work stays
intact. Historical source folders are checked for unchanged file hashes.

The fixture uses artificial values and empty FamilyActivitySelection. It was generated on
the recorded current simulator runtime using old code, not exported from an original user's
older-OS device. Real token preservation, App Store overlay installation, UI rendering,
actual shields, NFC and other historical device/runtime variants require later checks.
This test does not establish the cause of every previous update crash. No physical-device
check or release is claimed by passing local tests.

See `scripts/upgrade1301/README.md` for regeneration and local execution, and fixture
`provenance.json` for the exact source/data identity and runtime.
