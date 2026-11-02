import StoreKit

@MainActor
protocol SubscriptionStore {
  func currentGrants() async throws -> [SubscriptionGrant]
  func purchase(productID: String) async throws -> SubscriptionPurchaseResult
  func restore() async throws
}

enum SubscriptionPurchaseResult { case verified, cancelled, pending, unverified }

@MainActor
struct StoreKitSubscriptionStore: SubscriptionStore {
  func currentGrants() async throws -> [SubscriptionGrant] {
    var grants: [SubscriptionGrant] = []
    for await result in StoreKit.Transaction.currentEntitlements {
      guard case .verified(let transaction) = result,
        SubscriptionAccess.productIDs.contains(transaction.productID),
        let expiration = transaction.expirationDate, !transaction.isUpgraded
      else { continue }
      var grant = SubscriptionGrant(
        productID: transaction.productID,
        purchasedAt: transaction.purchaseDate, expiresAt: expiration,
        revoked: transaction.revocationDate != nil,
        isFreePeriod: transaction.offer?.paymentMode == .freeTrial || transaction.price == 0)
      if !grant.isFreePeriod, let status = await transaction.subscriptionStatus,
        status.state == .inGracePeriod,
        case .verified(let renewal) = status.renewalInfo
      {
        grant.graceEndsAt = renewal.gracePeriodExpirationDate
      }
      grants.append(grant)
    }
    return grants
  }

  func purchase(productID: String) async throws -> SubscriptionPurchaseResult {
    guard SubscriptionAccess.productIDs.contains(productID),
      let product = try await Product.products(for: [productID]).first
    else {
      throw CocoaError(.validationMissingMandatoryProperty)
    }
    switch try await product.purchase() {
    case .success(let result):
      guard case .verified(let transaction) = result,
        SubscriptionAccess.productIDs.contains(transaction.productID),
        transaction.revocationDate == nil
      else { return .unverified }
      await transaction.finish()
      return .verified
    case .userCancelled: return .cancelled
    case .pending: return .pending
    @unknown default: return .unverified
    }
  }

  func restore() async throws { try await AppStore.sync() }
}
