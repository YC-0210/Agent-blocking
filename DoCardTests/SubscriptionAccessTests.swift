import CryptoKit
import XCTest

@testable import DoCard

final class SubscriptionAccessTests: XCTestCase {

  func testA7NoInventedGrace() {
    let name = "NoInventedGrace.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let runtime = SharedData.Runtime(
      defaults: defaults, signingKey: SymmetricKey(size: .bits256), now: { now },
      calendar: Calendar(identifier: .gregorian))
    SharedData.$runtime.withValue(runtime) {
      SharedData.subscriptionTier = .free
      SharedData.subscriptionExpirationDate = now.addingTimeInterval(-60)
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free)
    }
  }

  func testA5ExpiredSavedPremiumDoesNotGrantAccess() {
    let name = "SubscriptionAccessTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let runtime = SharedData.Runtime(
      defaults: defaults, signingKey: SymmetricKey(size: .bits256), now: { now },
      calendar: Calendar(identifier: .gregorian))
    SharedData.$runtime.withValue(runtime) {
      SharedData.subscriptionTier = .premium
      SharedData.subscriptionExpirationDate = now.addingTimeInterval(-1)
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free)
    }
  }
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func grant(_ product: String = SubscriptionProduct.monthly) -> SubscriptionGrant {
    SubscriptionGrant(
      productID: product, purchasedAt: now.addingTimeInterval(-3600),
      expiresAt: now.addingTimeInterval(3600))
  }

  func testA1NoPurchaseDoesNotGrantAccess() {
    XCTAssertNil(SubscriptionAccess.endDate(grants: [], now: now))
  }

  func testA2MonthlyAndAnnualHaveAccess() {
    for product in [SubscriptionProduct.monthly, SubscriptionProduct.annual] {
      XCTAssertEqual(
        SubscriptionAccess.endDate(grants: [grant(product)], now: now), now.addingTimeInterval(3600)
      )
    }
  }

  func testA3TrialAndRedeemedFreeOfferHaveAccessUntilTheirEnd() {
    var trial = grant()
    trial.isFreePeriod = true
    XCTAssertEqual(SubscriptionAccess.endDate(grants: [trial], now: now), trial.expiresAt)
    XCTAssertNil(SubscriptionAccess.endDate(grants: [trial], now: trial.expiresAt))
  }

  func testA5ExactExpirationBoundary() {
    let paid = grant()
    for (offset, allowed) in [(-1.0, true), (0.0, false), (1.0, false)] {
      XCTAssertEqual(
        SubscriptionAccess.endDate(grants: [paid], now: paid.expiresAt.addingTimeInterval(offset))
          != nil, allowed)
    }
  }

  func testA6OnlyVerifiedPaidGraceExtendsAccess() {
    var paid = grant()
    paid.expiresAt = now.addingTimeInterval(-60)
    paid.graceEndsAt = now.addingTimeInterval(3 * 86400 - 60)
    XCTAssertEqual(SubscriptionAccess.endDate(grants: [paid], now: now), paid.graceEndsAt)
    XCTAssertNil(SubscriptionAccess.endDate(grants: [paid], now: paid.graceEndsAt!))
    XCTAssertNil(
      SubscriptionAccess.endDate(grants: [paid], now: paid.graceEndsAt!.addingTimeInterval(1)))
  }

  func testA7ExpiredFreePeriodCannotReceiveGrace() {
    var free = grant()
    free.isFreePeriod = true
    free.expiresAt = now
    free.graceEndsAt = now.addingTimeInterval(3 * 86400)
    XCTAssertNil(SubscriptionAccess.endDate(grants: [free], now: now))
    var noGrace = grant()
    noGrace.expiresAt = now
    XCTAssertNil(SubscriptionAccess.endDate(grants: [noGrace], now: now))
  }

  func testA8OfflineDecisionUsesSavedEndIncludingConfirmedGrace() throws {
    var paid = grant()
    paid.graceEndsAt = paid.expiresAt.addingTimeInterval(3 * 86400)
    let saved = try JSONEncoder().encode([paid])
    let offline = try JSONDecoder().decode([SubscriptionGrant].self, from: saved)
    XCTAssertNotNil(
      SubscriptionAccess.endDate(grants: offline, now: paid.accessEnd.addingTimeInterval(-1)))
    XCTAssertNil(SubscriptionAccess.endDate(grants: offline, now: paid.accessEnd))
  }

  func testA9InvalidUnrelatedRevokedAndFuturePurchasesGrantNothing() {
    var unverified = grant()
    unverified.verified = false
    var revoked = grant()
    revoked.revoked = true
    var future = grant()
    future.purchasedAt = now.addingTimeInterval(1)
    for invalid in [unverified, revoked, future, grant("unrelated.product")] {
      XCTAssertNil(SubscriptionAccess.endDate(grants: [invalid], now: now))
      XCTAssertEqual(
        SubscriptionAccess.endDate(grants: [invalid, grant()], now: now), grant().expiresAt)
    }
  }

  func testA10RenewalWinsRegardlessOfArrayOrder() {
    var expired = grant()
    expired.expiresAt = now.addingTimeInterval(-1)
    for list in [[expired, grant()], [grant(), expired]] {
      XCTAssertEqual(
        SubscriptionAccess.endDate(grants: list, now: now), now.addingTimeInterval(3600))
    }
  }

  func testB2UnpaidRecoveryAndBillingActionsRemainAvailable() {
    let exceptions: [SubscriptionAction] = [
      .stopBlocking, .emergencyUnlock, .purchase, .restore, .manageSubscription, .help, .legal,
    ]
    for action in SubscriptionAction.allCases {
      XCTAssertEqual(
        SubscriptionAccess.permits(action, hasAccess: false), exceptions.contains(action))
      XCTAssertTrue(SubscriptionAccess.permits(action, hasAccess: true))
    }
  }

}
