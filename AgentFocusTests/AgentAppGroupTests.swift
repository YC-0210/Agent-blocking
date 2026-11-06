import Foundation
import XCTest

@testable import AgentFocusCore

final class AgentAppGroupTests: XCTestCase {
  func testChangingThePrivateSelectionClearsItsPreviouslyConfirmedAppIdentity() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: .init(read: { nil }, write: { _ in }),
      now: { 1_793_836_800_000 }, apply: { _, _ in }, release: {})
    try phone.approve(
      policy: .init(
        modeID: "approved", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"), selection: "private",
      pairingID: "phone")
    try phone.saveAppGroup(
      id: "default", name: "Instagram", selection: "private", pairingID: "phone",
      iconKey: "instagram", expectedModeID: "approved")
    XCTAssertEqual(try phone.status()?.appGroups.first?.iconKey, "instagram")
    let mode = try XCTUnwrap(phone.status()?.policy.modeID)
    XCTAssertThrowsError(
      try phone.saveAppGroup(
        id: "default", name: "Bad", selection: "private",
        pairingID: "phone", iconKey: "https://invalid.test/tracker", expectedModeID: mode))
    try phone.updateSelection("different-private", pairingID: "phone", expectedModeID: mode)
    XCTAssertNil(try phone.status()?.appGroups.first?.iconKey)
    XCTAssertEqual(
      try phone.appSelection(groupID: "default", pairingID: "phone"), "different-private")
  }

  func testIdleSelectionEditorAndDefaultGroupShareTheSameSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let phone = AgentFocusPhone<String>(
      directory: directory, emergency: .init(read: { nil }, write: { _ in }),
      now: { 1_793_836_800_000 }, apply: { _, _ in }, release: {})
    try phone.approve(
      policy: .init(
        modeID: "mode", maximumMinutes: 45, startMinute: 0,
        endMinute: 1440, timeZone: "Asia/Taipei"),
      selection: "original", pairingID: "phone")
    try phone.saveAppGroup(
      id: "default", name: "Work", selection: "group-edited", pairingID: "phone",
      expectedModeID: try XCTUnwrap(phone.status()?.policy.modeID))
    let draft = try phone.editableSelection(pairingID: "phone")
    XCTAssertEqual(draft.selection, "group-edited")
    try phone.updateSelection("editor-edited", pairingID: "phone", expectedModeID: draft.modeID)
    XCTAssertEqual(try phone.appSelection(groupID: "default", pairingID: "phone"), "editor-edited")
    XCTAssertThrowsError(
      try phone.saveAppGroup(
        id: "default", name: "Stale", selection: "group-edited", pairingID: "phone",
        expectedModeID: draft.modeID))
    XCTAssertEqual(
      try phone.appSelection(groupID: "default", pairingID: "phone"), "editor-edited")
    XCTAssertEqual(try phone.status()?.appGroups.first?.name, "Work")
    let mode = try XCTUnwrap(phone.status()?.policy.modeID)
    let command = FocusCommand(
      id: "start", sequence: 1, action: .start, modeID: mode, durationMinutes: 2,
      sessionID: "session", issuedAt: 1_793_836_800_000, expiresAt: 1_793_836_860_000)
    XCTAssertEqual(try phone.receive(command, pairingID: "phone").status, "applied")
    XCTAssertThrowsError(
      try phone.updateSelection(
        "during-session", pairingID: "phone", expectedModeID: mode))
  }

  func testChosenGroupPersistsAcrossReopenAndRestoresTheSamePrivateSelection() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let emergency = AgentEmergencyStorage(read: { nil }, write: { _ in })
    let now = 1_793_836_800_000.0
    var applied: [String] = []
    func phone() -> AgentFocusPhone<String> {
      AgentFocusPhone(
        directory: directory, emergency: emergency, now: { now },
        apply: { _, selection in applied.append(selection) }, release: {})
    }
    try phone().approve(
      policy: .init(
        modeID: "approved", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"),
      selection: "private-default", pairingID: "phone")
    let group = try phone().saveAppGroup(
      name: "Deep Work", selection: "private-work", pairingID: "phone",
      expectedModeID: try XCTUnwrap(phone().status()?.policy.modeID))
    let mode = try XCTUnwrap(phone().status()?.policy.modeID)
    let start = FocusCommand(
      id: "start", sequence: 1, action: .start, modeID: mode,
      durationMinutes: 2, sessionID: "session", issuedAt: now, expiresAt: now + 60_000,
      appGroupID: group.id)
    XCTAssertEqual(try phone().receive(start, pairingID: "phone").status, "applied")
    XCTAssertEqual(applied, ["private-work"])
    XCTAssertEqual(try phone().status()?.activeAppGroupID, group.id)
    XCTAssertEqual(try phone().appSelection(groupID: group.id, pairingID: "phone"), "private-work")
    try phone().reconcile(authorized: true)
    XCTAssertEqual(applied, ["private-work", "private-work"])
    XCTAssertThrowsError(
      try phone().saveAppGroup(
        id: group.id, name: "Changed",
        selection: "different", pairingID: "phone",
        expectedModeID: try XCTUnwrap(phone().status()?.policy.modeID)))
    XCTAssertEqual(try phone().status()?.session?.endAt, now + 120_000)
  }
  func testGroupEditRotatesApprovalRejectsOldDraftAndNeverFallsBackForUnknownGroup() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    var applied: [String] = []
    let now = 1_793_836_800_000.0
    let phone = AgentFocusPhone<String>(
      directory: directory,
      emergency: .init(read: { nil }, write: { _ in }), now: { now },
      apply: { _, selection in applied.append(selection) }, release: {})
    try phone.approve(
      policy: .init(
        modeID: "old-mode", maximumMinutes: 45,
        startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei"),
      selection: "private-default", pairingID: "phone")
    XCTAssertThrowsError(try phone.appSelection(groupID: "default", pairingID: "other"))
    try phone.saveAppGroup(
      id: "default", name: "Work", selection: "private-updated", pairingID: "phone",
      expectedModeID: try XCTUnwrap(phone.status()?.policy.modeID))
    let mode = try XCTUnwrap(phone.status()?.policy.modeID)
    XCTAssertNotEqual(mode, "old-mode")
    var start = FocusCommand(
      id: "old", sequence: 1, action: .start, modeID: "old-mode",
      durationMinutes: 2, sessionID: "session", issuedAt: now, expiresAt: now + 60_000)
    XCTAssertEqual(try phone.receive(start, pairingID: "phone").reason, "mode_not_approved")
    start = FocusCommand(
      id: "missing", sequence: 2, action: .start, modeID: mode,
      durationMinutes: 2, sessionID: "session", issuedAt: now, expiresAt: now + 60_000,
      appGroupID: "not-on-phone")
    XCTAssertEqual(try phone.receive(start, pairingID: "phone").reason, "app_group_not_approved")
    XCTAssertNil(try phone.status()?.session)
    XCTAssertTrue(applied.isEmpty)
    start = FocusCommand(
      id: "legacy", sequence: 3, action: .start, modeID: mode,
      durationMinutes: 2, sessionID: "session", issuedAt: now, expiresAt: now + 60_000)
    XCTAssertEqual(try phone.receive(start, pairingID: "phone").status, "applied")
    XCTAssertEqual(applied, ["private-updated"])
    try phone.emergencyUnlock()
    XCTAssertNil(try phone.status()?.activeAppGroupID)
    XCTAssertEqual(try phone.status()?.appGroups.first?.name, "Work")
    XCTAssertEqual(
      try phone.appSelection(groupID: "default", pairingID: "phone"), "private-updated")
  }

  func testGroupMetadataValidationAndNewPairingIsolation() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let phone = AgentFocusPhone<String>(
      directory: directory,
      emergency: .init(read: { nil }, write: { _ in }), now: { 1_793_836_800_000 },
      apply: { _, _ in }, release: {})
    let policy = AgentFocusPolicy(
      modeID: "mode", maximumMinutes: 45,
      startMinute: 0, endMinute: 1440, timeZone: "Asia/Taipei")
    try phone.approve(policy: policy, selection: "first-private", pairingID: "first")
    for name in ["", " ", String(repeating: "a", count: 41), "unsafe\nname"] {
      XCTAssertThrowsError(
        try phone.saveAppGroup(
          name: name, selection: "private", pairingID: "first",
          expectedModeID: try XCTUnwrap(phone.status()?.policy.modeID)))
    }
    XCTAssertThrowsError(
      try phone.saveAppGroup(
        id: "missing", name: "Work", selection: "private", pairingID: "first",
        expectedModeID: try XCTUnwrap(phone.status()?.policy.modeID)))
    for index in 1...7 {
      try phone.saveAppGroup(
        name: "Group \(index)", selection: "private", pairingID: "first",
        expectedModeID: try XCTUnwrap(phone.status()?.policy.modeID))
    }
    XCTAssertThrowsError(
      try phone.saveAppGroup(
        name: "Ninth", selection: "private", pairingID: "first",
        expectedModeID: try XCTUnwrap(phone.status()?.policy.modeID)))
    let oldMode = try XCTUnwrap(phone.status()?.policy.modeID)
    try phone.approve(policy: policy, selection: "second-private", pairingID: "second")
    XCTAssertThrowsError(
      try phone.saveAppGroup(
        id: "default", name: "Old draft", selection: "first-private", pairingID: "second",
        expectedModeID: oldMode))
    XCTAssertEqual(try phone.status()?.appGroups, [.init(id: "default", name: "Saved apps")])
    XCTAssertEqual(
      try phone.appSelection(groupID: "default", pairingID: "second"), "second-private")
    XCTAssertThrowsError(try phone.appSelection(groupID: "default", pairingID: "first"))
  }

  func testOldPhoneRecordMigratesWithoutLosingItsSelectionOrLimits() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let oldRecord =
      #"{"pairingID":"phone","approvalID":"old","cancellationRevision":0,"policy":{"modeID":"approved","maximumMinutes":170,"startMinute":0,"endMinute":1440,"timeZone":"Asia/Taipei"},"selection":"private-legacy","state":{"lastSequence":0,"requiresRenewalApproval":false},"receipts":[]}"#
    try Data(oldRecord.utf8).write(to: directory.appendingPathComponent("agent-focus-v1.json"))
    let phone = AgentFocusPhone<String>(
      directory: directory,
      emergency: .init(read: { nil }, write: { _ in }), now: { 1_793_836_800_000 },
      apply: { _, _ in }, release: {})
    XCTAssertEqual(try phone.status()?.policy.maximumMinutes, 170)
    XCTAssertEqual(try phone.status()?.policy.modeID, "approved")
    XCTAssertEqual(try phone.status()?.appGroups, [.init(id: "default", name: "Saved apps")])
    XCTAssertEqual(try phone.appSelection(groupID: "default", pairingID: "phone"), "private-legacy")
    try phone.saveAppGroup(
      name: "Work", selection: "private-work", pairingID: "phone",
      expectedModeID: try XCTUnwrap(phone.status()?.policy.modeID))
    XCTAssertEqual(try phone.appSelection(groupID: "default", pairingID: "phone"), "private-legacy")
    XCTAssertEqual(try phone.status()?.policy.maximumMinutes, 170)
  }

}
