import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import DoCard

private final class HistoryBlocker: AppBlockerUtil {
  var blockRequests = 0
  override func activateRestrictions(for profile: SharedData.ProfileSnapshot) { blockRequests += 1 }
  override func deactivateRestrictions() {}
}

@MainActor
private final class HistoryFixture {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let suiteName = "SessionHistoryTests.\(UUID().uuidString)"
  let calendar: Calendar
  var container: ModelContainer?
  var context: ModelContext!
  let workID = UUID(uuidString: "53000000-0000-4000-8000-000000000001")!
  let studyID = UUID(uuidString: "53000000-0000-4000-8000-000000000002")!

  init() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
    calendar = cal
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try open()
    for (id, name) in [(workID, "Work"), (studyID, "Study")] {
      let profile = BlockedProfiles(name: name)
      profile.id = id
      context.insert(profile)
    }
    try context.save()
  }

  func open() throws {
    let configuration = ModelConfiguration(
      schema: Schema(versionedSchema: AppSchemaV5.self),
      url: directory.appendingPathComponent("history.store"), cloudKitDatabase: .none)
    container = try AppModelStore.open(configuration: configuration)
    context = ModelContext(container!)
    context.autosaveEnabled = false
  }

  func reopen() throws {
    try context.save()
    context = nil
    container = nil
    try open()
  }

  func date(hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: minute))!
  }

  var runtime: SharedData.Runtime {
    let now = date(hour: 12)
    return SharedData.Runtime(
      defaults: UserDefaults(suiteName: suiteName)!, signingKey: SymmetricKey(size: .bits256),
      now: { now }, calendar: calendar)
  }

  func snapshot(
    id: String = "work-session", profileID: UUID? = nil,
    start: Date? = nil, end: Date? = nil, reason: String? = "timer_expired"
  ) -> SharedData.SessionSnapshot {
    SharedData.SessionSnapshot(
      id: id, tag: "history-test", blockedProfileId: profileID ?? workID,
      startTime: start ?? date(hour: 9), endTime: end,
      forceStarted: false, triggerSource: "scheduled", endReason: reason)
  }

  func importSnapshot(_ snapshot: SharedData.SessionSnapshot) {
    BlockedProfileSession.upsertSessionFromSnapshot(in: context, withSnapshot: snapshot)
  }

  func cleanup() {
    context = nil
    container = nil
    UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directory)
  }
}

@MainActor
final class SessionHistoryTests: XCTestCase {
  private func withFixture(_ body: (HistoryFixture) throws -> Void) throws {
    let fixture = try HistoryFixture()
    defer { fixture.cleanup() }
    try SharedData.$runtime.withValue(fixture.runtime) { try body(fixture) }
  }

  func testS1RepeatedImportSavesOneSessionAfterReopen() throws {
    try withFixture { fixture in
      let snapshot = fixture.snapshot(end: fixture.date(hour: 9, minute: 30))
      fixture.importSnapshot(snapshot)
      fixture.importSnapshot(snapshot)
      try fixture.reopen()

      let saved = try fixture.context.fetch(FetchDescriptor<BlockedProfileSession>())
      XCTAssertEqual(saved.count, 1)
      let session = try XCTUnwrap(saved.first)
      XCTAssertEqual(session.id, snapshot.id)
      XCTAssertEqual(session.startTime, snapshot.startTime)
      XCTAssertEqual(session.endTime, snapshot.endTime)
      XCTAssertEqual(session.blockedProfile.id, fixture.workID)
      XCTAssertEqual(session.blockedProfile.sessions.map(\.id), [snapshot.id])
    }
  }

  func testS3CompletionUpdatesTheActiveRecord() throws {
    try withFixture { fixture in
      let active = fixture.snapshot(reason: nil)
      fixture.importSnapshot(active)
      try fixture.context.save()
      XCTAssertTrue(
        try XCTUnwrap(
          BlockedProfileSession.findSession(byID: active.id, in: fixture.context)
        ).isActive)

      var completed = active
      completed.endTime = fixture.date(hour: 9, minute: 30)
      completed.endReason = "timer_expired"
      fixture.importSnapshot(completed)
      try fixture.reopen()

      let saved = try fixture.context.fetch(FetchDescriptor<BlockedProfileSession>())
      XCTAssertEqual(saved.count, 1)
      let session = try XCTUnwrap(saved.first)
      XCTAssertEqual(session.id, active.id)
      XCTAssertEqual(session.startTime, active.startTime)
      XCTAssertEqual(session.endTime, completed.endTime)
      XCTAssertEqual(session.endReason, completed.endReason)
      XCTAssertFalse(session.isActive)
    }
  }

