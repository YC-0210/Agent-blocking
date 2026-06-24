# 0001 — Suppression Registry owns flag storage; the scheduling-clock stays in SharedData

Status: accepted

## Decision

The schedule-suppression *storage contract* — the two key prefixes
(`emergencyUnlockedSchedule_`, `cardTapSuppressedSchedule_`), the
`"<profile>.<schedule>_<weekday>"` key shape, HMAC signing, and the read / write / cleanup of
the flags — lives in one type, `SuppressionRegistry` (`DoCard/Utils/SuppressionRegistry.swift`).
The *scheduling-clock* logic — which schedule window is open right now and when it ends —
deliberately stays in `SharedData`, which owns `ProfileSnapshot` and the calendar math.

## Why

Before this, the prefixes and key shape were copied verbatim into three processes (main app,
`StrategyManager`, and the DeviceActivity extension), and the read / cleanup loops were
re-implemented per caller. Any drift could re-lock a device immediately after an Emergency
Unlock, or fail to suppress at all. One owner removes the triplication and the per-caller key
construction; the extension now passes its `DeviceActivityName.rawValue` straight through, so
the key shape can never drift from what the writer produced.

## Considered and rejected

Moving the scheduling-clock math into the registry too — so everything "suppression" lived in
one file — was rejected. That calendar/window code is App-Store-critical reliability logic and
is coupled to `ProfileSnapshot`; relocating it adds risk for no user-facing gain. The split is
intentional: **do not merge the window math back into `SuppressionRegistry`.**

## Consequences

`SharedData`'s public suppression functions (`writeEmergencyUnlockSuppressionFlags`,
`writeCardTapSuppressionFlags`, `isScheduleCurrentlyActiveAndUnsuppressed`) keep the same
signatures and now delegate storage to the registry — their callers are unchanged. The
Emergency-Unlock ordering invariant (write the flag *before* `stopBlocking`) is preserved.
