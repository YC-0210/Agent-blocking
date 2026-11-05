import Foundation
import XCTest

@testable import AgentFocusCore

final class AgentFocusTests: XCTestCase {
  func testPhoneRejectsSessionLongerThanApprovedLimit() throws {
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45, startMinute: 0, endMinute: 1440,
        timeZone: "Asia/Taipei"))
    let command = FocusCommand(
      id: "too-long", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 46, sessionID: "session-1", issuedAt: 1_793_836_800_000,
      expiresAt: 1_793_836_860_000)
    XCTAssertEqual(
      phone.receive(command, now: 1_793_836_800_000).reason, "duration_exceeds_approval")
    XCTAssertNil(phone.state.session)
  }
  func testApprovedSessionStartsAndExpiresWithoutAnAgent() throws {
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45, startMinute: 0, endMinute: 1440,
        timeZone: "Asia/Taipei"))
    let command = FocusCommand(
      id: "valid", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 45, sessionID: "session-1", issuedAt: 1_793_836_800_000,
      expiresAt: 1_793_836_860_000)
    XCTAssertEqual(phone.receive(command, now: 1_793_836_800_000).status, "applied")
    XCTAssertEqual(phone.state.session?.endAt, 1_793_839_500_000)
    try phone.reconcile(now: 1_793_839_500_000)
    XCTAssertNil(phone.state.session)
  }

  func testPhoneRejectsCommandsOutsideItsApprovedPolicy() {
    let policy = AgentFocusPolicy(
      modeID: "work", maximumMinutes: 45,
      startMinute: 540, endMinute: 1080, timeZone: "Asia/Taipei")
    // 2026-11-05 08:00 Taipei: before the approved 09:00 start.
    let cases: [(String, Int, Double, String)] = [
      ("other", 30, 1_793_836_800_000, "mode_not_approved"),
      ("work", 0, 1_793_836_800_000, "invalid_duration"),
      ("work", 30, 1_793_836_800_000, "outside_approved_hours"),
      ("work", 30, 1_793_871_900_000, "outside_approved_hours"),
    ]
    for (mode, minutes, now, reason) in cases {
      let phone = AgentFocusController(policy: policy)
      let command = FocusCommand(
        id: "request", sequence: 1, action: .start,
        modeID: mode, durationMinutes: minutes, sessionID: "s", issuedAt: now,
        expiresAt: now + 60000)
      XCTAssertEqual(phone.receive(command, now: now).reason, reason)
      XCTAssertNil(phone.state.session)
    }
  }

  func testPhoneRejectsExpiredAndFutureCommands() {
    for issued in [1793836700000.0, 1793836900000.0] {
      let phone = AgentFocusController(
        policy: .init(
          modeID: "work", maximumMinutes: 45,
          startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"))
      let command = FocusCommand(
        id: "late", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "s", issuedAt: issued, expiresAt: issued + 60000)
      XCTAssertEqual(
        phone.receive(command, now: 1_793_836_800_000).reason, "expired_or_future_command")
      XCTAssertNil(phone.state.session)
    }
  }

  func testStopCannotUnlockAnotherSessionAndCanUnlockOutsideApprovedHours() {
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"))
    _ = phone.receive(
      FocusCommand(
        id: "start", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000,
        expiresAt: 1_793_836_860_000),
      now: 1_793_836_800_000)
    let wrong = FocusCommand(
      id: "wrong", sequence: 2, action: .stop, modeID: "work",
      durationMinutes: nil, sessionID: "other", issuedAt: 1_793_836_801_000,
      expiresAt: 1_793_836_860_000)
    XCTAssertEqual(phone.receive(wrong, now: 1_793_836_801_000).reason, "session_mismatch")
    let stop = FocusCommand(
      id: "stop", sequence: 3, action: .stop, modeID: "work",
      durationMinutes: nil, sessionID: "s", issuedAt: 1_793_836_802_000,
      expiresAt: 1_793_836_860_000)
    XCTAssertEqual(phone.receive(stop, now: 1_793_836_802_000).status, "applied")
    XCTAssertNil(phone.state.session)
  }

  func testEmergencyUnlockRejectsReplayButAllowsANewCommandAfterRecreation() throws {
    let policy = AgentFocusPolicy(
      modeID: "work", maximumMinutes: 45,
      startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei")
    let phone = AgentFocusController(policy: policy)
    let start = FocusCommand(
      id: "start", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000, expiresAt: 1_793_836_860_000
    )
    _ = phone.receive(start, now: 1_793_836_800_000)
    try phone.emergencyUnlock()
    let restored = AgentFocusController(policy: policy, state: phone.state)
    XCTAssertEqual(restored.receive(start, now: 1_793_836_801_000).reason, "stale_command")
    let fresh = FocusCommand(
      id: "fresh", sequence: 2, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "new", issuedAt: 1_793_836_802_000,
      expiresAt: 1_793_836_860_000)
    XCTAssertEqual(restored.receive(fresh, now: 1_793_836_802_000).status, "applied")
    XCTAssertEqual(restored.state.session?.id, "new")
  }

  func testExpiredSessionRequiresExplicitRenewalApproval() throws {
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"))
    _ = phone.receive(
      FocusCommand(
        id: "start", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000,
        expiresAt: 1_793_836_860_000),
      now: 1_793_836_800_000)
    try phone.reconcile(now: 1_793_838_600_000)
    let next = FocusCommand(
      id: "next", sequence: 2, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "new", issuedAt: 1_793_838_600_000,
      expiresAt: 1_793_838_660_000)
    XCTAssertEqual(phone.receive(next, now: 1_793_838_600_000).reason, "renewal_approval_required")
    XCTAssertNil(phone.state.session)
  }

  func testFailedShieldApplicationNeverReportsApplied() {
    struct Unavailable: Error {}
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"),
      start: { _ in throw Unavailable() })
    let result = phone.receive(
      FocusCommand(
        id: "start", sequence: 1, action: .start,
        modeID: "work", durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000,
        expiresAt: 1_793_836_860_000), now: 1_793_836_800_000)
    XCTAssertEqual(result.status, "rejected")
    XCTAssertEqual(result.reason, "execution_failed")
    XCTAssertNil(phone.state.session)
  }

  func testRetryReturnsDurableReceiptWithoutStartingAgain() throws {
    let policy = AgentFocusPolicy(
      modeID: "work", maximumMinutes: 45,
      startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei")
    let phone = AgentFocusController(policy: policy)
    let command = FocusCommand(
      id: "start", sequence: 1, action: .start,
      modeID: "work", durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000,
      expiresAt: 1_793_836_860_000)
    let receipt = phone.receive(command, now: 1_793_836_800_000)
    let restored = AgentFocusController(policy: policy, state: phone.state)
    XCTAssertEqual(restored.receive(command, now: 1_793_836_801_000), receipt)
    try restored.emergencyUnlock()
    XCTAssertEqual(restored.receive(command, now: 1_793_836_802_000).reason, "stale_command")
  }

  func testQueuedStartIssuedBeforeEmergencyCannotReblockWithANewerSequence() throws {
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"))
    try phone.emergencyUnlock(now: 1_793_836_801_000)
    let command = FocusCommand(
      id: "queued", sequence: 9, action: .start,
      modeID: "work", durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000,
      expiresAt: 1_793_836_860_000)
    XCTAssertEqual(phone.receive(command, now: 1_793_836_802_000).reason, "issued_before_emergency")
    XCTAssertNil(phone.state.session)
  }

  func testRecoveryClearsSessionIfLocalExpiryCannotBeRestored() throws {
    struct Unavailable: Error {}
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"),
      state: .init(session: .init(id: "s", endAt: 1_793_839_500_000)),
      start: { _ in throw Unavailable() })
    try phone.restore(now: 1_793_836_800_000)
    XCTAssertNil(phone.state.session)
    XCTAssertTrue(phone.state.requiresRenewalApproval)
  }

  func testSmallClockSkewCannotExtendTheApprovedDuration() {
    let phone = AgentFocusController(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"))
    let command = FocusCommand(
      id: "skew", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 45, sessionID: "s", issuedAt: 1_793_836_802_000, expiresAt: 1_793_836_862_000
    )
    XCTAssertEqual(phone.receive(command, now: 1_793_836_800_000).status, "applied")
    XCTAssertEqual(phone.state.session?.endAt, 1_793_839_500_000)
  }
}
