import XCTest

final class CaptureTests: XCTestCase {
  func snap(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }
  func launch(_ state: String, extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication(bundleIdentifier: "online.do.agent.ui.capture")
    app.launchArguments = [state, "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + extra
    app.launch()
    XCTAssertTrue(
      app.otherElements["agent-focus-brand"].waitForExistence(timeout: 5)
        || app.staticTexts["agent-focus-brand"].exists)
    return app
  }
  func reveal(_ element: XCUIElement, app: XCUIApplication) {
    for _ in 0..<5 {
      if element.isHittable { return }
      app.swipeUp()
    }
  }
  func testCaptureHomeAndEmergency() {
    continueAfterFailure = false
    for state in ["connected", "pending", "ended", "unknown", "applying", "unlock-failed"] {
      let app = launch(state)
      let unlock = app.buttons["agent-focus-emergency-unlock"]
      reveal(unlock, app: app)
      XCTAssertTrue(unlock.isHittable)
      snap("bold-\(state)")
      if state == "connected" {
        unlock.tap()
        XCTAssertTrue(app.staticTexts["No active session."].waitForExistence(timeout: 3))
        snap("bold-emergency-ended")
      }
      app.terminate()
    }
  }
  func testLargeTextAndLimitsCapture() {
    let app = launch(
      "connected",
      extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
    let unlock = app.buttons["agent-focus-emergency-unlock"]
    reveal(unlock, app: app)
    XCTAssertTrue(unlock.isHittable)
    snap("bold-large-text")
    app.terminate()
    let limits = launch("setup-limits", extra: ["invitation", "authorized"])
    let connect = limits.buttons["agent-focus-connect"]
    reveal(connect, app: limits)
    XCTAssertFalse(connect.isEnabled)
    snap("bold-setup-limits")
  }
  func testSetupGuardsAndNativePicker() {
    continueAfterFailure = false
    var app = launch("setup")
    XCTAssertFalse(app.buttons["agent-focus-continue"].isEnabled)
    snap("bold-setup-connection")
    app.terminate()
    app = launch("setup", extra: ["invitation"])
    app.buttons["agent-focus-continue"].tap()
    XCTAssertFalse(app.buttons["agent-focus-continue"].isEnabled)
    app.buttons["agent-focus-authorize"].tap()
    XCTAssertFalse(app.buttons["agent-focus-continue"].isEnabled)
    snap("bold-setup-apps")
    app.buttons["agent-focus-choose-apps"].tap()
    sleep(2)
    snap("bold-native-picker")
    // The system's all-categories checkbox has no stable identifier.
    let all = app.staticTexts["All Apps & Categories"]
    if all.exists {
      all.coordinate(withNormalizedOffset: CGVector(dx: -0.22, dy: 0.5)).tap()
      let done = app.buttons["Done"]
      if done.exists {
        done.tap()
      } else {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.90, dy: 0.11)).tap()
      }
      sleep(1)
      let next = app.buttons["agent-focus-continue"]
      if next.isEnabled {
        next.tap()
        snap("bold-setup-limits")
      }
    }
  }
}
