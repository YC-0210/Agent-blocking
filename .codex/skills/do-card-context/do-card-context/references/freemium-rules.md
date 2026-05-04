# DO Card — Freemium & StoreKit 2 Rules

## Pricing

| Plan | Price | Note |
|------|-------|------|
| Free tier | NT$0 | Always available |
| Monthly | NT$99 | - |
| Annual | NT$790 | - |
| Card + Annual bundle | NT$990 | Best value |
| Card purchase | NT$690 | Includes 3 months Premium via App Store Promo Code |

---

## Tier Feature Matrix

| Feature | Free | Premium |
|---------|------|---------|
| NFC trigger (start/stop blocking) | ✅ | ✅ |
| App block limit | **3 apps max** | Unlimited |
| Category blocking | ❌ stripped at enforcement | ✅ |
| Scheduled automation | ❌ | ✅ |
| Weekly report (basic) | ✅ | ✅ |
| Deep report + trends | ❌ | ✅ |
| Focus Score | ❌ (blurred with upgrade CTA) | ✅ |
| Emergency Unlock | ✅ **ALWAYS FREE** | ✅ |
| Family Controls authorization | ✅ **ALWAYS FREE** | ✅ |

---

## App Store Review Hard Rules (Never Violate)

These three things **must never** be behind a paywall — Apple will reject the app:
1. `RequestAuthorization` (Family Controls) — always free
2. Emergency Unlock — always free  
3. NFC trigger (start/stop session) — always free

---

## Implementation Gates — Two Layers

### Layer 1: UI Gate (`AppPicker.swift`)
- If user tries to select more than 3 apps on free tier: show inline lock icon + upgrade button
- Confirm button is `disabled` (hard block, not dismissable warning)
- Categories are visually hidden with upgrade prompt

### Layer 2: Enforcement Gate (`AppBlockerUtil.swift`)
Even if UI is bypassed, enforcement strips tokens:
```swift
// Free tier enforcement
categoryTokens = []
applicationTokens = prefix(3)
webDomainTokens = prefix(3)
```

### Premium Blur Pattern
Use `PremiumBlurOverlay` modifier for locked premium UI:
- `blur(6)` + `ultraThinMaterial` + lock icon
- ViewModel always computes premium metrics (so blur reveals real data on upgrade)
- Orange lock CTA uses `ThemeManager.accentColor`

---

## StoreKit 2 Implementation

- Singleton: `SubscriptionManager.swift` (`@MainActor`)
- No RevenueCat — pure StoreKit 2
- App Group shares subscription state to extensions
- `SubscriptionTier` enum: `.free` / `.premium`
- Subscription state persisted via App Group keys (see code-architecture.md)

---

## Schedule Feature (Premium Gate)

`ScheduleTabView.swift` — if free tier attempts to create a schedule, show `PaywallView` modal.
Scheduled sessions have lower weight in Focus Report metrics than manual sessions (see focus-report.md).
