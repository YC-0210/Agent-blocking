import XCTest

final class LocalizationTests: XCTestCase {
  private func launch(_ state: String, language: String = "zh-Hant", extra: [String] = [])
    -> XCUIApplication
  {
    let app = XCUIApplication(bundleIdentifier: "online.do.agent.ui.capture")
    app.launchArguments =
      [state, "-AppleLanguages", "(\(language))", "-AppleLocale", "zh_TW"] + extra
    app.launch()
    XCTAssertTrue(app.buttons["agent-focus-emergency-unlock"].waitForExistence(timeout: 5))
    return app
  }

  private func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<6 {
      if element.isHittable { return }
      app.swipeUp()
    }
    XCTAssertTrue(element.isHittable)
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  func testTraditionalChineseHomeAndEmergencyAtLargeText() {
    continueAfterFailure = false
    let app = launch(
      "connected",
      extra: [
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
      ])
    XCTAssertEqual(app.staticTexts["agent-focus-heading"].label, "專注中")
    let unlock = app.buttons["agent-focus-emergency-unlock"]
    reveal(unlock, app: app)
    XCTAssertTrue(unlock.label.contains("緊急解鎖"))
    capture("zh-tw-large-text-emergency")
    unlock.tap()
    XCTAssertTrue(app.staticTexts["目前沒有進行中的專注。"].waitForExistence(timeout: 3))
    capture("zh-tw-idle")
    app.terminate()
  }

  func testTraditionalChineseSetupAndApplying() {
    continueAfterFailure = false
    var app = launch("setup")
    XCTAssertTrue(app.staticTexts["伺服器網址"].exists)
    XCTAssertFalse(app.buttons["agent-focus-continue"].isEnabled)
    capture("zh-tw-setup")
    app.terminate()
    app = launch("setup-limits", extra: ["invitation", "authorized"])
    let approve = app.buttons["agent-focus-connect"]
    reveal(approve, app: app)
    XCTAssertTrue(approve.label.contains("確認設定並連線"))
    XCTAssertFalse(approve.isEnabled)
    capture("zh-tw-limits")
    app.terminate()
    app = launch("applying")
    XCTAssertEqual(app.staticTexts["agent-focus-heading"].label, "正在確認\n狀態")
    XCTAssertTrue(app.staticTexts["正在套用設定…"].exists)
    capture("zh-tw-applying")
    app.terminate()
    app = launch("connected", language: "en")
    XCTAssertEqual(app.staticTexts["agent-focus-heading"].label, "FOCUS\nIS ON.")
    app.terminate()
  }
}
