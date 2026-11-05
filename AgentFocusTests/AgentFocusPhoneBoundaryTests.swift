import Foundation
import XCTest

@testable import AgentFocusCore

final class AgentFocusPhoneBoundaryTests: XCTestCase {
  // Each test below exercises the persisted phone API and observable native effects.
  func testDSTFullDayHoursEndAtNextLocalMidnight() throws {

    // Explicit UTC examples cover both the 23-hour and 25-hour local calendar day.
    let examples: [(String, Double)] = [
      ("2026-03-09T03:58:00Z", 1_773_028_800_000),
      ("2026-11-02T04:58:00Z", 1_793_595_600_000),
    ]
    for (instant, midnight) in examples {
      let fixture = try PhoneBoundaryFixture(zone: "America/New_York", instant: instant)
      defer { fixture.cleanup() }
      XCTAssertEqual(try fixture.receive(fixture.start(2)).status, "applied")
      XCTAssertEqual(try fixture.phone.status()?.session?.endAt, midnight)
      let overflow = try PhoneBoundaryFixture(zone: "America/New_York", instant: instant)
      defer { overflow.cleanup() }
      overflow.clock += 1
      XCTAssertEqual(try overflow.receive(overflow.start(2)).reason, "outside_approved_hours")
      XCTAssertFalse(overflow.shielded)
    }
  }

  func testFallBackFourAMBoundaryUsesWallClockRatherThanElapsedMinutes() throws {

    // Nov 1 has 25 local hours in New York. 08:58Z is 03:58 EST.
    for (instant, expectedReason) in [
      ("2026-11-01T08:58:00Z", Optional<String>.none),
      ("2026-11-01T08:59:00Z", Optional("outside_approved_hours")),
    ] {
      let fixture = try PhoneBoundaryFixture(
        start: 0, end: 240, zone: "America/New_York", instant: instant)
      defer { fixture.cleanup() }
      let receipt = try fixture.receive(fixture.start(2))
      XCTAssertEqual(receipt.reason, expectedReason)
      XCTAssertEqual(receipt.status, expectedReason == nil ? "applied" : "rejected")
      if expectedReason == nil {
        XCTAssertEqual(try fixture.phone.status()?.session?.endAt, 1_793_523_600_000)
      } else {
        XCTAssertFalse(fixture.shielded)
      }
    }
  }

