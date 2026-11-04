import XCTest

@testable import DoCard

final class AppUpdateTests: XCTestCase {
  private func configuration(_ minimum: String, enabled: Bool? = nil) -> AppUpdateConfiguration {
    AppUpdateConfiguration(minimumVersion: minimum, updateMessage: nil, enabled: enabled)
  }

  func testOlderVersionRequiresUpdate() {
    XCTAssertTrue(configuration("2.1.1").requiresUpdate(installedVersion: "2.1.0"))
  }

  func testEqualOrNewerVersionRemainsUsable() {
    XCTAssertFalse(configuration("2.1.1").requiresUpdate(installedVersion: "2.1.1"))
    XCTAssertFalse(configuration("2.1.1").requiresUpdate(installedVersion: "2.2.0"))
  }

  func testNumericComparisonAcrossMajorMinorAndPatch() {
    for (installed, minimum, required) in [
      ("2.9.0", "2.10.0", true), ("2.10.0", "2.9.0", false),
      ("2.1.9", "2.1.10", true), ("2.99.99", "3.0.0", true),
      ("1.40.0", "2.1.1", true),
    ] {
      XCTAssertEqual(configuration(minimum).requiresUpdate(installedVersion: installed), required)
    }
  }

  func testOmittedComponentsAreZero() {
    XCTAssertFalse(configuration("2.1.0").requiresUpdate(installedVersion: "2.1"))
    XCTAssertFalse(configuration("2").requiresUpdate(installedVersion: "2.0.0"))
    XCTAssertTrue(configuration("2.1").requiresUpdate(installedVersion: "2"))
  }

  func testInvalidVersionsFailOpen() {
    for invalid in [
      "", " ", "2..1", ".2", "2.", "2.1.1.1", "v2.1", "2.1-beta", "-1",
      "2.a", "２.１", "999999999999999999999999999999999999",
    ] {
      XCTAssertFalse(configuration(invalid).requiresUpdate(installedVersion: "1.0"), invalid)
      XCTAssertFalse(configuration("99.0").requiresUpdate(installedVersion: invalid), invalid)
    }
  }

  func testDisabledPolicyAllowsOlderVersion() {
    XCTAssertFalse(configuration("99.0", enabled: false).requiresUpdate(installedVersion: "1.0"))
  }

  func testExistingWebsiteJSONIsSupported() throws {
    let config = try JSONDecoder().decode(
      AppUpdateConfiguration.self,
      from: Data(
        #"{"minimumVersion":"1.40.0","updateMessage":"請更新至最新版以繼續使用 DO Card。"}"#.utf8))
    XCTAssertTrue(config.requiresUpdate(installedVersion: "1.39.0"))
    XCTAssertFalse(config.requiresUpdate(installedVersion: "2.1.0"))
  }

  func testGateWaitsForRecoveryAndAuthorization() {
    XCTAssertTrue(
      AppUpdatePolicy.shouldGate(
        updateRequired: true, isBlocking: false,
        isOnboarding: false, isAuthorized: true))
    XCTAssertFalse(
      AppUpdatePolicy.shouldGate(
        updateRequired: true, isBlocking: true,
        isOnboarding: false, isAuthorized: true), "Active focus keeps its NFC stop and emergency UI"
    )
    XCTAssertFalse(
      AppUpdatePolicy.shouldGate(
        updateRequired: true, isBlocking: false,
        isOnboarding: true, isAuthorized: true), "Onboarding finishes before gating navigation")
    XCTAssertFalse(
      AppUpdatePolicy.shouldGate(
        updateRequired: true, isBlocking: false,
        isOnboarding: false, isAuthorized: false), "Screen Time authorization remains accessible")
    XCTAssertFalse(
      AppUpdatePolicy.shouldGate(
        updateRequired: false, isBlocking: false,
        isOnboarding: false, isAuthorized: true))
  }
}