  func testS4ForegroundLoaderImportsPendingHistoryWithoutActivatingIt() throws {
    try withFixture { fixture in
      let completed = fixture.snapshot(end: fixture.date(hour: 9, minute: 30))
      SharedData.completedSessionsInSchedular = [completed]
      let blocker = HistoryBlocker()
      let manager = StrategyManager(
        appBlocker: blocker, systemEffect: { _ in }, readEmergencyUses: { 3 },
        writeEmergencyUses: { _ in })
      defer { manager.stopTimer() }

      manager.loadActiveSession(context: fixture.context)
      try fixture.context.save()
      XCTAssertTrue(SharedData.getCompletedSessionsForSchedular().isEmpty)
      manager.loadActiveSession(context: fixture.context)
      XCTAssertNil(manager.activeSession)
      XCTAssertFalse(manager.activeSessionStatus.isBlocking)
      XCTAssertEqual(blocker.blockRequests, 0)
      try fixture.reopen()
      let saved = try fixture.context.fetch(FetchDescriptor<BlockedProfileSession>())
      XCTAssertEqual(saved.count, 1)
      XCTAssertEqual(saved.first?.id, completed.id)
      XCTAssertEqual(saved.first?.endTime, completed.endTime)
    }
  }

  func testS6StaleStartCannotInflateSavedDuration() throws {
    try withFixture { fixture in
      let original = fixture.snapshot(end: fixture.date(hour: 9, minute: 30))
      fixture.importSnapshot(original)
      try fixture.context.save()
      var stale = original
      stale.startTime = fixture.date(hour: 8)
      fixture.importSnapshot(stale)
      try fixture.reopen()

      let saved = try XCTUnwrap(
        BlockedProfileSession.findSession(byID: original.id, in: fixture.context))
      XCTAssertEqual(saved.startTime, original.startTime)
      XCTAssertEqual(saved.duration, 1800, accuracy: 0.001)
    }
  }

  func testS7LateTimerCannotExtendEmergencyEndedHistory() throws {
    try withFixture { fixture in
      let emergency = fixture.snapshot(
        end: fixture.date(hour: 9, minute: 20), reason: "emergency_unlock")
      fixture.importSnapshot(emergency)
      try fixture.context.save()
      var lateTimer = emergency
      lateTimer.endTime = fixture.date(hour: 9, minute: 30)
      lateTimer.endReason = "timer_expired"
      fixture.importSnapshot(lateTimer)
      try fixture.reopen()

      let saved = try XCTUnwrap(
        BlockedProfileSession.findSession(byID: emergency.id, in: fixture.context))
      XCTAssertEqual(saved.endReason, "emergency_unlock")
      XCTAssertEqual(saved.endTime, emergency.endTime)
      XCTAssertEqual(saved.duration, 1200, accuracy: 0.001)
    }
  }

  func testS8OldActiveSnapshotCannotReopenCompletedHistory() throws {
    try withFixture { fixture in
      let completed = fixture.snapshot(
        end: fixture.date(hour: 9, minute: 20), reason: "card_tap")
      fixture.importSnapshot(completed)
      try fixture.context.save()
      var staleActive = completed
      staleActive.endTime = nil
      staleActive.endReason = nil
      fixture.importSnapshot(staleActive)
      try fixture.reopen()

      let saved = try XCTUnwrap(
        BlockedProfileSession.findSession(byID: completed.id, in: fixture.context))
      XCTAssertFalse(saved.isActive)
      XCTAssertEqual(saved.endTime, completed.endTime)
      XCTAssertEqual(saved.endReason, "card_tap")
      XCTAssertEqual(saved.duration, 1200, accuracy: 0.001)
    }
  }

  func testS2DistinctImportsKeepTheirProfilesAfterReopen() throws {
    try withFixture { fixture in
      let work = fixture.snapshot(end: fixture.date(hour: 9, minute: 30))
      let study = fixture.snapshot(
        id: "study-session", profileID: fixture.studyID, start: fixture.date(hour: 10),
        end: fixture.date(hour: 10, minute: 20))
      fixture.importSnapshot(work)
      fixture.importSnapshot(study)
      try fixture.reopen()

      let saved = try fixture.context.fetch(FetchDescriptor<BlockedProfileSession>())
      XCTAssertEqual(Set(saved.map(\.id)), Set([work.id, study.id]))
      XCTAssertEqual(saved.count, 2)
      for input in [work, study] {
        let actual = try XCTUnwrap(saved.first { $0.id == input.id })
        XCTAssertEqual(actual.blockedProfile.id, input.blockedProfileId)
        XCTAssertEqual(actual.startTime, input.startTime)
        XCTAssertEqual(actual.endTime, input.endTime)
        XCTAssertEqual(actual.blockedProfile.sessions.map(\.id), [input.id])
      }
    }
  }
}
