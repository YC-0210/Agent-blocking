# DO Card — Code Architecture Reference

## Tech Stack
- **Language**: Swift / SwiftUI
- **Persistence**: SwiftData
- **NFC**: iOS Core NFC Framework + NFC Tools Library (not from scratch)
- **Screen Time**: Apple Family Controls API (FamilyActivityPicker, ManagedSettingsStore, ShieldConfiguration, DeviceActivityCenter)
- **Auth storage**: Keychain (`com.do-app.security`)
- **Shared state**: App Group `group.DO.version3` — HMAC-SHA256 signed UserDefaults (CryptoKit, 256-bit SymmetricKey stored in Keychain)
- **Build tool**: Xcode
- **Localization**: Traditional Chinese (`Localizable.xcstrings`)

### ThemeManager Color Distinction
- `ThemeManager.accentColor` is the canonical DO Orange (`#FF6B35`) and is defined in `ThemeManager.swift`. Use this for brand elements.
- `ThemeManager.availableColors` exposes the selectable theme palette; `themeManager.themeColor` returns the current user-selected color.
- Do not introduce `#F26419` unless the codebase is intentionally changed to use it.

---

## Verified File Map

```
DoCard/
├── DoCardApp.swift                              # App entry — wires up the model container and shared managers
├── Models/
│   ├── Shared.swift                             # App Group UserDefaults keys
│   ├── SubscriptionState.swift                  # SubscriptionTier enum (free/premium)
│   ├── BlockedProfileSessions.swift             # BlockedProfileSession SwiftData model
│   ├── NFCTapEvent.swift                        # NFCTapEvent SwiftData model (v2.0)
│   ├── EmergencyUnlockEvent.swift               # EmergencyUnlockEvent SwiftData model (v2.0)
│   └── Strategies/
│       ├── BlockingStrategy.swift               # Protocol
│       ├── NFCBlockingStrategy.swift            # Classic NFC tap mode
│       ├── NFCTimerBlockingStrategy.swift       # Timer mode with NFC
│       ├── NFCManualBlockingStrategy.swift      # Manual NFC mode (⚠️ not in availableStrategies)
│       ├── ManualBlockingStrategy.swift         # Non-NFC manual blocking
│       └── ShortcutTimerBlockingStrategy.swift  # Siri Shortcuts integration
├── Utils/
│   ├── AppBlockerUtil.swift                     # ⚠️ Enforcement gate for Freemium
│   ├── SubscriptionManager.swift                # @MainActor StoreKit 2 singleton
│   ├── StrategyManager.swift                    # emergencyUnblock() + break management
│   ├── NFCScannerUtil.swift                     # NFC identifiers defined here
│   ├── NFCWriter.swift                          # NFC tag writing utility
│   ├── FocusScoreCalculator.swift               # Focus Score + Peak Time (v2.0)
│   └── HabitCurveCalculator.swift               # Mitscherlich habit curve (v2.0)
├── Views/
│   ├── HomeView.swift                           # Injects SubscriptionManager as env object
│   ├── ScheduleTabView.swift                    # Premium-gated schedule creation/editing
│   ├── SettingsTabView.swift                    # Subscription row + pairing + emergency unlock
│   ├── PaywallView.swift                        # Paywall modal
│   ├── EmergencyView.swift                      # Dedicated emergency unlock view
│   └── ReportView.swift                         # Focus Report view (v2.0)
├── ViewModels/
│   └── ReportViewModel.swift                    # Focus Report VM — always computes premium metrics
├── Components/
│   ├── BlockedProfileView/
│   │   └── AppPicker.swift                      # ⚠️ UI gate for Freemium (>3 apps)
│   └── Common/
│       └── PremiumBlurOverlay.swift             # Reusable blur modifier for premium features
└── Localizable.xcstrings                        # Traditional Chinese strings

DoCardDeviceMonitor/
└── DeviceActivityMonitorExtension.swift         # Reads subscriptionTier before activating

DoCardShieldConfig/
└── ShieldConfigurationExtension.swift           # Reads subscriptionTier for shield UI
```

---

## NFC Technical Details

| Property | Value |
|----------|-------|
| NDEF External Type | `docard.app:card` (defined in `NFCScannerUtil.swift` line 33) |
| MIME type | `docard.app/card` (defined in `NFCScannerUtil.swift` line 34) |
| ⚠️ Payload format | **UUID string** (UTF-8 encoded profile UUID) — NOT JSON as previously thought |
| Chip | NTAG213 (CR80 card: 85.6×54×0.76mm) |
| Background reading | Enabled — app wakes instantly, no foreground required |
| Legacy identifiers | None — `do-app.com:lock` and `foqos` fully removed |

---

## Blocking Strategies

`StrategyManager.availableStrategies` currently includes:
- `NFCBlockingStrategy`
- `NFCTimerBlockingStrategy`

`StrategyManager.getStrategyFromId(id:)` can instantiate all five strategies below.

| Strategy | NFC? | In `availableStrategies`? | Supported by `getStrategyFromId`? |
|----------|------|--------------------------|----------------------------------|
| `NFCBlockingStrategy` | ✅ | ✅ | ✅ |
| `NFCTimerBlockingStrategy` | ✅ | ✅ | ✅ |
| `NFCManualBlockingStrategy` | ✅ | ❌ | ✅ |
| `ManualBlockingStrategy` | ❌ | ❌ | ✅ |
| `ShortcutTimerBlockingStrategy` | ❌ | ❌ | ✅ |

