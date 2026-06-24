# 0002 — Active-session status: unify the read, keep the stores split

Status: accepted

## Decision

The question *"is a session active right now — and for which profile, and what kind?"* gets
**one answer**, exposed as a small, independently-testable value type (`ActiveSessionStatus`)
that `StrategyManager` vends. The ~10 in-app screens + 2 Shortcuts intents read *that* instead
of each re-deriving the answer from raw session objects.

(Named `ActiveSessionStatus`, not `SessionStatus` — the latter is the existing started/ended
lifecycle-event enum in `BlockingStrategy`; renaming that is out of scope.)

The underlying session **stores stay split and are NOT merged**:
- **SwiftData** (`BlockedProfileSession`) — authoritative local history; readable only by the main app.
- **App Group snapshots** (`activeStrategySharedSession`, `activeScheduleSharedSession`) — the
  cross-process signaling layer the DeviceActivity extension and widget read.

## Why

"Is a session active?" was answered ~6 ways and re-derived across ~10 screens, with the
manual-beats-scheduled precedence re-implemented or ignored ad hoc — a real bug surface. One
read API makes the answer consistent and testable, and lifts the concept out of the ~1,300-line
`StrategyManager` god object.

But the multiple *stores* are **load-bearing, not accidental duplication**: the extension and
widget run in a separate process and cannot read SwiftData, so they depend on the App Group
snapshots. Merging the stores would break blocking and the widget. So we unify the *read*, not
the *storage*.

## Invariants the read API must preserve

- **Precedence:** a manual / NFC session beats a scheduled one (`activeStrategySharedSession ??
  activeScheduleSharedSession`).
- **Cold start:** a freshly-opened scheduled window lives only in the App Group until
  `syncScheduleSessions()` upserts it into SwiftData; the answer must report an active schedule
  even before that sync.
- **SwiftData stays authoritative** for history / audit and conflict resolution; the in-memory
  `activeSession` drives live UI.
- **Scope:** in-app readers only. The widget and DeviceActivity extension keep reading the App
  Group snapshots directly — out of scope here.

## Consequences

Behavior is preserved where screens already agree. Where a screen was quietly inconsistent
(e.g. ignored precedence, or showed the wrong profile during a schedule), it becomes correct —
and every such change is listed for on-device review rather than altered silently. Do **not**
"simplify" later by merging the stores; see *Why*.
