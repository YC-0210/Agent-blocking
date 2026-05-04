# Timer Mode Reliability Audit

## Summary

This audit traced timer mode end to end across:

- `NFCTimerBlockingStrategy`
- `ShortcutTimerBlockingStrategy`
- `BlockedProfileSession` and `SharedData`
- `AppBlockerUtil`
- `DeviceActivityCenterUtil.startStrategyTimerActivity`
- `StrategyTimerActivity`
- `ScheduleTimerActivity`
- `StrategyManager.loadActiveSession`

The timer flow has one strong property today: a timer session immediately writes both SwiftData state and `SharedData.activeSharedSession`, so the DeviceActivity extension can usually find the active session later.

The main reliability risks are not in timer startup itself. They are in:

- timer/schedule interaction through the single global `ManagedSettingsStore`
- silent failure after the session has already been created
- expiry math near midnight
- recovery logic that re-derives duration from mutable profile settings instead of immutable session-time data

## State Transition Table

| Checkpoint | `StrategyManager.activeSession` | SwiftData session | `SharedData.activeSharedSession` | DeviceActivity registrations | Actual restrictions |
|---|---|---|---|---|---|
| Before timer start | `nil` | none active | `nil` | none or unrelated schedules | off |
| After `activateRestrictions` | still `nil` until callback | none yet | none yet | none yet | on immediately via `ManagedSettingsStore` |
| After `BlockedProfileSession.createSession()` | set in `onSessionCreation(.started)` | active timer session created | same session snapshot written immediately | none yet | still on |
| After `startStrategyTimerActivity()` succeeds | active timer session | active | same timer snapshot | `StrategyTimerActivity:<profileId>` | on |
| After app relaunch before expiry | restored from most recent active session | still active | depends on extension/app sync | strategy timer may still be registered | re-applied from app |
| After app relaunch after expiry | cleared if `loadActiveSession()` decides planned end passed | session marked ended | flushed by `endSession()` | strategy timer removed | off |
| After manual unlock | cleared in `.ended` callback | session ended with `card_tap` | flushed by `endSession()` | all strategy timers removed | off |
| After overlapping schedule start | may still point at old timer session until sync/load | can diverge from real blocker | may be replaced by schedule session | timer + schedule may both exist | whichever path wrote `ManagedSettingsStore` last |
| After schedule end during overlap | may still look active in UI | may end wrong session or remain stale | ended only if shared session still matches schedule profile | timer registration may remain | can turn off even if timer should still be running |

## Findings

### High Severity

#### 1. Schedule on a different profile can hijack a running timer and leave the UI in a false-active state

- Timer start creates a SwiftData session and writes it into `SharedData.activeSharedSession` via `BlockedProfileSession.createSession()` in [`DoCard/Models/BlockedProfileSessions.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Models/BlockedProfileSessions.swift:118).
- If a schedule later starts on another profile, `ScheduleTimerActivity.start()` ends the existing shared session and replaces it with a new scheduled session for the schedule profile in [`DoCard/Models/Timers/ScheduleTimerActivity.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Models/Timers/ScheduleTimerActivity.swift:91).
- `StrategyManager.activeSession` is not reconciled at that moment; sync only happens later when `getActiveSession()` is called in [`DoCard/Utils/StrategyManager.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/StrategyManager.swift:880).
- Because `ManagedSettingsStore` is global, the schedule then overwrites the timer’s restrictions.

Impact:

- Timer profile A can still look active in the app while profile B is the actual blocker.
- When the schedule ends, it can clear restrictions entirely, while the original timer registration may still exist.
- This is the clearest “UI says timer is running but actual blocking is different” failure mode.

#### 2. Schedule on the same profile can prematurely terminate an active timer at schedule end

- If the schedule starts on the same profile as the active timer, `ScheduleTimerActivity.start()` sees a matching shared session and simply re-applies restrictions in [`DoCard/Models/Timers/ScheduleTimerActivity.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Models/Timers/ScheduleTimerActivity.swift:91).
- When that schedule later ends, `ScheduleTimerActivity.stop()` deactivates restrictions and calls `SharedData.endActiveSharedSession()` in [`DoCard/Models/Timers/ScheduleTimerActivity.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Models/Timers/ScheduleTimerActivity.swift:116).
- Since the shared session is still the original timer session snapshot, the timer session is effectively ended by the schedule end callback.

Impact:

- A timer can end early even though its configured duration has not elapsed.
- The end reason recorded through the shared-session path becomes `timer_expired`, even though the real cause was “schedule window ended”.
- This is a timer/schedule correctness bug, not just a UI inconsistency.

### Medium Severity

#### 3. Background timer start bypasses the `wouldShieldAnything` guard and can create a live session with no blocking

- Foreground timer start goes through `StrategyManager.startBlocking()`, which aborts if `AppBlockerUtil.wouldShieldAnything` is false in [`DoCard/Utils/StrategyManager.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/StrategyManager.swift:913).
- Background timer start (`startSessionFromBackground(durationInMinutes:)`) does not perform that check before invoking `ShortcutTimerBlockingStrategy.startBlocking()` in [`DoCard/Utils/StrategyManager.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/StrategyManager.swift:513).
- `ShortcutTimerBlockingStrategy.startBlocking()` calls `activateRestrictions()` and creates the session unconditionally in [`DoCard/Models/Strategies/ShortcutTimerBlockingStrategy.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Models/Strategies/ShortcutTimerBlockingStrategy.swift:27).
- `AppBlockerUtil.activateRestrictions()` explicitly no-ops when effective tokens are empty after tier enforcement in [`DoCard/Utils/AppBlockerUtil.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/AppBlockerUtil.swift:86).

Impact:

- A shortcut-triggered timer can look active while blocking nothing, especially for free-tier profiles that only selected categories or web domains.
- This is a real false-active-session path.

#### 4. Timer sessions are created before timer registration success is known, so authorization or `startMonitoring` failure silently disables auto-expiry

- Both timer strategies apply restrictions and create a session before `DeviceActivityCenterUtil.startStrategyTimerActivity()` returns in [`DoCard/Models/Strategies/NFCTimerBlockingStrategy.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Models/Strategies/NFCTimerBlockingStrategy.swift:51) and [`DoCard/Models/Strategies/ShortcutTimerBlockingStrategy.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Models/Strategies/ShortcutTimerBlockingStrategy.swift:37).
- `startStrategyTimerActivity()` returns early if Family Controls authorization is not approved, and it only logs `startMonitoring` failures instead of surfacing them or rolling back the session in [`DoCard/Utils/DeviceActivityCenterUtil.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/DeviceActivityCenterUtil.swift:129).

