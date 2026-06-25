import XCTest

@testable import DoCard

/// Tests for `SettingsLayout` — the pure, two-level description of the Settings
/// hub: the ordered category rows on the landing page, the rows inside each
/// category's sub-page, and whether the emergency row shows. Mirrors
/// `ActiveSessionStatusTests`: load-bearing structure locked in one tested place.
///
/// Tier is deliberately not an input — it changes labels/handlers, not which
/// categories or rows exist.
final class SettingsLayoutTests: XCTestCase {

  // MARK: - Landing categories

  func testLandingCategoriesDefault() {
    XCTAssertEqual(
      SettingsLayout.landingCategories(includeDebug: false),
      [.account, .card, .notifications, .personalization, .devices, .about],
      "The landing shows six categories in this order")
  }

  func testLandingCategoriesAppendDebugLast() {
    let categories = SettingsLayout.landingCategories(includeDebug: true)
    XCTAssertEqual(categories.last, .debug, "Debug, when present, is the last category")
    XCTAssertEqual(categories.count, 7)
  }

  // MARK: - Emergency row (landing-level, not a category)

  func testEmergencyRowOnlyWhenBlocking() {
    XCTAssertTrue(SettingsLayout.showsEmergencyRow(isBlocking: true))
    XCTAssertFalse(SettingsLayout.showsEmergencyRow(isBlocking: false))
  }

  // MARK: - Sub-page rows per category

  func testAccountRows() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .account, cardPaired: false),
      [.subscriptionStatus, .restorePurchases],
      "帳號與訂閱 shows plan status and a restore-purchases row")
  }

  func testCardRowsHideRenameUntilPaired() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .card, cardPaired: false),
      [.addCard, .cardlessStart],
      "重新命名 is hidden until a card is paired")
  }

  func testCardRowsShowRenameWhenPaired() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .card, cardPaired: true),
      [.addCard, .renameCard, .cardlessStart],
      "重新命名 appears between 新增 and 免卡開始 once paired")
  }

  func testNotificationsRows() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .notifications, cardPaired: false),
      [.liveActivity, .askToShare, .reminder])
  }

  func testPersonalizationRows() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .personalization, cardPaired: false),
      [.homeCenterpiece, .motivationGallery],
      "主畫面中央 and 動力相簿 live together under 個人化")
  }

  func testDevicesRows() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .devices, cardPaired: false),
      [.deviceSync])
  }

  func testAboutRows() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .about, cardPaired: false),
      [.version, .licenses])
  }

  func testDebugRows() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .debug, cardPaired: false),
      [.debugTier])
  }

  // MARK: - cardPaired only affects the card sub-page

  func testCardPairedDoesNotAffectOtherCategories() {
    for category in SettingsLayout.landingCategories(includeDebug: true) where category != .card {
      XCTAssertEqual(
        SettingsLayout.rows(in: category, cardPaired: false),
        SettingsLayout.rows(in: category, cardPaired: true),
        "Pairing a card must only change the DO Card sub-page")
    }
  }
}
