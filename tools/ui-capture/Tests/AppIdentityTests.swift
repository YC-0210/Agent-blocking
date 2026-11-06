import XCTest

/// View-only fixture: no real phone or private app tokens.
@MainActor
final class AppIdentityTests: XCTestCase {
  func testEmptyAppAssociationCannotBeConfirmedAndEmergencyUnlockRemainsAvailable() {
    let app = XCUIApplication()
    app.launchArguments = ["ended", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let manage = app.buttons["agent-focus-review-apps"]
    if !manage.isHittable { app.swipeUp() }
    XCTAssertTrue(manage.waitForExistence(timeout: 5))
    manage.tap()
    XCTAssertTrue(
      app.staticTexts["Choose exactly one app, without categories or websites."].waitForExistence(
        timeout: 5))
    let save = app.buttons["Save app for chat"]
    if !save.isHittable { app.swipeUp() }
    XCTAssertTrue(save.exists)
    XCTAssertFalse(save.isEnabled)
    XCTAssertTrue(app.buttons["Emergency Unlock"].firstMatch.exists)
    XCTAssertFalse(app.staticTexts["Saved groups"].exists)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "app-identity-empty"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
