import XCTest

@testable import DoCard

/// Tests for `DeviceSyncStrings` — the single source of truth for the
/// device-sync feature's user-facing name. The settings row and the pairing
/// screen title must read from the same constant so they can never drift, and
/// the name must be device-generic (not browser-specific) now that iPad sync
/// reuses the same pairing flow.
final class DeviceSyncStringsTests: XCTestCase {

  func testFeatureTitleIsDeviceGeneric() {
    XCTAssertEqual(
      DeviceSyncStrings.featureTitle, "裝置同步",
      "The feature is named 裝置同步 / Device Sync so it also covers iPad")
  }

  func testFeatureTitleDropsBrowserSpecificName() {
    XCTAssertNotEqual(
      DeviceSyncStrings.featureTitle, "Chrome / Safari 連動",
      "The old browser-specific name must not be the feature title anymore")
  }
}
