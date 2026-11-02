import Foundation

/// Paid capabilities. Recovery, billing, help and legal actions are always available
/// through SubscriptionAccess.permits. NFC starts require access; NFC stops do not.
struct Entitlements {
  let appLimit: Int
  let canBlockCategories: Bool
  let canBlockWebDomains: Bool
  let canSchedule: Bool
  let canSeeDeepReport: Bool

  static let freeAppLimit = 0
  /// Existing app selection limit, retained by the paid-only policy.
  static let premiumAppLimit = 50

  static func forTier(_ tier: SubscriptionTier) -> Entitlements {
    let paid = tier == .premium
    return Entitlements(
      appLimit: paid ? premiumAppLimit : freeAppLimit,
      canBlockCategories: paid, canBlockWebDomains: paid, canSchedule: paid,
      canSeeDeepReport: paid)
  }

  static var current: Entitlements { forTier(SharedData.effectiveSubscriptionTier) }
}
