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

**Home centerpiece**
The single focal element in the middle of the DO page. Exactly one is shown at a time, chosen by the user: the Motivation Gallery (動力相簿, default), the original DO Card, or Today's Tasks (今日目標). Switching is a pick-one chooser, not a swipe deck.
_Avoid:_ hero, banner, home card

**Today's Tasks** (今日目標 / "Today's Tasks")
A home-centerpiece option showing the user's main goals for the current day — up to three. The DOer's intent for the day, on the same screen as the card tap. A new day clears completed goals and carries unfinished ones forward; no past-days history is kept.
_Avoid:_ to-do, 待辦, checklist

**Daily Task**
One entry in Today's Tasks: a short **name** (shown on the centerpiece), an optional longer **detail** (revealed and edited by tapping the name), and a done state toggled by its checkbox. Tapping the name edits; the checkbox completes — two distinct tap targets.
_Avoid:_ to-do item, todo

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
An HMAC-signed App Group UserDefaults key that prevents a scheduled window from re-engaging after the user has explicitly ended it. Two reasons, each its own key namespace: `emergencyUnlockedSchedule_<activityId>` and `cardTapSuppressedSchedule_<activityId>`. Owned end-to-end by **Suppression Registry** — one place defines the prefixes, key shape, signing, and cleanup; no process keeps its own copy.
_Avoid:_ disable flag, block flag

**Suppression Registry** (`Utils/SuppressionRegistry.swift`)
The single owner of the suppression-flag *storage* contract: the two reason prefixes, the `"<profile>.<schedule>_<weekday>"` activity-id shape, HMAC signing (via `SharedData`), and read / write / cleanup. The app, `StrategyManager`, and the DeviceActivity extension all cross this one interface (`suppress`, `isSuppressed`, `cleanupExpired`, `activityId`) instead of re-implementing it. Owns *storage only* — the scheduling-clock (which window is active, when it ends) deliberately stays in `SharedData`; see `docs/adr/0001-suppression-registry.md`.
_Avoid:_ re-deriving prefixes or building suppression keys by hand; merging the window math into it

**Active session status** (`ActiveSessionStatus`, vended by `StrategyManager`)
The single in-app answer to "is a focus session active, for which profile, and what kind?" — a small value type every in-app screen + Shortcuts intent reads, instead of re-deriving from raw session objects. Encodes the manual-beats-scheduled precedence and the cold-start rule (a scheduled window counts as active even before it is synced into SwiftData). Reads the existing stores; does **not** merge them — the App Group snapshots stay the cross-process signaling layer for the widget / DeviceActivity extension. (Named `ActiveSessionStatus` to avoid colliding with `SessionStatus`, the started/ended lifecycle-event enum in `BlockingStrategy`.) See `docs/adr/0002-active-session-status-read-api.md`.
_Avoid:_ re-deriving `activeSession?.isActive` or reaching into raw session objects from views; merging the session stores; confusing it with `SessionStatus` (the lifecycle event)

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
| `Utils/SuppressionRegistry.swift` | Single owner of suppression-flag storage — prefixes, key shape, signing, cleanup; app + extension both cross it |
| `Models/Shared.swift` | App Group keys, HMAC helpers, suppression flag writers (delegate storage to `SuppressionRegistry`) |
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
