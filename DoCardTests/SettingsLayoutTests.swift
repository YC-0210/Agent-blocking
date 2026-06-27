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
      "主畫面中央 and 我的動力 live together under 個人化 (gallery is the default centerpiece)")
  }

  // MARK: - 我的動力 is gated on the chosen centerpiece

  func testPersonalizationShowsGalleryRowOnlyWhenGallerySelected() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .personalization, cardPaired: false, centerpiece: .gallery),
      [.homeCenterpiece, .motivationGallery],
      "我的動力 appears when 動力相簿 is the chosen centerpiece")
  }

  func testPersonalizationHidesGalleryRowForCardCenterpiece() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .personalization, cardPaired: false, centerpiece: .card),
      [.homeCenterpiece],
      "我的動力 is hidden when DO 卡片 is the chosen centerpiece")
  }

  func testPersonalizationHidesGalleryRowForTasksCenterpiece() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .personalization, cardPaired: false, centerpiece: .tasks),
      [.homeCenterpiece],
      "我的動力 is hidden when 今日目標 is the chosen centerpiece")
  }

  func testDevicesHasNoSubPageRows() {
    XCTAssertEqual(
      SettingsLayout.rows(in: .devices, cardPaired: false),
      [],
      "裝置同步 is a direct link, not a hub — it has no sub-page rows (#27)")
  }

  // MARK: - Direct-link categories (no intermediate sub-page)

  func testDevicesIsADirectLink() {
    XCTAssertTrue(
      SettingsLayout.isDirectLink(.devices),
      "裝置同步 navigates straight to the pairing screen, skipping the old 連動裝置 hub (#27)")
  }

  func testOtherCategoriesAreNotDirectLinks() {
    for category in SettingsLayout.landingCategories(includeDebug: true) where category != .devices {
      XCTAssertFalse(
        SettingsLayout.isDirectLink(category),
        "Only 裝置同步 is a direct link; every other category drills into a sub-page")
    }
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

  // MARK: - centerpiece only affects the personalization sub-page

  func testCenterpieceOnlyAffectsPersonalization() {
    for category in SettingsLayout.landingCategories(includeDebug: true)
    where category != .personalization {
      XCTAssertEqual(
        SettingsLayout.rows(in: category, cardPaired: false, centerpiece: .gallery),
        SettingsLayout.rows(in: category, cardPaired: false, centerpiece: .card),
        "The centerpiece selection must only change the 個人化 sub-page")
    }
  }
}