⚠️ `NFCManualBlockingStrategy` creates sessions tagged with `ManualBlockingStrategy.id` — may be intentional sharing or a bug. Investigate before relying on session tags to identify strategy type.

---

## SwiftData Models

### `BlockedProfiles`
Named set of apps to block.
- `enableBreaks: Bool` — ⚠️ Break infrastructure dormant but not removed
- `breakTimeInMinutes: Int`

### `BlockedProfileSession`
| Field | Type | Note |
|-------|------|------|
| `id` | String | UUID |
| `tag` | String | Strategy identifier |
| `blockedProfile` | BlockedProfiles | Relationship |
| `startTime` | Date | |
| `endTime` | Date? | nil = still active |
| `breakStartTime` | Date? | Break infrastructure (dormant) |
| `breakEndTime` | Date? | Break infrastructure (dormant) |
| `forceStarted` | Bool | Counts as manual (weight 1.0) |
| `triggerSource` | String | `"manual"`, `"scheduled"`, `"shortcut"`, or `"deeplink"` |
| `endReason` | String? | `"card_tap"`, `"timer_expired"`, `"emergency_unlock"`, or `nil` |

### `NFCTapEvent` (v2.0)
| Field | Type | Note |
|-------|------|------|
| `id` | String | UUID |
| `timestamp` | Date | Persisted (was discarded in v1) |
| `action` | String | `"start_block"` or `"end_block"` |
| `profileId` | UUID | Denormalized |
| `profileName` | String | Denormalized |

Save in: `startBlocking()` and `stopBlocking()` for NFC-based strategies

### `EmergencyUnlockEvent` (v2.0)
| Field | Type | Note |
|-------|------|------|
| `id` | String | UUID |
| `timestamp` | Date | |
| `sessionId` | String | Session interrupted |
| `profileId` | UUID | Denormalized |
| `sessionDuration` | TimeInterval | Duration before bail |

Save in: `StrategyManager.emergencyUnblock()` BEFORE counter decrement

---

## App Group Shared Keys

**Group ID**: `group.DO.version3`
**Auth method**: HMAC-SHA256 (CryptoKit). Each key has a corresponding `.hmac` suffixed key for signature. Includes upgrade path for pre-V17 unsigned data.

| Key | Type | Written by | Read by |
|-----|------|-----------|---------|
| `subscriptionTier` | String ("free"/"premium") | Main app | DeviceMonitor, ShieldConfig |
| `subscriptionExpirationDate` | Double (timeIntervalSince1970) | Main app | DeviceMonitor |
| `profileSnapshots` | — | Main app | Extensions |
| `activeScheduleSession` | — | Main app | Extensions |
| `completedScheduleSessions` | — | Main app | Extensions |
| `widgetDeepLinkTokens` | — | Main app | Widget |

---

## Freemium — Two Gates (both required)

### Gate 1: UI Gate — `AppPicker.swift`
- Confirm button: `.disabled(exceedsFreeTierLimit)` — hard block, not dismissable alert
- Inline lock icon + "升級" button (lines 97–115)
- `exceedsFreeTierLimit` = true when `categoryTokens` is non-empty OR app count > 3

### Gate 2: Enforcement Gate — `AppBlockerUtil.swift`
```swift
// Free tier enforcement (gated: tier == .free && !allowOnlyApps)
categoriesTokens = []                                        // categories stripped entirely
applicationTokens = Set(Array(applicationTokens).prefix(3)) // capped at 3 (returns Set)
webTokens = []                                               // ⚠️ stripped entirely (not prefix(3))
```

⚠️ Web domains are stripped entirely on free tier, not capped at 3 as previously documented.

---

## Break Infrastructure — Dormant, Not Removed

UI buttons for break/rest are NOT visible in user-facing views. However, the following code still exists:
- `BlockedProfiles`: `enableBreaks`, `breakTimeInMinutes`
- `BlockedProfileSessions`: `breakStartTime`, `breakEndTime`, `isBreakAvailable`, `isBreakActive`, `startBreak()`, `endBreak()`
- `StrategyManager`: `toggleBreak()`, `startBreak()`, `stopBreak()`, `handleBreakExpired()`
- `BreakTimerActivity.swift`: break timer model

The rest button removal was a **UI-only removal**. The data layer and manager logic remain. Do not reference these in user-facing copy, but be aware they exist when working on StrategyManager or session models.

---

## Emergency Unlock

- Lives in `StrategyManager.emergencyUnblock()`
- `EmergencyUnlockEvent` is inserted before `emergencyUnblocksRemaining` is decremented
- No paywall checks wrap emergency unlock; the only guards are remaining count > 0 and an active session
- Dedicated view: `EmergencyView.swift`

---

## StoreKit 2

- `SubscriptionManager.swift` — `@MainActor` (confirmed line 7)
- No RevenueCat — `Package.resolved` has zero pins
- `ReportViewModel.load()` always calls `loadPremiumMetrics()` regardless of tier (blur shows real data)
- Card bundle promo code: App Store Connect config, not in codebase

---

## Cursor Prompt Format (YAN's Preferred Style)

```
## 問題描述
[清楚說明要解決什麼問題]

## 預期行為
[列出修改後應該發生什麼]

## 需要修改的檔案
- `路徑/檔案.swift` — [說明這個檔案要做什麼改動]

## 注意事項
- [任何需要注意的限制或規則]
- [例如：不得移除 Emergency Unlock / 不得在 paywall 後放 Family Controls auth]

## 交付物
[完成後的驗證方式]
```
