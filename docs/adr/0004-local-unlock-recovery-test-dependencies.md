# 0004 — Exercise unlock and recovery with scoped dependencies

Status: implemented locally; awaiting review. 2026-11-01.

## Decision

Exercise the real `StrategyManager`, NFC/manual strategies, SwiftData session methods,
schedule-start handler, suppression registry, and signed shared-state encoding in local tests.
Supply replacements only for the clock, storage location/key, hardware reads, blocking
requests, emergency counter storage, and ancillary platform/network effects.

`SharedData.Runtime` is task-scoped, not a mutable global override. Each test supplies a
unique UserDefaults suite, an ephemeral signing key, a fixed Gregorian/Taipei calendar, and
a lock-protected clock. Its debug-log sink prevents test calls writing the shared log file.
No caller outside a scoped test needs to supply a runtime: existing App Group, Keychain,
date and calendar defaults remain the normal path.

The manager and strategies accept dependencies through initializers with existing live
defaults. The manager's synchronous `systemEffect` executor encloses ancillary operations
(Live Activities, widgets, notification cancellation, share prompts, timer scheduling, and
paired-device notifications). Tests omit those operations; session decisions, callbacks,
state transitions, persistence, and suppression writes remain real and execute normally.
Tests use profiles without reminder notifications. Blocking requests are recorded, not
applied through ManagedSettingsStore.

The scanner's read-result validation/delivery is shared by the real hardware callback and
the scripted read adapter. Tests of a wrong card therefore exercise production paired-ID
validation rather than teaching a fake scanner to reject it independently. Co-Focus
diversion retains its existing live default; these fixtures supply no active diversion.

## Alternatives rejected

- Writing suppression flags directly in every test: skips whether the unlock path writes
  the correct flag before recovery, which is the main failure we need to catch.
- A second, simplified recovery engine used only by tests: could pass while production
  recovery fails.
- Global storage overrides or real Keychain counters: risk shared-state collisions and
  changes to the developer's saved data.
- Full hardware-only tests for every event order: slow and unsuitable for deterministic
  exploration of the current-window stop rule.

## Constraints and limits

The app's separate strategy/schedule shared slots remain separate. Suppression storage
remains in SuppressionRegistry; scheduling-clock logic remains in SharedData (ADR-0001).
History remains in SwiftData and is not moved into shared defaults (ADR-0002).

No stored model fields, coding keys, schema versions, subscription policy, NFC payment
gates, Family Controls authorization, or CI files change. Section D of the proposed test
plan is excluded. Initializers still permit ordinary app callers to use the live defaults.

R2 drives the production schedule-start handler in the app test module, not an actual
DeviceActivity extension process. R3 recreates a coordinator, ModelContext and defaults
reader; it is not a device reboot or independent OS process. SwiftData stores are fresh and
in-memory; old-data migration is not covered. No claims about actual shields, radio reads,
background event delivery, timer ticks, notifications, Mac sync, or Live Activities follow
from passing these tests. The existing XCTest target still launches the normal host app.

The final run record is delivered separately with the local test results. Before shipping
changes to the live dependency paths, run the appropriate physical-device release checks.
