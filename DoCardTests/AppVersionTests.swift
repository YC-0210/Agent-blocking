import XCTest

@testable import DoCard

/// Tests for `AppVersion.displayString` — the pure formatter behind the 關於
/// (About) row's version label.
final class AppVersionTests: XCTestCase {

  func testShortAndBuild() {
    XCTAssertEqual(AppVersion.displayString(short: "2.0.8", build: "42"), "2.0.8 (42)")
  }

  func testShortWithoutBuild() {
    XCTAssertEqual(AppVersion.displayString(short: "2.0.8", build: nil), "2.0.8")
    XCTAssertEqual(AppVersion.displayString(short: "2.0.8", build: ""), "2.0.8")
  }

  func testMissingShortFallsBackToDash() {
    XCTAssertEqual(AppVersion.displayString(short: nil, build: "42"), "—")
    XCTAssertEqual(AppVersion.displayString(short: "", build: "42"), "—")
    XCTAssertEqual(AppVersion.displayString(short: nil, build: nil), "—")
  }
}
