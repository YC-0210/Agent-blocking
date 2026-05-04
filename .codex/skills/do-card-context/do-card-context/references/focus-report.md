# DO Card — Focus Report System Reference

## Data Tier

| Metric | Free/Premium | Source |
|--------|-------------|--------|
| Total block duration (weekly) | Free | `BlockedProfileSession` |
| Block session count | Free | `BlockedProfileSession` |
| Top 3 blocked apps | Free | `BlockedProfileSession` |
| NFC tap count (weekly) | Premium | `NFCTapEvent` |
| Peak tap hours heatmap | Premium | `NFCTapEvent` grouped by `Calendar.component(.hour)` |
| Session completion rate | Premium | `BlockedProfileSession.endReason != "emergency_unlock"` |
| Focus Score (0–100) | Premium | Derived formula (see below) |
| Week-over-week trend (4 weeks) | Premium | `BlockedProfileSession` grouped by `weekOfYear` |
| Best focus time suggestion | Premium | `NFCTapEvent` + session success rate by hour |

---

## Session Fields (v2.0 additions to `BlockedProfileSession`)

```swift
var triggerSource: String = "manual"   // "manual" | "scheduled" | "shortcut" | "deeplink"
var endReason: String?                  // "card_tap" | "timer_expired" | "emergency_unlock" | nil (active)
```

### Where these are written

**`triggerSource`:**
| Call site | Value |
|-----------|-------|
| `NFCBlockingStrategy.startBlocking()` | `"manual"` |
| `NFCTimerBlockingStrategy.startBlocking()` | `"manual"` |
| `NFCManualBlockingStrategy.startBlocking()` | `"manual"` |
| `SharedData.createSessionForSchedular()` | `"scheduled"` |
| `StrategyManager.startSessionFromBackground()` | `"shortcut"` |
| `StrategyManager.toggleSessionFromDeeplink()` | `"deeplink"` |

**`endReason`:**
| Call site | Value |
|-----------|-------|
| NFC strategy `stopBlocking()` `onTagScanned` handler | `"card_tap"` |
| `StrategyTimerActivity.stop()` / `SharedData.endActiveSharedSession()` | `"timer_expired"` |
| `StrategyManager.emergencyUnlock()` (before counter decrement) | `"emergency_unlock"` |

### ⚠️ Pre-v2.0 behavior (for reference only)

Before these fields existed, the system used fragile inference:
- Timer expiry = inferred by exclusion (no NFCTapEvent + no EmergencyUnlockEvent)
- Manual vs scheduled = 60-second time-window join between session.startTime and NFCTapEvent
- `forceStarted: Bool` was used as a proxy but is ambiguous (covers scheduled + shortcuts + deeplinks)

Do NOT use these inference methods in new code. Read the fields directly.

---

## Three-Layer Architecture

### Layer 1 — Behavioral Data (raw)
Session duration, completion rate, tap count, time-of-day heatmap, streak, weekly total

### Layer 2 — Derived Metrics (key formulas)

**Focus Score** (`FocusScoreCalculator.swift`)
```
score = min(
  completionRate × 0.6
  + durationScore × 0.3        // target baseline: 5 hrs/week
  + consistencyBonus × 0.1,    // 100 if ≥5 active days, scaled otherwise
  1.0
) × 100
```
- `qualifiedSession`: ≥ 10 minutes (prevents score inflation)
- `completionRate`: sessions where `endReason != "emergency_unlock"` / total sessions

**Peak Focus Time**
```
focusQuality(hour) = w1×tapPreference + w2×completionRate + w3×normalizedDuration
// w1=0.3, w2=0.5, w3=0.2
// Requires ≥3 samples per slot AND ≥14 days usage
```

**Optimal Session Length**
- Timer mode: `effectiveFocusMinutes = avgDuration × completionRate`
- Classic mode: `naturalFocusSpan = median(card_tap_sessions)`
- Each bucket: ≥3 samples required

**Habit Formation** (`HabitCurveCalculator.swift`)

Uses Mitscherlich growth model:
```
y = a × (1 − e^(−d/τ))
```
- `y` = habit automation level (0–1)
- `d` = number of active days
- `τ` = time constant

Session weight via `triggerSource` field (direct read, no join):
```swift
let weight: Double
switch session.triggerSource {
case "manual":    weight = 1.0
case "scheduled": weight = session.endReason == "emergency_unlock" ? 0.25 : 0.5
default:          weight = 0.5
}
```

Phases: Deliberate (1–21d) → Transition (22–66d) → Automated (67d+)
Requires ≥7 active days before showing.
`autonomyRatio` = manual sessions / total sessions (habit internalization tracker)

### Layer 3 — Subjective Feedback
Post-session rating, perceived time distortion, 4-question SRBAI simplified

All calculations run on-device — no server required.

---

## Event Tables (audit / history — NOT primary calculation source)

`NFCTapEvent` and `EmergencyUnlockEvent` remain in the data model for:
- NFC tap count metric
- Peak hours heatmap
- Emergency unlock history display

They are NO LONGER used as the primary source for trigger/end inference in calculators.

---

## Academic Foundations

| Concept | Source |
|---------|--------|
| Attention restoration cost (23min recovery) | Gloria Mark |
| Ultradian rhythm (90min BRAC cycle) | Kleitman |
| Flow state | Csikszentmihalyi; Nature subjournal 2024/2025 |
| Circadian cognitive peaks (Synchrony Effect) | — |
| Habit formation median 66 days | Lally 2010, European Journal of Social Psychology |
| Sustained attention paradox | — |
