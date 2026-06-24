import XCTest

@testable import DoCard

/// Tests for `ActiveSessionStatus` — the single in-app answer to "is a session active, for
/// which profile, and what kind?". These lock the load-bearing rules (manual beats scheduled;
/// a scheduled window counts even before it is synced into SwiftData) in one tested place.
final class ActiveSessionStatusTests: XCTestCase {

  private let manualProfile = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
  private let scheduledProfile = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!

  func testNothingActiveIsNotBlocking() {
    let status = ActiveSessionStatus.resolve(manual: nil, scheduled: nil)
    XCTAssertEqual(status.kind, .none)
    XCTAssertFalse(status.isBlocking)
    XCTAssertNil(status.activeProfileId)
  }

  func testManualSessionIsBlockingForItsProfile() {
    let status = ActiveSessionStatus.resolve(
      manual: .init(profileId: manualProfile), scheduled: nil)
    XCTAssertEqual(status.kind, .manual)
    XCTAssertTrue(status.isBlocking)
    XCTAssertEqual(status.activeProfileId, manualProfile)
  }

  // Cold start: a scheduled window counts as active even with no manual session.
  func testScheduledOnlyIsBlockingForItsProfile() {
    let status = ActiveSessionStatus.resolve(
      manual: nil, scheduled: .init(profileId: scheduledProfile))
    XCTAssertEqual(status.kind, .scheduled)
    XCTAssertTrue(status.isBlocking)
    XCTAssertEqual(status.activeProfileId, scheduledProfile)
  }

  // The load-bearing precedence: a manual / NFC session wins over a scheduled one.
  func testManualBeatsScheduled() {
    let status = ActiveSessionStatus.resolve(
      manual: .init(profileId: manualProfile),
      scheduled: .init(profileId: scheduledProfile))
    XCTAssertEqual(status.kind, .manual)
    XCTAssertEqual(status.activeProfileId, manualProfile)
  }

  func testTimerDurationSurfacedAndClassicIsNil() {
    let timer = ActiveSessionStatus.resolve(
      manual: .init(profileId: manualProfile, plannedDurationMinutes: 25), scheduled: nil)
    XCTAssertEqual(timer.plannedDurationMinutes, 25)

    let classic = ActiveSessionStatus.resolve(
      manual: .init(profileId: manualProfile), scheduled: nil)
    XCTAssertNil(classic.plannedDurationMinutes)
  }
}
