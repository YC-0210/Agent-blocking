import XCTest

@testable import DoCard

@MainActor
private final class ScriptedSubscriptionStore: SubscriptionStore {
  var grants: [SubscriptionGrant] = []
  var outcome = SubscriptionPurchaseResult.verified
  var failure = false
  var calls = 0
  func currentGrants() async throws -> [SubscriptionGrant] {
    if failure { throw URLError(.notConnectedToInternet) }
    return grants
  }
  func purchase(productID: String) async throws -> SubscriptionPurchaseResult {
    calls += 1
    if failure { throw URLError(.cannotConnectToHost) }
    return outcome
  }
  func restore() async throws { if failure { throw URLError(.cannotConnectToHost) } }
}

@MainActor
final class SubscriptionStoreTests: XCTestCase {
  private func fixture(
    _ body: (AccessFixture, ScriptedSubscriptionStore, SubscriptionManager) async throws -> Void
  ) async throws {
    let f = try AccessFixture()
    defer { f.cleanup() }
    let store = ScriptedSubscriptionStore()
    try await SharedData.$runtime.withValue(f.runtime) {
      let manager = SubscriptionManager(store: store, startAutomatically: false, scheduleExpiry: {})
      try await body(f, store, manager)
    }
  }

  func testI7VerifiedPurchaseAndRestoreUpdateSharedAccess() async throws {
    try await fixture { f, store, manager in
      store.grants = [
        SubscriptionGrant(
          productID: SubscriptionProduct.monthly,
          purchasedAt: f.clock.now, expiresAt: f.clock.now.addingTimeInterval(3600))
      ]
      await manager.purchase(productID: SubscriptionProduct.monthly)
      XCTAssertTrue(manager.isPremium)
      XCTAssertEqual(SharedData.subscriptionAccessEnd, f.clock.now.addingTimeInterval(3600))
      SharedData.subscriptionGrants = []
      await manager.restorePurchases()
      XCTAssertTrue(manager.isPremium)
      XCTAssertEqual(SharedData.subscriptionGrants?.count, 1)
    }
  }

  func testI7CancelledPendingUnverifiedAndFailedPurchasesGrantNothing() async throws {
    for outcome in [SubscriptionPurchaseResult.cancelled, .pending, .unverified] {
      try await fixture { _, store, manager in
        store.outcome = outcome
        await manager.purchase(productID: SubscriptionProduct.monthly)
        XCTAssertFalse(manager.isPremium)
        XCTAssertFalse(manager.purchaseInProgress)
      }
    }
    try await fixture { _, store, manager in
      store.failure = true
      await manager.purchase(productID: SubscriptionProduct.monthly)
      XCTAssertFalse(manager.isPremium)
      XCTAssertNotNil(manager.errorMessage)
    }
  }

  func testI7PurchaseFailureAndRestoreFailurePreserveValidOfflineProof() async throws {
    try await fixture { f, store, manager in
      f.paid()
      store.failure = true
      await manager.purchase(productID: SubscriptionProduct.monthly)
      await manager.restorePurchases()
      await manager.checkCurrentEntitlements()
      XCTAssertTrue(manager.isPremium)
      f.clock.now = f.clock.now.addingTimeInterval(1800)
      manager.refreshLocalAccess()
      XCTAssertFalse(manager.isPremium)
    }
  }

  func testI7VerifiedRevocationRemovesAccessAndUnrelatedPurchaseIsIgnored() async throws {
    try await fixture { f, store, manager in
      f.paid()
      store.grants = []
      await manager.checkCurrentEntitlements()
      XCTAssertFalse(manager.isPremium)
      XCTAssertNil(manager.expirationDate)
      await manager.purchase(productID: "unrelated.product")
      XCTAssertEqual(store.calls, 0)
    }
  }

}
