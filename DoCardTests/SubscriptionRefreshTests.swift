import XCTest

@testable import DoCard

@MainActor
private final class DeferredAccessStore: SubscriptionStore {
  var firstRead: CheckedContinuation<[SubscriptionGrant], Error>?
  var next: [SubscriptionGrant] = []
  let started: XCTestExpectation
  init(started: XCTestExpectation) { self.started = started }
  func currentGrants() async throws -> [SubscriptionGrant] {
    if firstRead == nil {
      return try await withCheckedThrowingContinuation {
        firstRead = $0
        started.fulfill()
      }
    }
    return next
  }
  func purchase(productID: String) async throws -> SubscriptionPurchaseResult { .cancelled }
  func restore() async throws {}
}

@MainActor
final class SubscriptionRefreshTests: XCTestCase {
  func testA10OlderRefreshCannotOverwriteVerifiedRenewal() async throws {
    let f = try AccessFixture()
    defer { f.cleanup() }
    try await SharedData.$runtime.withValue(f.runtime) {
      let started = expectation(description: "First receipt read reached external store")
      let store = DeferredAccessStore(started: started)
      store.next = [
        SubscriptionGrant(
          productID: SubscriptionProduct.monthly,
          purchasedAt: f.clock.now, expiresAt: f.clock.now.addingTimeInterval(3600))
      ]
      let manager = SubscriptionManager(store: store, startAutomatically: false, scheduleExpiry: {})
      let older = Task { await manager.checkCurrentEntitlements() }
      await fulfillment(of: [started], timeout: 2)
      await manager.checkCurrentEntitlements()
      XCTAssertTrue(manager.isPremium)
      store.firstRead?.resume(returning: [])
      await older.value
      XCTAssertTrue(manager.isPremium)
      XCTAssertEqual(SharedData.subscriptionAccessEnd, f.clock.now.addingTimeInterval(3600))
    }
  }
}
