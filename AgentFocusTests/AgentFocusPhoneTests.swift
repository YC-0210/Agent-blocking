import Foundation
import XCTest

@testable import AgentFocusCore

final class AgentFocusPhoneTests: XCTestCase {
  func testLowerMaximumLeavesActiveDeadlineAndEnforcesTheNewLimitOnLaterSessions() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let emergency = TestEmergencyStorage()
    let now = 1_793_836_800_000.0
    var appliedSelections: [String] = []
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage,
      now: { now }, apply: { _, selection in appliedSelections.append(selection) }, release: {})
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45, startMinute: 0,
        endMinute: 1440, timeZone: "Asia/Taipei"), selection: "unchanged-selection",
      pairingID: "phone")
    _ = try phone.receive(
      .init(
        id: "start", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "active", issuedAt: now, expiresAt: now + 60_000),
      pairingID: "phone")
    let change = try JSONDecoder().decode(
      FocusCommand.self,
      from: Data(
        """
        {"id":"lower","sequence":2,"action":"set_maximum","modeID":"work",
         "issuedAt":1793836800000,"expiresAt":1793836860000,
         "maximumMinutes":15,"expectedMaximumMinutes":45,"userConfirmed":true}
        """.utf8))
    XCTAssertEqual(try phone.receive(change, pairingID: "phone").status, "applied")
    let status = try XCTUnwrap(phone.status())
    XCTAssertEqual(status.session?.endAt, 1_793_838_600_000)
    let mode = status.policy.modeID
    _ = try phone.receive(
      .init(
        id: "stop", sequence: 3, action: .stop, modeID: mode,
        durationMinutes: nil, sessionID: "active", issuedAt: now, expiresAt: now + 60_000),
      pairingID: "phone")
    let tooLong = FocusCommand(
      id: "long", sequence: 4, action: .start, modeID: mode,
      durationMinutes: 30, sessionID: "later", issuedAt: now, expiresAt: now + 60_000)
    XCTAssertEqual(
      try phone.receive(tooLong, pairingID: "phone").reason, "duration_exceeds_approval")
    let allowed = FocusCommand(
      id: "short", sequence: 5, action: .start, modeID: mode,
      durationMinutes: 10, sessionID: "later-short", issuedAt: now, expiresAt: now + 60_000)
    XCTAssertEqual(try phone.receive(allowed, pairingID: "phone").status, "applied")
    XCTAssertEqual(appliedSelections, ["unchanged-selection", "unchanged-selection"])
  }

  func testSessionCommandsCannotAlsoChangeTheMaximum() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let emergency = TestEmergencyStorage()
    var shielded = false
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage,
      now: { 1_793_836_800_000 }, apply: { _, _ in shielded = true }, release: { shielded = false })
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45, startMinute: 0,
        endMinute: 1440, timeZone: "Asia/Taipei"), selection: "private", pairingID: "phone")
    let mixed = try JSONDecoder().decode(
      FocusCommand.self,
      from: Data(
        """
        {"id":"mixed","sequence":1,"action":"start","modeID":"work",
         "sessionID":"session","durationMinutes":30,
         "issuedAt":1793836800000,"expiresAt":1793836860000,
         "maximumMinutes":60,"expectedMaximumMinutes":45,"userConfirmed":true}
        """.utf8))
    XCTAssertEqual(try phone.receive(mixed, pairingID: "phone").status, "rejected")
    XCTAssertEqual(try phone.status()?.policy.maximumMinutes, 45)
    XCTAssertFalse(shielded)
  }

  func testConfirmedMaximumChangePersistsWithoutChangingCurrentSessionOrSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let emergency = TestEmergencyStorage()
    var installed: [String] = []
    var releases = 0
    let now = 1_793_836_800_000.0
    func makePhone() -> AgentFocusPhone<String> {
      AgentFocusPhone(
        directory: directory, emergency: emergency.storage, now: { now },
        apply: { _, selection in installed.append(selection) }, release: { releases += 1 })
    }
    let phone = makePhone()
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45, startMinute: 0,
        endMinute: 1440, timeZone: "Asia/Taipei"), selection: "private-app-tokens",
      pairingID: "phone")
    _ = try phone.receive(
      .init(
        id: "start", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "active", issuedAt: now, expiresAt: now + 60_000),
      pairingID: "phone")
    let session = try phone.status()?.session
    let change = try JSONDecoder().decode(
      FocusCommand.self,
      from: Data(
        """
        {"id":"limit","sequence":2,"action":"set_maximum","modeID":"work",
         "issuedAt":1793836800000,"expiresAt":1793836860000,
         "maximumMinutes":60,"expectedMaximumMinutes":45,"userConfirmed":true}
        """.utf8))
    XCTAssertEqual(try phone.receive(change, pairingID: "phone").status, "applied")
    XCTAssertEqual(try phone.receive(change, pairingID: "phone").status, "applied")
    let restored = try XCTUnwrap(makePhone().status())
    XCTAssertEqual(restored.policy.maximumMinutes, 60)
    XCTAssertNotEqual(restored.policy.modeID, "work")
    XCTAssertEqual(restored.policy.startMinute, 0)
    XCTAssertEqual(restored.policy.endMinute, 1440)
    XCTAssertEqual(restored.policy.timeZone, "Asia/Taipei")
    XCTAssertEqual(restored.session, session)
    XCTAssertEqual(installed, ["private-app-tokens"])
    XCTAssertEqual(releases, 0)
  }

  func testReplacingPairingResetsSequenceAndReceiptOutbox() throws {
    let emergency = TestEmergencyStorage()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var clock = 1793836800000.0
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { clock },
      apply: { _, _ in }, release: {})
    let policy = AgentFocusPolicy(
      modeID: "work", maximumMinutes: 45,
      startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei")
    try phone.approve(policy: policy, selection: "opaque-local-selection", pairingID: "old")
    let first = FocusCommand(
      id: "first", sequence: 50, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000, expiresAt: 1_793_836_860_000
    )
    _ = try phone.receive(first, pairingID: "old")
    try phone.emergencyUnlock()
    try phone.approve(policy: policy, selection: "opaque-local-selection", pairingID: "new")
    XCTAssertTrue(try phone.pendingReceipts(pairingID: "new").isEmpty)
    clock += 1000
    let fresh = FocusCommand(
      id: "fresh", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "new-s", issuedAt: 1_793_836_801_000,
      expiresAt: 1_793_836_860_000)
    XCTAssertEqual(try phone.receive(fresh, pairingID: "new").status, "applied")
    XCTAssertThrowsError(try phone.receive(fresh, pairingID: "old"))
  }

  func testPersistenceFailureCannotApplyUnownedShields() throws {
    let emergency = TestEmergencyStorage()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    var shielded = false
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { 1_793_836_800_000 },
      apply: { _, _ in shielded = true }, release: { shielded = false })
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "opaque",
      pairingID: "phone")
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    let command = FocusCommand(
      id: "first", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000, expiresAt: 1_793_836_860_000
    )
    XCTAssertThrowsError(try phone.receive(command, pairingID: "phone"))
    XCTAssertFalse(
      shielded, "No platform shields may be applied before recoverable ownership is durable")
  }

  func testEmergencyReleaseWinsOverAConcurrentShieldRestore() throws {
    let emergency = TestEmergencyStorage()
    final class Hardware: @unchecked Sendable {
      let lock = NSLock()
      let applying = DispatchSemaphore(value: 0)
      let proceed = DispatchSemaphore(value: 0)
      let released = DispatchSemaphore(value: 0)
      var shielded = false
      func install() {
        applying.signal()
        _ = proceed.wait(timeout: .now() + 5)
        lock.lock()
        shielded = true
        lock.unlock()
      }
      func clear() {
        lock.lock()
        shielded = false
        lock.unlock()
        released.signal()
      }
    }
    let hardware = Hardware()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { 1_793_836_800_000 },
      apply: { _, _ in hardware.install() }, release: { hardware.clear() })
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "opaque",
      pairingID: "phone")
    let command = FocusCommand(
      id: "first", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000, expiresAt: 1_793_836_860_000
    )
    let finished = DispatchGroup()
    finished.enter()
    DispatchQueue.global().async {
      defer { finished.leave() }
      _ = try? phone.receive(command, pairingID: "phone")
    }
    XCTAssertEqual(hardware.applying.wait(timeout: .now() + 2), .success)
    finished.enter()
    DispatchQueue.global().async {
      defer { finished.leave() }
      try? phone.emergencyUnlock()
    }
    // If the old pre-lock clear executes, wait until it has happened before allowing install.
    _ = hardware.released.wait(timeout: .now() + 0.1)
    hardware.proceed.signal()
    XCTAssertEqual(finished.wait(timeout: .now() + 3), .success)
    XCTAssertFalse(hardware.shielded, "Emergency must clear after any earlier installer finishes")
  }

  func testRecreatedPhoneExpiresLocallyAndScopesAcknowledgementsToPairing() throws {
    let emergency = TestEmergencyStorage()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var clock = 1793836800000.0
    var shielded = false
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { clock },
      apply: { _, _ in shielded = true }, release: { shielded = false })
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "opaque",
      pairingID: "phone")
    _ = try phone.receive(
      FocusCommand(
        id: "first", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "s", issuedAt: clock, expiresAt: clock + 60000),
      pairingID: "phone")
    let restored = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { clock },
      apply: { _, _ in shielded = true }, release: { shielded = false })
    clock = 1_793_838_600_000
    try restored.reconcile(authorized: true)
    XCTAssertNil(try restored.status(pairingID: "phone")?.session)
    XCTAssertFalse(shielded)
    XCTAssertTrue(try restored.status(pairingID: "phone")!.requiresRenewalApproval)
    XCTAssertThrowsError(try restored.acknowledge("first", pairingID: "other"))
    try restored.acknowledge("first", pairingID: "phone")
    XCTAssertTrue(try restored.pendingReceipts(pairingID: "phone").isEmpty)
  }

  func testRetryDoesNotReinstallPhysicalShields() throws {
    let emergency = TestEmergencyStorage()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var installations = 0
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { 1_793_836_800_000 },
      apply: { _, _ in installations += 1 }, release: {})
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "opaque",
      pairingID: "phone")
    let command = FocusCommand(
      id: "first", sequence: 1, action: .start, modeID: "work",
      durationMinutes: 30, sessionID: "s", issuedAt: 1_793_836_800_000, expiresAt: 1_793_836_860_000
    )
    _ = try phone.receive(command, pairingID: "phone")
    _ = try phone.receive(command, pairingID: "phone")
    XCTAssertEqual(installations, 1)
  }

  func testFailedEmergencyRecordWriteCannotResurrectSessionAfterRecreation() throws {
    let emergency = TestEmergencyStorage()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    var clock = 1793836800000.0
    var shielded = false
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { clock },
      apply: { _, _ in shielded = true }, release: { shielded = false })
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "opaque",
      pairingID: "phone")
    _ = try phone.receive(
      FocusCommand(
        id: "first", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "s", issuedAt: clock, expiresAt: clock + 60000),
      pairingID: "phone")
    clock += 1000
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
    XCTAssertThrowsError(try phone.emergencyUnlock())
    XCTAssertFalse(shielded)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    let restored = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage, now: { clock },
      apply: { _, _ in shielded = true }, release: { shielded = false })
    try restored.reconcile(authorized: true)
    XCTAssertFalse(
      shielded, "The canceled session must not return when the record becomes writable")
    XCTAssertNil(try restored.status(pairingID: "phone")?.session)
  }
  func testEmergencyInvalidatesUnseenCommandsWithoutDependingOnClockOrdering() throws {
    for relayOffset in [-4000.0, 4000.0] {
      let emergency = TestEmergencyStorage()
      let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
        UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: directory) }
      var clock = 1793836800000.0
      let phone = AgentFocusPhone<String>(
        directory: directory, emergency: emergency.storage,
        now: { clock }, apply: { _, _ in }, release: {})
      try phone.approve(
        policy: .init(
          modeID: "work", maximumMinutes: 45,
          startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "opaque",
        pairingID: "phone")
      let queued = FocusCommand(
        id: "queued", sequence: 1, action: .start, modeID: "work",
        durationMinutes: 30, sessionID: "old", issuedAt: clock + relayOffset,
        expiresAt: clock + 60000)
      clock += 1000
      try phone.emergencyUnlock()
      clock += 1000
      XCTAssertEqual(try phone.receive(queued, pairingID: "phone").reason, "mode_not_approved")
      let mode = try XCTUnwrap(phone.status(pairingID: "phone")?.policy.modeID)
      XCTAssertNotEqual(mode, "work")
      let fresh = FocusCommand(
        id: "fresh", sequence: 2, action: .start, modeID: mode,
        durationMinutes: 30, sessionID: "new", issuedAt: clock + relayOffset,
        expiresAt: clock + 60000)
      XCTAssertEqual(try phone.receive(fresh, pairingID: "phone").status, "applied")
    }
  }

  func testOlderKeychainCancellationCannotUndoANewerPrimaryCancellation() throws {
    let emergency = TestEmergencyStorage()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var clock = 1793836800000.0
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: emergency.storage,
      now: { clock }, apply: { _, _ in }, release: {})
    try phone.approve(
      policy: .init(
        modeID: "work", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "opaque",
      pairingID: "phone")
    clock += 1000
    try phone.emergencyUnlock()
    let firstMode = try XCTUnwrap(phone.status(pairingID: "phone")?.policy.modeID)
    clock += 1000
    _ = try phone.receive(
      FocusCommand(
        id: "first", sequence: 1, action: .start, modeID: firstMode,
        durationMinutes: 30, sessionID: "s", issuedAt: clock, expiresAt: clock + 60000),
      pairingID: "phone")
    let queued = FocusCommand(
      id: "queued", sequence: 2, action: .start, modeID: firstMode,
      durationMinutes: 30, sessionID: "old", issuedAt: clock, expiresAt: clock + 60000)
    clock += 1000
    emergency.failsWrites = true
    try phone.emergencyUnlock()
    clock += 1000
    XCTAssertEqual(try phone.receive(queued, pairingID: "phone").reason, "mode_not_approved")
    XCTAssertNotEqual(try phone.status(pairingID: "phone")?.policy.modeID, firstMode)
  }

}

private final class TestEmergencyStorage: @unchecked Sendable {
  private let lock = NSLock()
  var failsWrites = false
  private var value: AgentEmergencyCancellation?
  var storage: AgentEmergencyStorage {
    AgentEmergencyStorage(
      read: {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.value
      },
      write: { value in
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.failsWrites { throw CocoaError(.fileWriteNoPermission) }
        self.value = value
      })
  }
}
