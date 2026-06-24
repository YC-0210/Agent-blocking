import XCTest

@testable import DoCard

/// Tests for `SuppressionRegistry` — the single owner of the schedule-suppression
/// *storage* contract (the two key prefixes, the activity-id shape, and the HMAC-signed
/// read / write / cleanup of "do-not-re-block-this-window" flags).
///
/// These lock down the storage behavior the app and its DeviceActivity extension both
/// depend on: a written flag suppresses within its window; an expired flag stops
/// suppressing and self-deletes; the two reasons are independent; the cleanup sweep
/// removes only expired flags; and — critically — the activity-id format never drifts
/// from the `DeviceActivityName` the extension passes straight into `isSuppressed`.
final class SuppressionRegistryTests: XCTestCase {

  // Fixed test identifiers so we never collide with a real profile, and can remove every
  // key we touch in tearDown (the App Group suite is shared with the real app).
  private let profileId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
  private let scheduleId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

  private var activityIdA: String {
    SuppressionRegistry.activityId(profileId: profileId, scheduleId: scheduleId, weekday: .monday)
  }
  private var activityIdB: String {
    SuppressionRegistry.activityId(profileId: profileId, scheduleId: scheduleId, weekday: .tuesday)
  }

  override func tearDown() {
    for id in [activityIdA, activityIdB] {
      for reason in [SuppressionRegistry.Reason.emergencyUnlock, .cardTap] {
        SharedData.removeSignedValue(forKey: reason.prefix + id)
      }
    }
    super.tearDown()
  }

  private static let oneHour: TimeInterval = 60 * 60

  // MARK: - Activity-id format (locks the shape the extension depends on)

  func testActivityIdFormatIsStable() {
    // The DeviceActivity extension passes its DeviceActivityName.rawValue — built as
    // "<profile>.<schedule>_<weekday>" in ScheduleTimerActivity — straight into the
    // registry. If this format drifts, the watcher silently stops honoring suppression.
    let id = SuppressionRegistry.activityId(profileId: profileId, scheduleId: scheduleId, weekday: .monday)
    XCTAssertEqual(id, "\(profileId.uuidString).\(scheduleId.uuidString)_\(Weekday.monday.rawValue)")
  }

  // MARK: - suppress / isSuppressed

  func testSuppressedWithinWindow() {
    let now = Date()
    SuppressionRegistry.suppress(
      activityId: activityIdA, reason: .emergencyUnlock, until: now.addingTimeInterval(Self.oneHour))
    XCTAssertTrue(SuppressionRegistry.isSuppressed(activityId: activityIdA, now: now))
  }

  func testNotSuppressedByDefault() {
    XCTAssertFalse(SuppressionRegistry.isSuppressed(activityId: activityIdA))
  }

  func testExpiredFlagIsNotSuppressedAndSelfDeletes() {
    let now = Date()
    SuppressionRegistry.suppress(
      activityId: activityIdA, reason: .emergencyUnlock, until: now.addingTimeInterval(-1))

    // Past its window → reports not suppressed...
    XCTAssertFalse(SuppressionRegistry.isSuppressed(activityId: activityIdA, now: now))
    // ...and the underlying key was removed as a side effect (self-healing read).
    XCTAssertNil(
      SharedData.readVerifiedDouble(
        forKey: SuppressionRegistry.Reason.emergencyUnlock.prefix + activityIdA))
  }

  func testReasonsAreIndependent() {
    let now = Date()
    SuppressionRegistry.suppress(
      activityId: activityIdA, reason: .cardTap, until: now.addingTimeInterval(Self.oneHour))

    XCTAssertTrue(
      SuppressionRegistry.isSuppressed(activityId: activityIdA, now: now),
      "A cardTap flag suppresses just like an emergencyUnlock flag")
    // The emergencyUnlock namespace for the same id was never written.
    XCTAssertNil(
      SharedData.readVerifiedDouble(
        forKey: SuppressionRegistry.Reason.emergencyUnlock.prefix + activityIdA))
  }

  // MARK: - cleanupExpired (sweeps flags that were never read back)

  func testCleanupRemovesExpiredKeepsFuture() {
    let now = Date()
    SuppressionRegistry.suppress(
      activityId: activityIdA, reason: .emergencyUnlock, until: now.addingTimeInterval(-1))  // past
    SuppressionRegistry.suppress(
      activityId: activityIdB, reason: .cardTap, until: now.addingTimeInterval(Self.oneHour))  // future

    // Both keys exist before the sweep.
    XCTAssertNotNil(
      SharedData.readVerifiedDouble(
        forKey: SuppressionRegistry.Reason.emergencyUnlock.prefix + activityIdA))
    XCTAssertNotNil(
      SharedData.readVerifiedDouble(
        forKey: SuppressionRegistry.Reason.cardTap.prefix + activityIdB))

    SuppressionRegistry.cleanupExpired(now: now)

    // The expired flag is swept; the live one survives and still suppresses.
    XCTAssertNil(
      SharedData.readVerifiedDouble(
        forKey: SuppressionRegistry.Reason.emergencyUnlock.prefix + activityIdA),
      "cleanupExpired removes a flag whose window has passed")
    XCTAssertNotNil(
      SharedData.readVerifiedDouble(
        forKey: SuppressionRegistry.Reason.cardTap.prefix + activityIdB),
      "cleanupExpired leaves a still-live flag untouched")
    XCTAssertTrue(SuppressionRegistry.isSuppressed(activityId: activityIdB, now: now))
  }
}
