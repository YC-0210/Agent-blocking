import StoreKit
import StoreKitTest
import XCTest

@testable import DoCard

@MainActor
final class StoreKitAccessTests: XCTestCase {
  private func fixture(
    _ body: (AccessFixture, SKTestSession, SubscriptionManager) async throws -> Void
  ) async throws {
    let session = try SKTestSession(configurationFileNamed: "StoreKitConfig")
    session.resetToDefaultState()
    session.clearTransactions()
    session.disableDialogs = true
    defer {
      session.clearTransactions()
      session.resetToDefaultState()
    }
    let f = try AccessFixture()
    defer { f.cleanup() }
    // StoreKit creates real-time transaction dates. Match that clock here only;
    // the access-rule and lifecycle matrices retain their fixed test clock.
    let runtime = SharedData.Runtime(
      defaults: f.defaults, signingKey: f.key,
      now: { Date() }, calendar: f.calendar)
    try await SharedData.$runtime.withValue(runtime) {
      let manager = SubscriptionManager(startAutomatically: false, scheduleExpiry: {})
      try await body(f, session, manager)
    }
  }

  func testI7LocalStoreKitPurchaseThroughProductionAdapter() async throws {
    try await fixture { _, _, manager in
      await manager.purchase(productID: SubscriptionProduct.monthly)
      XCTAssertNil(manager.errorMessage)
      XCTAssertTrue(manager.isPremium)
      XCTAssertEqual(SharedData.subscriptionGrants?.first?.productID, SubscriptionProduct.monthly)
      XCTAssertNotNil(SharedData.subscriptionAccessEnd)
    }
  }

  func testI7LocalStoreKitRestoreAfterSharedStateIsLost() async throws {
    try await fixture { _, session, manager in
      _ = try await session.buyProduct(identifier: SubscriptionProduct.annual)
      SharedData.subscriptionGrants = []
      await manager.restorePurchases()
      XCTAssertNil(manager.errorMessage)
      XCTAssertTrue(manager.isPremium)
      XCTAssertEqual(SharedData.subscriptionGrants?.first?.productID, SubscriptionProduct.annual)
    }
  }

  func testI7LocalStoreKitRefundRemovesAccess() async throws {
    try await fixture { _, session, manager in
      _ = try await session.buyProduct(identifier: SubscriptionProduct.monthly)
      await manager.checkCurrentEntitlements()
      XCTAssertTrue(manager.isPremium)
      let transaction = try XCTUnwrap(session.allTransactions().first)
      let ready = expectation(description: "Refund listener ready")
      let revoked = expectation(description: "Verified refund update received")
      let observer = Task {
        ready.fulfill()
        for await result in StoreKit.Transaction.updates {
          if case .verified(let update) = result,
            update.productID == SubscriptionProduct.monthly, update.revocationDate != nil
          {
            revoked.fulfill()
            return
          }
        }
      }
      defer { observer.cancel() }
      await fulfillment(of: [ready], timeout: 2)
      try session.refundTransaction(identifier: transaction.identifier)
      await fulfillment(of: [revoked], timeout: 5)
      await manager.checkCurrentEntitlements()
      XCTAssertFalse(manager.isPremium)
    }
  }
  func testA4LocalStoreKitCancellationKeepsPaidAccess() async throws {
    try await fixture { _, session, manager in
      _ = try await session.buyProduct(identifier: SubscriptionProduct.monthly)
      let transaction = try XCTUnwrap(session.allTransactions().first)
      try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
      await manager.checkCurrentEntitlements()
      XCTAssertTrue(manager.isPremium)
      XCTAssertNotNil(SharedData.subscriptionAccessEnd)
    }
  }

}