  func testExpiredJournalCannotReinstallShieldsAfterReceiptSaveFailure() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    let command = try fixture.start(2)
    fixture.afterNativeApply = {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
    }
    XCTAssertThrowsError(try fixture.receive(command))
    fixture.afterNativeApply = nil
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
    fixture.clock += 120_000
    let recreated = fixture.recreate()
    try recreated.reconcile(authorized: true)
    XCTAssertNil(try recreated.status()?.session)
    XCTAssertTrue(try XCTUnwrap(recreated.status()).requiresRenewalApproval)
    XCTAssertFalse(fixture.shielded)
    XCTAssertEqual(fixture.installedSelections, ["private-app-selection"])
    XCTAssertEqual(
      try recreated.pendingReceipts(pairingID: "paired-phone").first?.reason,
      "expired_before_application")
  }

  func testJournalRecoversAfterAppliedShieldReceiptCannotBeSaved() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    let command = try fixture.start(2)
    fixture.afterNativeApply = {
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
    }
    XCTAssertThrowsError(try fixture.receive(command))
    XCTAssertTrue(fixture.shielded)
    fixture.afterNativeApply = nil
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
    let recreated = fixture.recreate()
    try recreated.reconcile(authorized: true)
    XCTAssertEqual(try recreated.status()?.session?.endAt, 1_793_836_920_000)
    XCTAssertEqual(try recreated.pendingReceipts(pairingID: "paired-phone").first?.status, "applied")
    XCTAssertEqual(try recreated.receive(command, pairingID: "paired-phone").status, "applied")
  }

  func testFailedMaximumPersistencePreservesLiveSessionAndOldPolicy() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.receive(fixture.start(30))
    let previous = try XCTUnwrap(fixture.phone.status())
    let command = try fixture.maximum(15)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o500], ofItemAtPath: fixture.directory.path)
    XCTAssertThrowsError(try fixture.receive(command))
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o700], ofItemAtPath: fixture.directory.path)
    let restored = try XCTUnwrap(fixture.recreate().status())
    XCTAssertEqual(restored.policy, previous.policy)
    XCTAssertEqual(restored.session, previous.session)
    XCTAssertTrue(fixture.shielded)
    XCTAssertEqual(fixture.installedSelections, ["private-app-selection"])
    XCTAssertEqual(try fixture.receive(command).status, "applied")
  }

  func testUnreadableEmergencyLedgerFailsClosedDuringRestoration() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.receive(fixture.start(30))
    fixture.failLedgerRead = true
    XCTAssertThrowsError(try fixture.recreate().reconcile(authorized: true))
    XCTAssertFalse(fixture.shielded)
  }

  func testAuthorizationDenialReleasesActiveSessionAndInvalidatesQueuedStart() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.receive(fixture.start(30))
    let queued = try fixture.start(2)
    try fixture.phone.reconcile(authorized: false)
    let recreated = fixture.recreate()
    XCTAssertNil(try recreated.status()?.session)
    XCTAssertFalse(fixture.shielded)
    XCTAssertNotEqual(try recreated.status()?.policy.modeID, "approved")
    XCTAssertEqual(try fixture.receive(queued).reason, "mode_not_approved")
  }

  func testQueuedMaximumCannotSurviveEmergencyModeRotation() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    let queued = try fixture.maximum(1440)
    try fixture.phone.emergencyUnlock()
    XCTAssertEqual(try fixture.receive(queued).reason, "mode_not_approved")
    XCTAssertEqual(try fixture.recreate().status()?.policy.maximumMinutes, 170)
    XCTAssertFalse(fixture.shielded)
    XCTAssertEqual(try fixture.receive(fixture.maximum(180)).status, "applied")
  }

  func testSpringForwardHoursCannotAuthorizePastFourAMWallClock() throws {
    // New York jumps from 01:59 to 03:00 on March 8, 2026.
    // 07:59 UTC is 03:59 local; a 2-minute session would finish at 04:01.
    let fixture = try PhoneBoundaryFixture(
      start: 0, end: 240, zone: "America/New_York", instant: "2026-03-08T07:59:00Z")
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(2)).reason, "outside_approved_hours")
    XCTAssertFalse(fixture.shielded)
    XCTAssertNil(try fixture.phone.status()?.session)
  }

  func testFailedNativeRestorationDurablyEndsOwnershipAndRequiresRenewal() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.receive(fixture.start(30))
    fixture.failApplication = true
    try fixture.recreate().reconcile(authorized: true)
    let restored = try XCTUnwrap(fixture.recreate().status())
    XCTAssertNil(restored.session)
    XCTAssertTrue(restored.requiresRenewalApproval)
    XCTAssertFalse(fixture.shielded)
  }

  func testMaximumChangeCannotSatisfyExpiredSessionRenewalApproval() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    _ = try fixture.receive(fixture.start(2))
    fixture.clock += 120_000
    try fixture.phone.reconcile(authorized: true)
    XCTAssertEqual(try fixture.receive(fixture.maximum(180)).status, "applied")
    XCTAssertTrue(try XCTUnwrap(fixture.recreate().status()).requiresRenewalApproval)
    XCTAssertEqual(try fixture.receive(fixture.start(2)).reason, "renewal_approval_required")
    XCTAssertEqual(try fixture.receive(fixture.start(2, renewal: true)).status, "applied")
  }

  func testPolicyTimezoneDeterminesPreviousLocalCalendarDay() throws {

    // Nov 5 at 00:00 UTC is Nov 4 at 16:00 in Los Angeles.
    let fixture = try PhoneBoundaryFixture(start: 960, end: 1020, zone: "America/Los_Angeles")
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(30)).status, "applied")
    XCTAssertEqual(try fixture.phone.status()?.session?.endAt, 1_793_838_600_000)
  }

  func testSessionCannotEndOneMillisecondPastAllowedHours() throws {

    let fixture = try PhoneBoundaryFixture(start: 540, end: 1080, instant: "2026-11-05T09:58:00Z")
    defer { fixture.cleanup() }
    fixture.clock += 1
    XCTAssertEqual(try fixture.receive(fixture.start(2)).reason, "outside_approved_hours")
    XCTAssertFalse(fixture.shielded)
  }

  func testSessionMayEndExactlyAtAllowedHoursBoundary() throws {

    let fixture = try PhoneBoundaryFixture(start: 540, end: 1080, instant: "2026-11-05T09:58:00Z")
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(2)).status, "applied")
    XCTAssertEqual(try fixture.phone.status()?.session?.endAt, 1_793_872_800_000)
  }

  func testAllowedHoursIncludeExactStartInSavedTimezone() throws {

    let fixture = try PhoneBoundaryFixture(start: 540, end: 1080, instant: "2026-11-05T01:00:00Z")
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(2)).status, "applied")
    XCTAssertEqual(try fixture.phone.status()?.session?.endAt, 1_793_840_520_000)
  }

  func testMaximumCannotCarryRenewalApproval() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    var command = try fixture.maximum(180)
    command.renewalConfirmed = true
    XCTAssertEqual(try fixture.receive(command).reason, "invalid_maximum_change")
    XCTAssertEqual(try fixture.recreate().status()?.policy.maximumMinutes, 170)
    XCTAssertFalse(fixture.shielded)
  }

  func testStaleExpectedMaximumCannotOverwritePolicy() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.maximum(180, expected: 45)).reason, "policy_changed")
    XCTAssertEqual(try fixture.recreate().status()?.policy.maximumMinutes, 170)
    XCTAssertEqual(try fixture.phone.status()?.policy.modeID, "approved")
  }

  func testMaximumRequiresExplicitConfirmation() throws {

    for confirmation: Bool? in [nil, false] {
      let fixture = try PhoneBoundaryFixture()
      defer { fixture.cleanup() }
      var command = try fixture.maximum(180)
      command.userConfirmed = confirmation
      XCTAssertEqual(try fixture.receive(command).reason, "maximum_confirmation_required")
      XCTAssertEqual(try fixture.recreate().status()?.policy.maximumMinutes, 170)
    }
  }

  func testOutOfRangeMaximumCannotChangeSavedPolicy() throws {

    for minutes in [14, 1441] {
      let fixture = try PhoneBoundaryFixture()
      defer { fixture.cleanup() }
      XCTAssertEqual(try fixture.receive(fixture.maximum(minutes)).reason, "invalid_maximum_change")
      XCTAssertEqual(try fixture.recreate().status()?.policy.maximumMinutes, 170)
      XCTAssertEqual(try fixture.phone.status()?.policy.modeID, "approved")
      XCTAssertFalse(fixture.shielded)
    }
  }

  func testMaximum1440MinutePolicyPersistsWithoutStartingSession() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.maximum(1440)).status, "applied")
    XCTAssertEqual(try fixture.recreate().status()?.policy.maximumMinutes, 1440)
    XCTAssertNil(try fixture.phone.status()?.session)
    XCTAssertTrue(fixture.installedSelections.isEmpty)
  }

  func testMinimum15MinuteMaximumPersistsWithoutStartingSession() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.maximum(15)).status, "applied")
    XCTAssertEqual(try fixture.recreate().status()?.policy.maximumMinutes, 15)
    XCTAssertNil(try fixture.phone.status()?.session)
    XCTAssertTrue(fixture.installedSelections.isEmpty)
  }

  func testOneMinuteSessionCannotInstallShields() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(1)).reason, "invalid_duration")
    XCTAssertFalse(fixture.shielded)
    XCTAssertNil(try fixture.phone.status()?.session)
  }

  func test171MinutesCannotExceed170MinuteMaximum() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(171)).reason, "duration_exceeds_approval")
    XCTAssertNil(try fixture.recreate().status()?.session)
    XCTAssertFalse(fixture.shielded)
  }

  func testExactly170MinutesFitsApprovedMaximum() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(170)).status, "applied")
    XCTAssertEqual(try fixture.recreate().status()?.session?.endAt, 1_793_847_000_000)
    XCTAssertTrue(fixture.shielded)
  }

  func testTwoMinuteDeadlineSurvivesPhoneRecreation() throws {

    let fixture = try PhoneBoundaryFixture()
    defer { fixture.cleanup() }
    XCTAssertEqual(try fixture.receive(fixture.start(2)).status, "applied")
    XCTAssertEqual(try fixture.recreate().status()?.session?.endAt, 1_793_836_920_000)
    fixture.clock += 119_999
    try fixture.phone.reconcile(authorized: true)
    XCTAssertNotNil(try fixture.phone.status()?.session)
    fixture.clock += 1
    try fixture.phone.reconcile(authorized: true)
    XCTAssertNil(try fixture.phone.status()?.session)
    XCTAssertFalse(fixture.shielded)
  }

}

