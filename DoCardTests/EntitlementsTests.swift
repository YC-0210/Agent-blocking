import XCTest

@testable import DoCard

final class EntitlementsTests: XCTestCase {
  func testB1UnpaidCapabilitiesAreAllDisabled() {
    let e = Entitlements.forTier(.free)
    XCTAssertEqual(e.appLimit, 0)
    XCTAssertFalse(e.canBlockCategories)
    XCTAssertFalse(e.canBlockWebDomains)
    XCTAssertFalse(e.canSchedule)
    XCTAssertFalse(e.canSeeDeepReport)
  }

  func testB1PaidCapabilitiesRemainAvailable() {
    let e = Entitlements.forTier(.premium)
    XCTAssertEqual(e.appLimit, 50)
    XCTAssertTrue(e.canBlockCategories)
    XCTAssertTrue(e.canBlockWebDomains)
    XCTAssertTrue(e.canSchedule)
    XCTAssertTrue(e.canSeeDeepReport)
  }
}
