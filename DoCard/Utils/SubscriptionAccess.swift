import Foundation

/// Values enter this model only after StoreKit verification. The saved copy is HMAC signed.
struct SubscriptionGrant: Codable, Equatable, Sendable {
  var productID: String
  var purchasedAt: Date
  var expiresAt: Date
  var verified: Bool = true
  var revoked: Bool = false
  var isFreePeriod: Bool = false
  var graceEndsAt: Date? = nil

  var accessEnd: Date {
    if !isFreePeriod, let graceEndsAt { return max(expiresAt, graceEndsAt) }
    return expiresAt
  }
}

enum SubscriptionAction: CaseIterable {
  case startSession, editSelection, editProfile, schedule, reports, pairing, otherFeature
  case stopBlocking, emergencyUnlock, purchase, restore, manageSubscription, help, legal
}

struct SubscriptionAccess {
  static let productIDs = SubscriptionProduct.allProductIDs

  static func endDate(grants: [SubscriptionGrant], now: Date) -> Date? {
    grants.filter {
      $0.verified && !$0.revoked && productIDs.contains($0.productID)
        && $0.purchasedAt <= now && now < $0.accessEnd
    }.map(\.accessEnd).max()
  }

  static func permits(_ action: SubscriptionAction, hasAccess: Bool) -> Bool {
    switch action {
    case .stopBlocking, .emergencyUnlock, .purchase, .restore, .manageSubscription, .help, .legal:
      return true
    default: return hasAccess
    }
  }
}