private final class PhoneBoundaryFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var clock: Double
  var shielded = false
  var installedSelections: [String] = []
  var failApplication = false
  var afterNativeApply: (() throws -> Void)?
  var failLedgerRead = false
  var cancellation: AgentEmergencyCancellation?
  private var sequence = 0
  lazy var phone = recreate()

  init(
    maximum: Int = 170, start: Int = 0, end: Int = 1440,
    zone: String = "Asia/Taipei", instant: String = "2026-11-05T00:00:00Z"
  ) throws {
    clock = Self.milliseconds(instant)
    try phone.approve(
      policy: .init(
        modeID: "approved", maximumMinutes: maximum, startMinute: start,
        endMinute: end, timeZone: zone),
      selection: "private-app-selection", pairingID: "paired-phone")
  }

  static func milliseconds(_ iso: String) -> Double {
    ISO8601DateFormatter().date(from: iso)!.timeIntervalSince1970 * 1000
  }

  func recreate() -> AgentFocusPhone<String> {
    AgentFocusPhone(
      directory: directory,
      emergency: .init(
        read: {
          if self.failLedgerRead { throw CocoaError(.fileReadNoPermission) }
          return self.cancellation
        }, write: { self.cancellation = $0 }),
      now: { self.clock },
      apply: { _, selection in
        if self.failApplication { throw CocoaError(.fileWriteUnknown) }
        self.installedSelections.append(selection)
        self.shielded = true
        try self.afterNativeApply?()
      }, release: { self.shielded = false })
  }

  func start(_ minutes: Int, mode: String? = nil, renewal: Bool? = nil) throws -> FocusCommand {
    sequence += 1
    return FocusCommand(
      id: "command-\(sequence)", sequence: sequence, action: .start,
      modeID: try mode ?? XCTUnwrap(phone.status()?.policy.modeID),
      durationMinutes: minutes, sessionID: "session-\(sequence)",
      issuedAt: clock, expiresAt: clock + 60_000, renewalConfirmed: renewal)
  }

  func maximum(_ minutes: Int, expected: Int? = nil) throws -> FocusCommand {
    sequence += 1
    let policy = try XCTUnwrap(phone.status()?.policy)
    return FocusCommand(
      id: "command-\(sequence)", sequence: sequence, action: .setMaximum,
      modeID: policy.modeID, durationMinutes: nil, sessionID: nil,
      issuedAt: clock, expiresAt: clock + 60_000, maximumMinutes: minutes,
      expectedMaximumMinutes: expected ?? policy.maximumMinutes, userConfirmed: true)
  }

  @discardableResult
  func receive(_ command: FocusCommand) throws -> FocusReceipt {
    try phone.receive(command, pairingID: "paired-phone")
  }

  func cleanup() {
    try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    try? FileManager.default.removeItem(at: directory)
  }
}
