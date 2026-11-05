# DO Card

Physical NFC card + iOS app that uses Apple's Screen Time API (Family Controls) to block distracting apps. The card tap is an intentional ritual — physical separation creates commitment that software-only solutions cannot replicate.

**Current repository:** iOS app (`DOCard-ios`). Browser-extension repositories are outside this change.
**Live version:** v2.0.8 — Freemium + Focus Report + Motivation Gallery (動力相簿)
**Phase:** Stabilise & grow — no large features in active development

---

> **Paid-only access update (2026-11-02):** ADR-0007 supersedes the earlier freemium
> rules. All remaining normal functions, including NFC starts, need active verified
> subscription/trial/offer/grace access. Stops, Emergency Unlock, billing, help and legal
> access remain available. Grace is Apple-confirmed, three days, paid-to-paid only; no
> local extra-day extension. Expiry ends blocking as soon as iOS permits and preserves
> history/settings. See `docs/testing/selection-access.md` for local checks and device limits.

> **Agent experiment exception (2026-11-05):** Per user request, ADR-0013 exempts
> agent focus from subscription checks in setup, execution and restoration. This
> branch now launches directly into Agent Focus; legacy home/onboarding/paywalls,
> StoreKit refresh and subscription expiry handling are excluded from its lifecycle.
> Screen Time authorization and phone-approved limits remain required.

## Next-version scope (2026-11-02)

Co-Focus and device synchronization are removed from the app: no shared-focus tab,
pairing UI for external devices, sync badge, purchase advertising, network clients,
background sync calls or NFC diversion. Physical DO Card pairing remains.
The Supabase SDK dependency is removed. Anonymous usage analytics keeps its existing
REST transport and zero-valued retired-feature columns for wire compatibility.
No backend records, old pairing credentials, browser-extension repositories or stored
SwiftData schemas are changed. See ADR-0008 and the local changelog.

Subscription expiry imports preserve saved scheduled-session breaks and close an open
break at removal time. New subscription grant snapshots require a valid signature;
they do not use the unsigned legacy migration. Older keys keep their existing upgrade path.

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

**Subscription access gate** — always UI and enforcement
All normal features require active access. The root screen and picker gate interactions;
profile writes, strategies, shortcut starts, schedule callbacks and `AppBlockerUtil` enforce
access again. Stops and billing/help/legal access remain available. See ADR-0007.

**Entitlements** (`Utils/Entitlements.swift`)
The capability rule book maps `.free` to disabled normal features and `.premium` to the
remaining paid capabilities (50 apps, categories, websites, schedules and reports).
`SubscriptionAccess` resolves verified purchase/grace facts and the exceptional actions.

**effectiveSubscriptionTier**
The canonical shared decision uses the signed `subscriptionGrants` snapshot and its verified
end time. Older signed premium/expiration values retain only their remaining valid period.
There is no automatic local grace extension. Debug force-tier remains Debug-only.

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

**Tech stack:** Swift / SwiftUI · SwiftData (schema V5, stamp 2.2.0) · Family Controls · StoreKit 2 (no RevenueCat) · App Group `group.DO.version3` (HMAC-SHA256 signed via CryptoKit)

**Session persistence — dual model (critical):**
- Manual / NFC sessions → SwiftData (`BlockedProfileSession`) → restored by `loadActiveSession()`
- Scheduled sessions → App Group UserDefaults (`activeScheduleSession`) → restored by `restoreScheduledSessionIfNeeded()`
- These are **separate stores**. `loadActiveSession()` cannot see scheduled sessions.

**Key files:**

| File | Role |
|------|------|
| `Utils/StrategyManager.swift` | Session lifecycle, Emergency Unlock, schedule restore, suppression flags |
| `Utils/AppBlockerUtil.swift` | ⚠️ Enforcement gate — verified access plus full restriction replacement |
| `Components/BlockedProfileView/AppPicker.swift` | ⚠️ UI gate — free tier app selection (asks `Entitlements`) |
| `Utils/Entitlements.swift` | Rule book — tier → capabilities; grace-aware `current`; UI + enforcement gates both ask it |
| `Utils/SuppressionRegistry.swift` | Single owner of suppression-flag storage — prefixes, key shape, signing, cleanup; app + extension both cross it |
| `Models/Shared.swift` | App Group keys, HMAC helpers, suppression flag writers (delegate storage to `SuppressionRegistry`) |
| `Utils/SubscriptionManager.swift` | StoreKit 2 singleton (`@MainActor`) |
| `Models/BlockedProfileSessions.swift` | SwiftData session model |
| `Utils/Analytics/RetentionTimeCalculator.swift` | Pure completed-session time allocation into fixed 3-calendar-day periods; 120-minute total threshold. Local capture uses ADR-0011; PostHog batch upload uses ADR-0012. See ADR-0010 for arithmetic. |
| `DoCardDeviceMonitor/DeviceActivityMonitorExtension.swift` | Extension — reads subscription tier before applying shields |
| `Models/AppMigrationPlan.swift` | SwiftData migration plan — update on any schema change |

**Multi-target project:** Main app / `DoCardDeviceMonitor` / `DoCardShieldConfig` / `DoCardWidget` — see git safety rules below before staging.

---

## Rules — Never Violate

1. **Emergency Unlock is always free** — no tier check anywhere in `emergencyUnblock()` or `EmergencyView.swift`
2. **NFC starts require active access; NFC stops remain available** — ADR-0007 supersedes the old free-start rule.
3. **Family Controls authorization implementation is unchanged** — the root app gate requires access before normal app/onboarding use; never charge separately for OS permission.
4. **Every paid feature needs two gates** — UI gate (user-facing block) + enforcement gate (`AppBlockerUtil.swift` access check and full restriction plan)
5. **Always use `SharedData.effectiveSubscriptionTier`** — raw tier flags do not prove an unexpired subscription.
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
- **Subscription expiry on a phone:** local access/cleanup tests now cover the agreed paid-only rule (ADR-0007); independent iOS background delivery and actual shields still require device checks.
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

Retention capture (ADR-0011): `RetentionCapture` connects successful starts, recorded breaks
and completions to the App Group `RetentionJournal`. The journal preserves cohort state,
daily contribution revisions and retractions independently of the transient shared buffer.
The deleted-project daily upload is no longer invoked. PostHog delivery is now wired through RetentionUploadService (ADR-0012).

Retention upload: `RetentionEventBuilder` emits only cohort entry and daily time
contributions. `PostHogRetentionUploader` uses the documented batch API and durable
per-destination revision checkpoints; `RetentionUploadService` drains in the main app
after disclosure. Config lives in ignored `Config/PostHog.local.xcconfig` or CI settings.
Debug/Release journals are separate; production queries must filter environment and
exclude synthetic records. Raw contribution events must be deduplicated before sums.


## Agent focus experiment (2026-11-05)

The explicit `codex/mcp-focus-experiment` branch adds an opt-in, card-free agent mode.
This is a scoped exception to ADR-0008, not restoration of Co-Focus or old sync clients.
The phone owns app selection and approved hours/duration. Separate named shields,
local expiry and replay state preserve existing card behavior and emergency access.
Codex connects to Linear separately; no usage histories or selection tokens are exported.
See ADR-0013, `docs/experiments/agent-focus-design.md`, and
`experiments/agent-focus/README.md` for setup and known unverified device behavior.