Impact:

- The user can enter a timer session that blocks apps immediately but never auto-unlocks.
- The failure mode is silent from the user’s perspective unless they inspect logs or debug UI.

#### 5. Timer expiry is truncated near midnight, and the accepted duration range is inconsistent

- `TimerDurationView` advertises “24h” but caps the slider at `1439` minutes while still including `1440` in snap points in [`DoCard/Components/Strategy/TimerDurationView.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Components/Strategy/TimerDurationView.swift:18).
- Background timer start accepts durations up to `1440` minutes in [`DoCard/Utils/StrategyManager.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/StrategyManager.swift:513).
- `DeviceActivityCenterUtil.getTimeIntervalStartAndEnd()` caps any rollover at `23:59` in [`DoCard/Utils/DeviceActivityCenterUtil.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/DeviceActivityCenterUtil.swift:235).

Impact:

- A timer started late in the day can expire much earlier than requested.
- Example: starting a 60-minute timer at 23:30 produces an end time of 23:59, not 00:30.
- A background-triggered 1440-minute timer cannot be represented faithfully by the scheduling helper.

#### 6. Relaunch recovery uses mutable profile timer settings instead of immutable session-time data

- On relaunch, `StrategyManager.loadActiveSession()` calculates `plannedEndTime` from `session.blockedProfile.strategyData` in [`DoCard/Utils/StrategyManager.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Utils/StrategyManager.swift:127).
- That value is profile configuration, not a session snapshot of the duration selected when the timer started.

Impact:

- If the profile’s timer duration is edited while a timer is active, the app can later restore the session with the wrong expiry threshold.
- This can cause both premature close and overlong restore depending on whether the setting was reduced or increased.

### Low Severity

#### 7. The debug markdown export under-reports strategy timers

- The live debug card knows how to classify `StrategyTimerActivity`, but the markdown export in `DebugView` does not in [`DoCard/Views/DebugView.swift`](/Users/chen/Desktop/DO-V2.0.4/DoCard/Views/DebugView.swift:222).

Impact:

- Investigation output copied from the in-app debug screen can hide the presence of active strategy timers.
- This is an observability gap, not a blocker bug.

## Scenario Matrix

| Scenario | Expected | Code path today | Result |
|---|---|---|---|
| Timer A active, schedule B starts | one clear owner or explicit rejection | schedule B ends timer A shared session, then writes B restrictions | state divergence; real blocker becomes B |
| Timer A active, schedule A starts | timer remains authoritative until its own expiry | schedule start reuses shared timer session, schedule end ends that shared session | timer can end early |
| Schedule active, timer starts via UI | reject | timer strategy cannot be selected for profiles with active schedules | blocked in UI only |
| Schedule configured, timer starts via shortcut before schedule window | explicit runtime rule | no runtime schedule conflict guard in shortcut path | allowed; later overlap can break |
| Shortcut timer on empty effective selection | reject with message | session is created after `activateRestrictions()` no-op | false-active timer |
| Authorization missing when timer starts | reject or roll back | restrictions/session happen before timer registration attempt | timer starts but may never auto-expire |
| App relaunch after user edits timer duration | restore original timer semantics | relaunch reuses current profile `strategyData` | expiry semantics can drift |

## Observability Notes

Useful existing logs:

- `AppBlockerUtil`: effective token no-op and shield application
- `DeviceActivityCenterUtil`: authorization failures and `startMonitoring`
- `DeviceActivityMonitorExtension`: interval start/end dispatch
- `StrategyTimerActivity` and `ScheduleTimerActivity`: shared-session ownership decisions

Current observability gaps:

- No user-visible error when timer registration fails after the session is already active.
- No explicit log tying `StrategyManager.activeSession` to shared-session replacement during schedule overlap.
- Debug markdown export misses `StrategyTimerActivity`.

## Recommended Follow-Up Fix Areas

1. Separate timer-session ownership from schedule-session ownership instead of sharing a single `activeSharedSession` slot for both.
2. Move timer registration validation earlier, or roll back session creation and shields when strategy timer registration fails.
3. Persist immutable timer duration per session and use that for expiry/recovery.
4. Replace the midnight cap helper with real date-based scheduling semantics.
5. Add a backend runtime conflict guard for shortcut/background timer starts, not just UI prevention.
