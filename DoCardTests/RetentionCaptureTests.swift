import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import DoCard

@MainActor
final class RetentionCaptureTests: XCTestCase {
  private func withFixture(_ body: (RetentionJournal, SharedData.SessionSnapshot) throws -> Void)
    throws
  {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let suiteName = "RetentionCaptureTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
      defaults.removePersistentDomain(forName: suiteName)
      try? FileManager.default.removeItem(at: directory)
    }
    let start = Date().addingTimeInterval(-7200)
    let end = start.addingTimeInterval(7200)
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "test-install", at: start, classification: "unknown")
    let runtime = SharedData.Runtime(
      defaults: defaults, signingKey: SymmetricKey(size: .bits256),
      now: { end }, calendar: Calendar(identifier: .gregorian))
    let snapshot = SharedData.SessionSnapshot(
      id: "session", tag: "DO-NOT-CAPTURE-CARD-TAG",
      blockedProfileId: UUID(), startTime: start, forceStarted: false, triggerSource: "scheduled")
    try RetentionCapture.$journalOverride.withValue(journal) {
      try SharedData.$runtime.withValue(runtime) { try body(journal, snapshot) }
    }
  }

  private func scheduledProfile(id: UUID) -> SharedData.ProfileSnapshot {
    SharedData.subscriptionTier = .premium
    SharedData.subscriptionExpirationDate = SharedData.currentDate.addingTimeInterval(86400)
    let profile = BlockedProfiles(
      id: id, name: "Scheduled retention fixture", enableAllowMode: true,
      schedules: [BlockedProfileSchedule(
        days: Weekday.allCases, startHour: 0, startMinute: 0,
        endHour: 0, endMinute: 0, isNextDay: true)])
    return BlockedProfiles.getSnapshot(for: profile)
  }

  func testRepeatedScheduledStartRecordsMissingStartAndCompletionOnce() throws {
    try withFixture { journal, snapshot in
      let profile = scheduledProfile(id: snapshot.blockedProfileId)
      SharedData.activeScheduleSharedSession = snapshot
      let activity = ScheduleTimerActivity(
        appBlocker: AppBlockerUtil(write: { _ in }), authorizationApproved: { true })
      activity.start(for: profile)
      activity.start(for: profile)
      activity.stop(for: profile)
      let state = try journal.read()
      XCTAssertEqual(state.sessions.count, 1)
      XCTAssertEqual(state.sessions[snapshot.id]?.trigger, "scheduled")
      XCTAssertEqual(state.sessions[snapshot.id]?.endReason, "timer_expired")
      XCTAssertEqual(state.contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 7200)
    }
  }

  func testBackgroundScheduledSessionRecordsUsingMainAppApprovalWithoutForegroundRecovery() throws {
    try withFixture { journal, snapshot in
      let profile = scheduledProfile(id: snapshot.blockedProfileId)
      SharedData.recordRetentionAuthorization(approved: true)
      SharedData.activeScheduleSharedSession = snapshot
      // No authorization override and no StrategyManager/foreground recovery.
      let activity = ScheduleTimerActivity(appBlocker: AppBlockerUtil(write: { _ in }))
      activity.start(for: profile)
      activity.stop(for: profile)
      XCTAssertEqual(try journal.read().sessions[snapshot.id]?.trigger, "scheduled")
      XCTAssertEqual(try journal.read().sessions[snapshot.id]?.endReason, "timer_expired")
      XCTAssertEqual(try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 7200)
    }
  }

  func testSharedRetentionAuthorizationFailsClosedAndRecordsRevocation() throws {
    try withFixture { _, _ in
      XCTAssertFalse(SharedData.retentionAuthorizationApproved)
      SharedData.recordRetentionAuthorization(approved: true)
      XCTAssertTrue(SharedData.retentionAuthorizationApproved)
      SharedData.recordRetentionAuthorization(approved: false)
      XCTAssertFalse(SharedData.retentionAuthorizationApproved)
      SharedData.storageDefaults.set(
        Data("true".utf8), forKey: "retentionAuthorizationApproved")
      XCTAssertFalse(SharedData.retentionAuthorizationApproved)
      SharedData.recordRetentionAuthorization(approved: true)
      SharedData.storageDefaults.removeObject(forKey: "retentionAuthorizationApproved.hmac")
      XCTAssertFalse(SharedData.retentionAuthorizationApproved)
    }
  }

  func testBackgroundScheduleWithoutMainAppApprovalCannotEnterCohort() throws {
    try withFixture { journal, snapshot in
      let profile = scheduledProfile(id: snapshot.blockedProfileId)
      SharedData.activeScheduleSharedSession = snapshot
      let activity = ScheduleTimerActivity(appBlocker: AppBlockerUtil(write: { _ in }))
      activity.start(for: profile)
      activity.stop(for: profile)
      XCTAssertTrue(try journal.read().sessions.isEmpty)
      XCTAssertTrue(try journal.read().contributions.isEmpty)
    }
  }

  func testRevokedSharedApprovalRejectsBackgroundScheduledStart() throws {
    try withFixture { journal, snapshot in
      let profile = scheduledProfile(id: snapshot.blockedProfileId)
      SharedData.recordRetentionAuthorization(approved: true)
      SharedData.recordRetentionAuthorization(approved: false)
      SharedData.activeScheduleSharedSession = snapshot
      let activity = ScheduleTimerActivity(appBlocker: AppBlockerUtil(write: { _ in }))
      activity.start(for: profile)
      activity.stop(for: profile)
      XCTAssertTrue(try journal.read().sessions.isEmpty)
      XCTAssertTrue(try journal.read().contributions.isEmpty)
    }
  }

  func testNewScheduledStartRecordsJournalEntry() throws {
    try withFixture { journal, snapshot in
      let profile = scheduledProfile(id: snapshot.blockedProfileId)
      let activity = ScheduleTimerActivity(
        appBlocker: AppBlockerUtil(write: { _ in }), authorizationApproved: { true })
      activity.start(for: profile)
      let active = try XCTUnwrap(SharedData.getActiveScheduleSharedSession())
      XCTAssertEqual(try journal.read().sessions[active.id]?.trigger, "scheduled")
    }
  }

  func testUnauthorizedScheduledStartCannotCreateRetentionEntry() throws {
    try withFixture { journal, snapshot in
      let profile = scheduledProfile(id: snapshot.blockedProfileId)
      SharedData.activeScheduleSharedSession = snapshot
      let activity = ScheduleTimerActivity(
        appBlocker: AppBlockerUtil(write: { _ in }), authorizationApproved: { false })
      activity.start(for: profile)
      XCTAssertTrue(try journal.read().sessions.isEmpty)
    }
  }

  func testScheduledCompletionSurvivesClearingTransientBuffer() throws {
    try withFixture { journal, snapshot in
      RetentionCapture.started(snapshot, eligible: true)
      SharedData.activeScheduleSharedSession = snapshot
      SharedData.endActiveScheduleSharedSession()
      SharedData.flushCompletedSessionsForSchedular()
      XCTAssertTrue(SharedData.getCompletedSessionsForSchedular().isEmpty)
      XCTAssertEqual(
        try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 7200)
      XCTAssertEqual(try journal.read().sessions["session"]?.trigger, "scheduled")
      let data = try JSONEncoder().encode(journal.read())
      XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("DO-NOT-CAPTURE-CARD-TAG"))
    }
  }

  func testStrategyTimerCompletionSurvivesClearingTransientBuffer() throws {
    try withFixture { journal, snapshot in
      var manual = snapshot
      manual.triggerSource = "manual"
      RetentionCapture.started(manual, eligible: true)
      SharedData.createActiveStrategySharedSession(for: manual)
      SharedData.endActiveStrategySharedSession()
      SharedData.flushCompletedSessionsForSchedular()
      XCTAssertEqual(
        try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 7200)
    }
  }

  func testSharedBreakFactsRemainExcludedWhenCompletionSnapshotLacksThem() throws {
    try withFixture { journal, snapshot in
      RetentionCapture.started(snapshot, eligible: true)
      SharedData.createActiveStrategySharedSession(for: snapshot)
      SharedData.setBreakStartTime(date: snapshot.startTime.addingTimeInterval(1000))
      SharedData.setBreakEndTime(date: snapshot.startTime.addingTimeInterval(2800))
      // A schedule-slot import can contain no break fields.
      var completed = snapshot
      completed.endTime = SharedData.currentDate
      RetentionCapture.completed(completed)
      XCTAssertEqual(
        try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 5400)
    }
  }

  func testIneligibleOrRolledBackStartDoesNotEnterCohort() throws {
    try withFixture { journal, snapshot in
      RetentionCapture.started(snapshot, eligible: false)
      SharedData.createActiveStrategySharedSession(for: snapshot)
      SharedData.flushActiveStrategySession()
      RetentionCapture.completed(snapshot)
      XCTAssertNil(try journal.read().cohort)
      XCTAssertTrue(try journal.read().sessions.isEmpty)
    }
  }

  func testStaleScheduleRecoveryStaysExcludedAfterImport() throws {
    try withFixture { journal, snapshot in
      RetentionCapture.started(snapshot, eligible: true)
      SharedData.activeScheduleSharedSession = snapshot
      SharedData.endActiveScheduleSharedSession(captureRetention: false)
      let completed = try XCTUnwrap(SharedData.getCompletedSessionsForSchedular().first)
      RetentionCapture.completed(completed)
      XCTAssertTrue(try journal.read().contributions.isEmpty)
      XCTAssertNotNil(try journal.read().cohort)
    }
  }

  func testSavedEmergencyUnlockCapturesBreakAdjustedActualTime() throws {
    try withFixture { journal, snapshot in
      let schema = Schema([BlockedProfiles.self, BlockedProfileSession.self])
      let container = try ModelContainer(
        for: schema,
        configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
      let context = ModelContext(container)
      context.autosaveEnabled = false
      let profile = BlockedProfiles(name: "Private profile name")
      context.insert(profile)
      let session = BlockedProfileSession(tag: "Private card tag", blockedProfile: profile)
      session.id = snapshot.id
      session.startTime = snapshot.startTime
      session.breakStartTime = snapshot.startTime.addingTimeInterval(1000)
      session.breakEndTime = snapshot.startTime.addingTimeInterval(2800)
      context.insert(session)
      try context.save()
      RetentionCapture.started(session.toSnapshot(), eligible: true)
      session.endSessionFully(in: context, endReason: "emergency_unlock")
      XCTAssertEqual(try journal.read().sessions[session.id]?.endReason, "emergency_unlock")
      XCTAssertEqual(
        try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 5400)
      XCTAssertFalse(session.isActive)
    }
  }
}
