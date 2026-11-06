import XCTest

/// View-only fixture: no real phone or private app tokens.
@MainActor
final class AppIdentityTests: XCTestCase {
  func testAppPickerHasOnlySelectionAndDoneWithNoIdentitySetup() {
    let app = XCUIApplication()
    app.launchArguments = ["ended", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    app.launch()
    let manage = app.buttons["agent-focus-review-apps"]
    if !manage.isHittable { app.swipeUp() }
    XCTAssertTrue(manage.waitForExistence(timeout: 5))
    manage.tap()
    XCTAssertTrue(app.navigationBars["Choose apps"].waitForExistence(timeout: 5))
    let done = app.buttons["agent-focus-picker-done"]
    XCTAssertTrue(done.exists)
    XCTAssertFalse(done.isEnabled)
    XCTAssertFalse(app.textFields["App name"].exists)
    XCTAssertFalse(app.buttons["Save app for chat"].exists)
    XCTAssertTrue(app.buttons["Emergency Unlock"].firstMatch.exists)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(manage.waitForExistence(timeout: 5))
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "pick-only-picker"
    shot.lifetime = .keepAlways
    add(shot)
  }
}
