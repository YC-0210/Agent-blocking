import Foundation
import XCTest

@testable import AgentFocusCore

final class AgentFocusPhoneTests: XCTestCase {
  func testReplacingPairingResetsSequenceAndReceiptOutbox() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var clock = 1793836800000.0
    let phone = AgentFocusPhone<String>(
      directory: directory, now: { clock },
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: directory.path)
      try? FileManager.default.removeItem(at: directory)
    }
    var shielded = false
    let phone = AgentFocusPhone<String>(
      directory: directory, now: { 1_793_836_800_000 },
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
      directory: directory, now: { 1_793_836_800_000 },
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var clock = 1793836800000.0
    var shielded = false
    let phone = AgentFocusPhone<String>(
      directory: directory, now: { clock },
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
      directory: directory, now: { clock },
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var installations = 0
    let phone = AgentFocusPhone<String>(
      directory: directory, now: { 1_793_836_800_000 },
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
}
