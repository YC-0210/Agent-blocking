---
name: do-card-context
description: >
  Load full DO Card project context for any task involving the DO Card app, its Swift/SwiftUI codebase,
  NFC/Screen Time architecture, Freemium/StoreKit 2 logic, Focus Report metrics, brand guidelines,
  marketing copy, competitive positioning, or Taiwan market strategy.

  ALWAYS trigger this skill when the user mentions: DO Card, DO Card app, do-card.online, NFC blocking,
  Screen Time API, Family Controls, SwiftData blocking, Foqos, Focus Report, SubscriptionManager,
  AppBlockerUtil, PaywallView, 儀式感, Taiwan screen time, Unpluq, Brick app, or any DO Card feature work.

  Use this skill for: writing Cursor prompts, generating marketing copy, designing UI, making product
  decisions, writing website content, creating social media posts, or any strategic discussion about DO Card.
---

# DO Card — Full Project Context

> For deep Swift/SwiftUI implementation details → read `references/code-architecture.md`
> For brand guidelines, copy rules, competitive positioning → read `references/marketing-brand.md`

---

## Product Overview

**DO Card** is a physical NFC card paired with an iOS app that uses Apple's Screen Time API to block
distracting apps. Core insight: **physical separation creates commitment software-only solutions cannot
replicate.** Tapping the card is an intentional ritual — it cannot be bypassed from the same screen.

- **Website**: do-card.online  
- **Email**: do-card@do-card.online  
- **Instagram**: @do_card_  
- **App Store**: Live (March 2026); search visibility limited — share via direct link  
- **Current status**: 5 early adopter sales, 15 free experience testers active, v2.0 in development

---

## Current App State

| Item | Detail |
|------|--------|
| Version live | 1.0 — all features free, no subscription |
| Version in dev | 2.0 — Freemium + Focus Report |
| Base codebase | Foqos (MIT open source), heavily modified |
| NFC identifier | `docard.app:card` (NDEF External Type) / MIME `docard.app/card` |
| App Group | `group.DO.version3` |
| UI accent color | `#FF6B35` — always via `ThemeManager.accentColor` |
| Localization | Traditional Chinese primary, English secondary |
| Brand name rule | "DO", "App", "DO Card" always kept in English, not translated |

---

## Pricing

| Plan | Price |
|------|-------|
| Card (hardware) | NT$690 (includes 3-month Premium promo code) |
| Monthly subscription | NT$99 |
| Annual subscription | NT$790 |
| Card + Annual bundle | NT$990 |

---

## Freemium Tier Design (v2.0)

| Feature | Free | Premium |
|---------|------|---------|
| NFC trigger | ✅ | ✅ |
| App block limit | 3 apps max | Unlimited |
| Category blocking | ❌ | ✅ |
| Scheduled automation | ❌ | ✅ |
| Basic weekly report | ✅ | ✅ |
| Deep Focus Report + trends | ❌ | ✅ |
| Emergency Unlock | ✅ Always free | ✅ Always free |
| Family Controls auth | ✅ Always free | ✅ Always free |

**App Store hard rules — NEVER violate:**
- `RequestAuthorization` (Family Controls) is never paywalled
- Emergency Unlock is never paywalled
- NFC trigger (start/stop) is never paywalled

---

## Cursor Prompt Format

When generating prompts for Cursor / Claude Code, always use this structure:

```
## 問題描述
[具體說明要改什麼、哪裡有 bug、或要新增什麼功能]

## 預期行為
[改完後應該發生什麼]

## 相關檔案
[列出涉及的 Swift 檔案路徑]

## 限制條件
[不能動的東西、App Store 規則、架構限制]

## 交付物
[要生成/修改哪些具體檔案或 function]
```

Always include in constraints: Emergency Unlock must remain free. Never touch `RequestAuthorization` flow.

---

## Key Architecture Rules (Quick Reference)

- **Two Freemium gates**: UI gate (`AppPicker.swift`) + enforcement gate (`AppBlockerUtil.swift`) — both must be present
- **Subscription sharing**: App Group UserDefaults keys `subscriptionTier` (String) + `subscriptionExpirationDate` (Double)
- **Premium blur**: Use `PremiumBlurOverlay.swift` reusable modifier — never hardcode blur ad-hoc
- **Brand orange**: Always `ThemeManager.accentColor`, never hardcode `#FF6B35` directly
- **Session modes**: Classic (no timer, card ends session) vs Timer (preset duration, card or expiry ends)
- **No rest button in UI**: Hidden from user-facing screens, but break-related model and manager logic still exist
- **Session weights**: manual tap = 1.0, scheduled completed = 0.5, scheduled interrupted = 0.25
- **forceStarted sessions**: Classify as `manual` weight (1.0), not `scheduled`

→ Full architecture + SwiftData models + NFC flow: `references/code-architecture.md`

---

## Marketing Quick Reference

| Item | Value |
|------|-------|
| Core tagline | 輕觸卡片，為每個重要時刻建立儀式感，讓一天有了清晰的節奏 |
| Core sentence | **「做就對了」** — verified CTA (2487 comments, 150 LINE adds) |
| Identity system | **DOer** — someone who acts on ideas, doesn't let phone steal their time |
| Positioning | Empowerment / self-sovereignty — NOT restriction / parental control |
| Tone benchmarks | MUJI, Moleskine, early Apple |
| Primary target | Taiwan students + young professionals, 16–35, iOS users |
| Avoid | 戒癮、管控、阻止、禁止、上癮、少滑手機 |
| Use instead | 儀式感、主權、節奏、做就對了、DOer、我完成了___ |

→ Full brand spec, DOer identity system, UGC framework, LINE principles, competitive analysis: `references/marketing-brand.md`
