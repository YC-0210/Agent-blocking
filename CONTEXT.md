# DO Card

Physical NFC card + iOS app that uses Apple's Screen Time API (Family Controls) to block distracting apps. The card tap is an intentional ritual — physical separation creates commitment that software-only solutions cannot replicate.

**Repos:** iOS app (`DO-IOS-Claude-`), Chrome extension (`do-card-chrome-extension`), Safari extension (`DO-Card-Mac-Safari-Extension`)
**Live version:** v2.0.8 — Freemium + Focus Report + Motivation Gallery (動力相簿)
**Phase:** Stabilise & grow — no large features in active development

---

## Language

**DOer**
The identity the app enables — someone who acts on ideas and doesn't let their phone steal their time. The brand's core identity.
_Avoid:_ user (in marketing copy), productivity person

**Blocking session**
A period of app restriction started by NFC tap or other trigger, ended by another tap, timer expiry, or Emergency Unlock.
_Avoid:_ lock, restriction period

**Profile** (`BlockedProfiles`)
A named set of apps to block. Users can have multiple profiles for different contexts (reading, family, couple mode).
_Avoid:_ rule set, blocker config

**Freemium gate** — always two layers
Every paid feature needs BOTH: (1) UI gate at the point of interaction and (2) enforcement gate in `AppBlockerUtil.swift`. One layer alone is never sufficient. Both layers ask the **Entitlements** rule book rather than re-deriving the free/premium rule inline.
_Avoid:_ paywall (use "gate" in code, "upgrade" in user-facing copy)

**Entitlements** (`Utils/Entitlements.swift`)
The single rule book for "what is this tier allowed to do?" — a pure value type mapping `SubscriptionTier` → capabilities (`appLimit`, `canBlockCategories`, `canBlockWebDomains`, `canSchedule`, `canSyncExternalDevices`, `canSeeDeepReport`, `canUseCoFocus`). Every gate asks it instead of re-deriving limits at a call site. `Entitlements.current` is grace-aware (reads `effectiveSubscriptionTier`), so UI gates and the enforcement gate never disagree. Governs **paid** capabilities only — never the always-free flows (card tap, Emergency Unlock, RequestAuthorization). `canUseCoFocus` is `true` for every tier today; the slot exists so future gating is a one-line change.
_Avoid:_ reading the tier and re-deriving limits inline; gating an always-free flow through it
_Debug:_ `SharedData.debugForcedTier` (`#if DEBUG` only) force-overrides `effectiveSubscriptionTier` to preview free/premium on a real device; toggle UI is the "🛠 Debug" section at the bottom of Settings. Compiled out of release builds.

**effectiveSubscriptionTier**
The canonical subscription state accessor — reads `subscriptionTier` from App Group UserDefaults and applies the 16-day grace period. Always use this. Never read `subscriptionTier` directly.
_Avoid:_ `subscriptionTier` (direct read)

**Suppression flag**
An HMAC-signed App Group UserDefaults key that prevents a scheduled window from re-engaging after the user has explicitly ended it. Multi-prefix system: `emergencyUnlockedSchedule_<activityId>` and `cardTapSuppressedSchedule_<activityId>`. Prefix lists are duplicated across main app, `StrategyManager`, and extension — all three must stay in sync.
_Avoid:_ disable flag, block flag

**Vertical slice**
A task that crosses all layers (SwiftData schema → manager → UI) so the feature is testable end-to-end after that slice. Preferred over horizontal (layer-by-layer) implementation.
_Avoid:_ phase (implies horizontal)

---

## Architecture

**Tech stack:** Swift / SwiftUI · SwiftData (schema V5, stamp 2.2.0) · Family Controls · Supabase (Co-Focus + Mac sync) · StoreKit 2 (no RevenueCat) · App Group `group.DO.version3` (HMAC-SHA256 signed via CryptoKit)

**Session persistence — dual model (critical):**
- Manual / NFC sessions → SwiftData (`BlockedProfileSession`) → restored by `loadActiveSession()`
- Scheduled sessions → App Group UserDefaults (`activeScheduleSession`) → restored by `restoreScheduledSessionIfNeeded()`
- These are **separate stores**. `loadActiveSession()` cannot see scheduled sessions.

**Key files:**

