import XCTest

@testable import DoCard

/// Tests for the `Entitlements` rule book — the single source of truth for
/// "what is this subscription tier allowed to do?".
///
/// These lock down the free / premium / grace-period rules so a future change
/// can't silently alter who-can-do-what (the project's most common regression).
final class EntitlementsTests: XCTestCase {

  // MARK: - Free tier

  func testFreeTierRules() {
    let free = Entitlements.forTier(.free)
    XCTAssertEqual(free.appLimit, 3, "Free tier blocks at most 3 apps")
    XCTAssertFalse(free.canBlockCategories, "Free tier cannot block whole categories")
    XCTAssertFalse(free.canBlockWebDomains, "Free tier cannot block websites")
    XCTAssertFalse(free.canSchedule, "Free tier has no scheduled automation")
    XCTAssertFalse(free.canSyncExternalDevices, "Free tier does not sync Mac / Chrome / Safari")
    XCTAssertFalse(free.canSeeDeepReport, "Free tier sees the deep report blurred")
  }

  // MARK: - Premium tier

  func testPremiumTierRules() {
    let premium = Entitlements.forTier(.premium)
    XCTAssertEqual(premium.appLimit, 50, "Premium blocks up to Apple's 50-app hard limit")
    XCTAssertTrue(premium.canBlockCategories)
    XCTAssertTrue(premium.canBlockWebDomains)
    XCTAssertTrue(premium.canSchedule)
    XCTAssertTrue(premium.canSyncExternalDevices)
    XCTAssertTrue(premium.canSeeDeepReport)
  }

  // MARK: - Constants

  func testAppLimitConstants() {
    XCTAssertEqual(Entitlements.freeAppLimit, 3)
    XCTAssertEqual(Entitlements.premiumAppLimit, 50)
  }

  // MARK: - Co-Focus (free for every tier today; slot reserved for future gating)

  func testCoFocusIsFreeForEveryTier() {
    XCTAssertTrue(Entitlements.forTier(.free).canUseCoFocus)
    XCTAssertTrue(Entitlements.forTier(.premium).canUseCoFocus)
  }

  // MARK: - Free and premium genuinely differ

  func testFreeAndPremiumDiffer() {
    let free = Entitlements.forTier(.free)
    let premium = Entitlements.forTier(.premium)
    XCTAssertNotEqual(free.appLimit, premium.appLimit)
    XCTAssertNotEqual(free.canSchedule, premium.canSchedule)
    XCTAssertNotEqual(free.canSeeDeepReport, premium.canSeeDeepReport)
  }

  // MARK: - Grace period (16-day billing grace → premium capabilities)
  //
  // The grace window lives in `SharedData.effectiveSubscriptionTier`. These tests
  // assert that `Entitlements.current` — the source both the UI gates and the
  // enforcement gate now read — grants premium capabilities throughout the window
  // and drops to free once it lapses. The shared state is saved and restored so the
  // App Group suite is left untouched.

  private var savedTier: SubscriptionTier!
  private var savedExpiration: Date?

  override func setUp() {
    super.setUp()
    savedTier = SharedData.subscriptionTier
    savedExpiration = SharedData.subscriptionExpirationDate
  }

  override func tearDown() {
    #if DEBUG
      SharedData.debugForcedTier = nil
    #endif
    SharedData.subscriptionTier = savedTier
    SharedData.subscriptionExpirationDate = savedExpiration
    super.tearDown()
  }

  private static let oneDay: TimeInterval = 24 * 60 * 60

  func testGraceWithinWindowGrantsPremiumCapabilities() {
    // Subscription lapsed 1 day ago — inside the 16-day grace window.
    SharedData.subscriptionTier = .free
    SharedData.subscriptionExpirationDate = Date().addingTimeInterval(-1 * Self.oneDay)

    XCTAssertEqual(
      SharedData.effectiveSubscriptionTier, .premium,
      "Within 16 days of lapse the effective tier is still premium")
    XCTAssertTrue(
      Entitlements.current.canSchedule,
      "A grace-period user keeps premium capabilities in the UI, not just enforcement")
    XCTAssertEqual(Entitlements.current.appLimit, 50)
  }

  func testGraceBeyondWindowDropsToFree() {
    // Subscription lapsed 20 days ago — past the 16-day grace window.
    SharedData.subscriptionTier = .free
    SharedData.subscriptionExpirationDate = Date().addingTimeInterval(-20 * Self.oneDay)

    XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free, "Past 16 days the effective tier is free")
    XCTAssertFalse(Entitlements.current.canSchedule)
    XCTAssertEqual(Entitlements.current.appLimit, 3)
  }

  func testActivePremiumGrantsPremiumCapabilities() {
    SharedData.subscriptionTier = .premium
    SharedData.subscriptionExpirationDate = Date().addingTimeInterval(30 * Self.oneDay)

    XCTAssertEqual(SharedData.effectiveSubscriptionTier, .premium)
    XCTAssertTrue(Entitlements.current.canSeeDeepReport)
    XCTAssertEqual(Entitlements.current.appLimit, 50)
  }

  // MARK: - Debug force-tier override (test builds only)

  #if DEBUG
    func testDebugForcedTierOverridesRealTier() {
      // A real premium subscriber can preview the free experience without changing
      // their subscription — the override wins at the single chokepoint, so the
      // whole app (UI gates + enforcement + extensions) sees the forced tier.
      SharedData.subscriptionTier = .premium
      SharedData.subscriptionExpirationDate = nil

      SharedData.debugForcedTier = .free
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free)
      XCTAssertEqual(Entitlements.current.appLimit, 3)
      XCTAssertFalse(Entitlements.current.canSchedule)

      SharedData.debugForcedTier = .premium
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .premium)
      XCTAssertEqual(Entitlements.current.appLimit, 50)

      SharedData.debugForcedTier = nil  // clearing returns to the real tier
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .premium)
    }
  #endif
}
