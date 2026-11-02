import XCTest

@testable import DoCard

final class SelectionRulesTests: XCTestCase {
  func testB3AppCountBoundariesWithoutOldThreeAppLimit() {
    for (count, accepted) in [(0, true), (3, true), (4, true), (49, true), (50, true), (51, false)]
    {
      XCTAssertEqual(SelectionRules.canSave(appCount: count, hasAccess: true), accepted)
      XCTAssertFalse(SelectionRules.canSave(appCount: count, hasAccess: false))
    }
  }

  func testB4SelectionIsPreservedAndWebsitesDoNotUseAppSlots() {
    let p = SelectionRules.plan(
      apps: Set(0..<50), categories: ["social"], websites: ["example.test"],
      allowOnlyApps: false, browserEnabled: true, customDomains: ["other.test"],
      allowOnlyDomains: false, hasAccess: true)
    XCTAssertEqual(p?.apps.count, 50)
    XCTAssertEqual(p?.categories, ["social"])
    XCTAssertEqual(p?.websites, ["example.test"])
    XCTAssertEqual(p?.customDomains, ["other.test"])
    XCTAssertEqual(p?.allowOnlyApps, false)
  }

  func testB5AllowOnlyModeCannotBypassSubscription() {
    for allow in [true, false] {
      let p = SelectionRules.plan(
        apps: ["app-A"], categories: ["social"], websites: ["a.test"],
        allowOnlyApps: allow, browserEnabled: true, customDomains: ["b.test"],
        allowOnlyDomains: true, hasAccess: false)
      XCTAssertNil(p)
      let paid = SelectionRules.plan(
        apps: ["app-A"], categories: ["social"], websites: ["a.test"],
        allowOnlyApps: allow, browserEnabled: true, customDomains: [], allowOnlyDomains: false,
        hasAccess: true)
      XCTAssertEqual(paid?.allowOnlyApps, allow)
      XCTAssertEqual(paid?.apps, ["app-A"])
    }
  }

  func testB6NewPlanDropsOldSelectionAndDisabledBrowserTokens() {
    let p = SelectionRules.plan(
      apps: ["new-app"], categories: Set<String>(), websites: ["old.test"],
      allowOnlyApps: false, browserEnabled: false, customDomains: [], allowOnlyDomains: false,
      hasAccess: true)
    XCTAssertEqual(p?.apps, ["new-app"])
    XCTAssertEqual(p?.categories, [])
    XCTAssertEqual(p?.websites, [])
    XCTAssertEqual(p?.allowOnlyApps, false)
    XCTAssertEqual(p?.browserEnabled, false)
    XCTAssertEqual(p?.allowOnlyDomains, false)
  }
}
