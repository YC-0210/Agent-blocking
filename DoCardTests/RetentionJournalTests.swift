import Foundation
import XCTest

@testable import DoCard

final class RetentionJournalTests: XCTestCase {
  private var directory: URL!
  private let start = Date(timeIntervalSince1970: 1_793_491_200)

  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }

  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  func testFirstConfirmedStartSurvivesReopeningWithoutResettingCohort() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "existing_install")
    try journal.recordStart(
      sessionID: "first", at: start, timeZoneID: "Asia/Taipei", trigger: "manual")
    let reopened = RetentionJournal(directory: directory)
    try reopened.activate(
      installID: "different", at: start.addingTimeInterval(100), classification: "unknown")
    try reopened.recordStart(
      sessionID: "second", at: start.addingTimeInterval(100), timeZoneID: "UTC",
      trigger: "scheduled")
    let state = try reopened.read()
    XCTAssertEqual(state.installID, "install")
    XCTAssertEqual(state.cohort?.sessionID, "first")
    XCTAssertEqual(state.cohort?.timeZoneID, "Asia/Taipei")
    XCTAssertEqual(state.sessions.count, 2)
  }

  func testCompletionUsesCalculatorAndDuplicateDeliveryDoesNotAddTime() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(sessionID: "first", at: start, timeZoneID: "UTC", trigger: "manual")
    let facts = RetentionTimeCalculator.Session(
      id: "first", startTime: start,
      endTime: start.addingTimeInterval(9000), breakStartTime: start.addingTimeInterval(1000),
      breakEndTime: start.addingTimeInterval(2800))
    try journal.recordCompletion(
      facts, endReason: "emergency_unlock", asOf: start.addingTimeInterval(9000))
    try journal.recordCompletion(
      facts, endReason: "emergency_unlock", asOf: start.addingTimeInterval(10000))
    let reopened = try RetentionJournal(directory: directory).read()
    XCTAssertEqual(reopened.contributions.count, 1)
    XCTAssertEqual(reopened.contributions.values.first?.lockedSeconds, 7200)
    XCTAssertEqual(reopened.contributions.values.first?.revision, 1)
    XCTAssertEqual(reopened.sessions["first"]?.endReason, "emergency_unlock")
  }

  func testShortenedCompletionRetractsOldDayAndIncrementsRevision() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(sessionID: "first", at: start, timeZoneID: "UTC", trigger: "scheduled")
    try journal.recordCompletion(
      .init(id: "first", startTime: start, endTime: start.addingTimeInterval(172800)),
      endReason: "timer_expired", asOf: start.addingTimeInterval(200000))
    let old = try journal.read().contributions
    XCTAssertGreaterThan(old.count, 1)
    try journal.recordCompletion(
      .init(id: "first", startTime: start, endTime: start.addingTimeInterval(100)),
      endReason: "emergency_unlock", asOf: start.addingTimeInterval(200000))
    let rows = try journal.read().contributions
    XCTAssertEqual(rows.count, old.count)
    XCTAssertEqual(rows.values.reduce(0) { $0 + $1.lockedSeconds }, 100)
    XCTAssertTrue(rows.values.allSatisfy { $0.revision == 2 })
    XCTAssertTrue(rows.values.contains { $0.lockedSeconds == 0 })
  }

  func testDelayedTimerCannotReplaceEmergencyUnlock() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(sessionID: "first", at: start, timeZoneID: "UTC", trigger: "manual")
    try journal.recordCompletion(
      .init(id: "first", startTime: start, endTime: start.addingTimeInterval(100)),
      endReason: "emergency_unlock", asOf: start.addingTimeInterval(200))
    try journal.recordCompletion(
      .init(id: "first", startTime: start, endTime: start.addingTimeInterval(200)),
      endReason: "timer_expired", asOf: start.addingTimeInterval(200))
    XCTAssertEqual(try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 100)
  }

  func testPreBaselineStartAndUnregisteredCompletionStayExcluded() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(
      sessionID: "old", at: start.addingTimeInterval(-1), timeZoneID: "UTC", trigger: "manual")
    try journal.recordCompletion(
      .init(
        id: "old", startTime: start.addingTimeInterval(-1), endTime: start.addingTimeInterval(7200)),
      endReason: "card_tap", asOf: start.addingTimeInterval(7200))
    let state = try journal.read()
    XCTAssertNil(state.cohort)
    XCTAssertTrue(state.sessions.isEmpty)
    XCTAssertTrue(state.contributions.isEmpty)
  }

  func testRunningAndFutureCompletionsDoNotBecomeTime() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(sessionID: "session", at: start, timeZoneID: "UTC", trigger: "manual")
    for end: Date? in [nil, start.addingTimeInterval(8000)] {
      try journal.recordCompletion(
        .init(id: "session", startTime: start, endTime: end),
        endReason: nil, asOf: start.addingTimeInterval(7200))
    }
    XCTAssertTrue(try journal.read().contributions.isEmpty)
    XCTAssertEqual(try journal.read().sessions["session"]?.revision, 0)
  }

  func testFullyBrokenSessionRetractsPreviouslyCountedSeconds() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(sessionID: "session", at: start, timeZoneID: "UTC", trigger: "manual")
    let end = start.addingTimeInterval(7200)
    try journal.recordCompletion(
      .init(id: "session", startTime: start, endTime: end), endReason: nil, asOf: end)
    try journal.recordCompletion(
      .init(id: "session", startTime: start, endTime: end, breakStartTime: start),
      endReason: nil, asOf: end)
    XCTAssertEqual(try journal.read().contributions.values.first?.lockedSeconds, 0)
    XCTAssertEqual(try journal.read().contributions.values.first?.revision, 2)
  }

  func testConcurrentWritersKeepEverySessionAndOneCohort() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    let errors = LockedErrors()
    let directory = directory!
    let start = start
    DispatchQueue.concurrentPerform(iterations: 40) { index in
      do {
        try RetentionJournal(directory: directory).recordStart(
          sessionID: "session-\(index)",
          at: start, timeZoneID: "UTC", trigger: "scheduled")
      } catch { errors.append(error) }
    }
    XCTAssertEqual(errors.count, 0)
    XCTAssertEqual(try journal.read().sessions.count, 40)
    XCTAssertNotNil(try journal.read().cohort)
  }

  func testCorruptJournalFailsWithoutResettingBaseline() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    let url = directory.appendingPathComponent("state.json")
    let damaged = Data("damaged".utf8)
    try damaged.write(to: url)
    XCTAssertThrowsError(
      try journal.activate(installID: "replacement", at: start, classification: "unknown"))
    XCTAssertEqual(try Data(contentsOf: url), damaged)
  }

  func testMissingActivationCannotCreateCohortFromExtension() throws {
    let journal = RetentionJournal(directory: directory)
    XCTAssertThrowsError(
      try journal.recordStart(
        sessionID: "session", at: start, timeZoneID: "UTC", trigger: "scheduled"))
    XCTAssertThrowsError(try journal.read())
  }

  func testConflictingStartAndInvalidCompletionLeaveRecordedFactsIntact() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(sessionID: "session", at: start, timeZoneID: "UTC", trigger: "manual")
    XCTAssertThrowsError(
      try journal.recordStart(
        sessionID: "session", at: start.addingTimeInterval(1), timeZoneID: "UTC", trigger: "manual")
    )
    XCTAssertThrowsError(
      try journal.recordCompletion(
        .init(
          id: "session", startTime: start,
          endTime: start.addingTimeInterval(-1)), endReason: nil, asOf: start))
    XCTAssertEqual(try journal.read().sessions["session"]?.startedAt, start)
    XCTAssertTrue(try journal.read().contributions.isEmpty)
  }

  func testRecordedBreakSurvivesSnapshotWithoutBreakFields() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(
      sessionID: "session", at: start, timeZoneID: "UTC", trigger: "scheduled")
    try journal.recordBreak(
      sessionID: "session", start: start.addingTimeInterval(1000),
      end: start.addingTimeInterval(2800), asOf: start.addingTimeInterval(7200))
    try journal.recordCompletion(
      .init(id: "session", startTime: start, endTime: start.addingTimeInterval(7200)),
      endReason: "timer_expired", asOf: start.addingTimeInterval(7200))
    XCTAssertEqual(
      try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 5400)
  }

  func testAmbiguousRecoveryCannotBecomeVerifiedTimeThroughLaterImport() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(
      sessionID: "session", at: start, timeZoneID: "UTC", trigger: "scheduled")
    try journal.excludeSession(id: "session")
    try journal.recordCompletion(
      .init(id: "session", startTime: start, endTime: start.addingTimeInterval(7200)),
      endReason: "timer_expired", asOf: start.addingTimeInterval(7200))
    XCTAssertTrue(try journal.read().contributions.isEmpty)
    XCTAssertEqual(try journal.read().sessions["session"]?.isExcluded, true)
    XCTAssertNotNil(try journal.read().cohort)  // The original denominator remains fixed.
  }

  func testLateBreakFactRevisesCompletionAndDuplicateImportKeepsIt() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(
      sessionID: "session", at: start, timeZoneID: "UTC", trigger: "scheduled")
    let facts = RetentionTimeCalculator.Session(
      id: "session", startTime: start, endTime: start.addingTimeInterval(7200))
    try journal.recordCompletion(
      facts, endReason: "timer_expired", asOf: start.addingTimeInterval(7200))
    try journal.recordBreak(
      sessionID: "session", start: start.addingTimeInterval(1000),
      end: start.addingTimeInterval(2800), asOf: start.addingTimeInterval(7200))
    try journal.recordCompletion(
      facts, endReason: "timer_expired", asOf: start.addingTimeInterval(7200))
    XCTAssertEqual(
      try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 5400)
    XCTAssertEqual(try journal.read().sessions["session"]?.revision, 2)
  }

  func testStaleRecoveryDoesNotDiscardAlreadyRecordedVerifiedCompletion() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: start, classification: "unknown")
    try journal.recordStart(
      sessionID: "session", at: start, timeZoneID: "UTC", trigger: "scheduled")
    try journal.recordCompletion(
      .init(id: "session", startTime: start, endTime: start.addingTimeInterval(7200)),
      endReason: "timer_expired", asOf: start.addingTimeInterval(7200))
    try journal.excludeSession(id: "session")
    XCTAssertEqual(
      try journal.read().contributions.values.reduce(0) { $0 + $1.lockedSeconds }, 7200)
    XCTAssertEqual(try journal.read().sessions["session"]?.isExcluded, false)
  }
}

private final class LockedErrors: @unchecked Sendable {
  private let lock = NSLock()
  private var errors: [Error] = []
  func append(_ error: Error) {
    lock.lock()
    defer { lock.unlock() }
    errors.append(error)
  }
  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return errors.count
  }
}