| File | Role |
|------|------|
| `Utils/StrategyManager.swift` | Session lifecycle, Emergency Unlock, schedule restore, suppression flags |
| `Utils/AppBlockerUtil.swift` | ⚠️ Enforcement gate — free tier token stripping (asks `Entitlements`) |
| `Components/BlockedProfileView/AppPicker.swift` | ⚠️ UI gate — free tier app selection (asks `Entitlements`) |
| `Utils/Entitlements.swift` | Rule book — tier → capabilities; grace-aware `current`; UI + enforcement gates both ask it |
| `Models/Shared.swift` | App Group keys, HMAC helpers, suppression flag writers |
| `Utils/SubscriptionManager.swift` | StoreKit 2 singleton (`@MainActor`) |
| `Models/BlockedProfileSessions.swift` | SwiftData session model |
| `DoCardDeviceMonitor/DeviceActivityMonitorExtension.swift` | Extension — reads subscription tier before applying shields |
| `Models/AppMigrationPlan.swift` | SwiftData migration plan — update on any schema change |

**Multi-target project:** Main app / `DoCardDeviceMonitor` / `DoCardShieldConfig` / `DoCardWidget` — see git safety rules below before staging.

---

## Rules — Never Violate

1. **Emergency Unlock is always free** — no tier check anywhere in `emergencyUnblock()` or `EmergencyView.swift`
2. **NFC trigger is always free** — `startBlocking()` / `stopBlocking()` never paywalled
3. **`RequestAuthorization` (Family Controls) is always free**
4. **Every paid feature needs two gates** — UI gate (user-facing block) + enforcement gate (`AppBlockerUtil.swift` token stripping)
5. **Always use `SharedData.effectiveSubscriptionTier`** — never read `subscriptionTier` directly (bypasses 16-day grace period)
6. **`.fullScreenCover` zeroes the top safe area** in this app — use `.overlay` for any full-screen modal that needs status bar respect
7. **SwiftData schema changes require a migration snapshot** — any new `@Model` property needs a new schema version in `AppMigrationPlan.swift`; older schema versions whose models diverge must be snapshotted inline
8. **Brand orange is `ThemeManager.accentColor`** — never hardcode `#FF6B35` or `#F26419`
9. **`git commit -a` and `git add -A` are banned** — multi-target project caused a production incident; always stage specific files explicitly

---

## Common Agent Failure Modes

- Adding a paid feature with only a UI gate, missing the enforcement gate in `AppBlockerUtil.swift`
- Reading `subscriptionTier` directly instead of `SharedData.effectiveSubscriptionTier`
- Treating session state as single-source — forgetting the SwiftData / App Group split for manual vs scheduled sessions
- Using `.fullScreenCover` for modals that need a visible status bar — produces zeroed safe area
- Using `git commit -a` or `git add -A` — stages build artifacts and unrelated target files

---

## Known Deferred Issues — Do Not Fix Without Explicit Instruction

- **`completedSessionsInSchedular` visibility gap:** completed scheduled sessions may not propagate cross-process to the main app, causing Focus Report data loss for users who never foreground the app mid-session
- **Non-NFC start path empty-token bypass:** `forceStartSession()`, `startSessionFromBackground()`, and `toggleSessionFromDeeplink()` bypass the empty-token preflight added in v2.0.4 (only the NFC path is protected)
- **Mid-session premium expiry:** subscription downgrade during an active session silently reduces blocking from unlimited to 3 apps with no user notification
- **`LiveActivityManager` mutable-profile fallback:** countdown prefers shared timer snapshot but falls back to mutable profile settings when unavailable — a proper fix requires a SwiftData schema change

---

## Reference Files

Read before touching the relevant area:

| File | When to read |
|------|-------------|
| `references/code-architecture.md` | Any SwiftData, session, NFC, or strategy change |
| `references/freemium-rules.md` | Any feature that touches paid vs free behaviour |
| `references/git-safety.md` | Before any `git add` / `git commit` / `git push` |
| `references/localization-workflow.md` | Any user-visible string added or modified |
| `references/app-store-submission-checklist.md` | Any App Store or TestFlight submission |
| `docs/agents/issue-tracker.md` | Issue tracker config (GitHub Issues on `DO-IOS-Claude-`) |
