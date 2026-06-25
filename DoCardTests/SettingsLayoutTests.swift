import XCTest

@testable import DoCard

/// Tests for `SettingsLayout` — the single, pure description of the Settings
/// screen's structure (which sections appear, in what order, and which rows each
/// contains) given the current app state. These lock the load-bearing rules of
/// the redesign in one tested place, mirroring `ActiveSessionStatusTests`:
///   • the merged 個人化 group (centerpiece + gallery),
///   • 重新命名 only after a card is paired,
///   • 緊急解鎖 only while blocking (between 連動裝置 and 關於),
///   • Debug only in debug builds (always last),
///   • 連動裝置 and 關於 always present.
///
/// Tier is deliberately not an input: it changes labels/handlers, not which rows
/// exist or their order.
final class SettingsLayoutTests: XCTestCase {

  // MARK: - Default state

  func testDefaultOrderAndRows() {
    let sections = SettingsLayout.resolve(
      cardPaired: false, isBlocking: false, includeDebug: false)

    XCTAssertEqual(
      sections.map(\.id),
      [.subscription, .card, .personalization, .notifications, .devices, .about],
      "Default settings show six groups in this order")

    let card = sections.first { $0.id == .card }
    XCTAssertEqual(
      card?.rows, [.addCard, .cardlessStart],
      "重新命名 stays hidden until a card is paired")
  }

  // MARK: - 重新命名 visibility

  func testRenameAppearsWhenCardPaired() {
    let sections = SettingsLayout.resolve(
      cardPaired: true, isBlocking: false, includeDebug: false)

    let card = sections.first { $0.id == .card }
    XCTAssertEqual(
      card?.rows, [.addCard, .renameCard, .cardlessStart],
      "重新命名 appears after 新增 and before 免卡開始 once paired")
  }

  // MARK: - 個人化 merge

  func testPersonalizationMergesCenterpieceAndGallery() {
    let sections = SettingsLayout.resolve(
      cardPaired: false, isBlocking: false, includeDebug: false)

    let personalization = sections.first { $0.id == .personalization }
    XCTAssertEqual(
      personalization?.rows, [.homeCenterpiece, .motivationGallery],
      "主畫面中央 and 動力相簿 are merged into one 個人化 group")
  }

  // MARK: - 通知與提醒

  func testNotificationsHaveThreeToggles() {
    let sections = SettingsLayout.resolve(
      cardPaired: false, isBlocking: false, includeDebug: false)

    let notifications = sections.first { $0.id == .notifications }
    XCTAssertEqual(
      notifications?.rows, [.liveActivity, .askToShare, .reminder])
  }

  // MARK: - 連動裝置 always present (not tier-gated for visibility)

  func testDeviceSyncAlwaysPresent() {
    let sections = SettingsLayout.resolve(
      cardPaired: false, isBlocking: false, includeDebug: false)
    XCTAssertEqual(
      sections.first { $0.id == .devices }?.rows, [.deviceSync],
      "連動裝置 row always shows — free taps open the paywall")
  }

  // MARK: - 緊急解鎖 visibility + position

  func testEmergencyHiddenWhenNotBlocking() {
    let ids = SettingsLayout.resolve(
      cardPaired: false, isBlocking: false, includeDebug: false).map(\.id)
    XCTAssertFalse(ids.contains(.emergency))
  }

  func testEmergencyAppearsWhenBlockingBetweenDevicesAndAbout() {
    let ids = SettingsLayout.resolve(
      cardPaired: false, isBlocking: true, includeDebug: false).map(\.id)

    XCTAssertTrue(ids.contains(.emergency), "緊急解鎖 shows during an active focus")
    let devices = ids.firstIndex(of: .devices)
    let emergency = ids.firstIndex(of: .emergency)
    let about = ids.firstIndex(of: .about)
    XCTAssertNotNil(devices)
    XCTAssertNotNil(emergency)
    XCTAssertNotNil(about)
    XCTAssertTrue(
      devices! < emergency! && emergency! < about!,
      "緊急解鎖 sits after 連動裝置 and before 關於")
  }

  // MARK: - 關於 always present

  func testAboutAlwaysHasVersionAndLicenses() {
    for blocking in [true, false] {
      let sections = SettingsLayout.resolve(
        cardPaired: false, isBlocking: blocking, includeDebug: false)
      let about = sections.first { $0.id == .about }
      XCTAssertEqual(
        about?.rows, [.version, .licenses],
        "關於 always shows the version and a Licenses link")
    }
  }

  // MARK: - Debug section

  func testNoDebugByDefault() {
    let ids = SettingsLayout.resolve(
      cardPaired: false, isBlocking: false, includeDebug: false).map(\.id)
    XCTAssertFalse(ids.contains(.debug))
  }

  func testDebugSectionIsLastWhenIncluded() {
    let ids = SettingsLayout.resolve(
      cardPaired: false, isBlocking: false, includeDebug: true).map(\.id)
    XCTAssertEqual(ids.last, .debug, "Debug, when present, is always the last section")
  }

  // MARK: - Full snapshot

  func testFullOrderWithEverythingEnabled() {
    let ids = SettingsLayout.resolve(
      cardPaired: true, isBlocking: true, includeDebug: true).map(\.id)
    XCTAssertEqual(
      ids,
      [.subscription, .card, .personalization, .notifications, .devices, .emergency, .about, .debug],
      "The complete section order with every conditional enabled")
  }
}
