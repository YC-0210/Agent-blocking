import Foundation
import XCTest

@testable import DoCard

final class RetentionTimeCalculatorTests: XCTestCase {
  private func date(_ value: String) -> Date {
    ISO8601DateFormatter().date(from: value)!
  }

  private func taipeiCohort() throws -> RetentionTimeCalculator.Cohort {
    try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-11-01T09:00:00+08:00"), timeZoneID: "Asia/Taipei")
  }

  func testInvalidSessionIsReportedInsteadOfBecomingZeroUsage() throws {
    let session = RetentionTimeCalculator.Session(
      id: "reversed", startTime: date("2026-11-01T11:00:00+08:00"),
      endTime: date("2026-11-01T09:00:00+08:00"))
    XCTAssertThrowsError(
      try RetentionTimeCalculator.contributions(
        for: session, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00")))
  }

  func testInvalidTimeZoneAndNonFiniteDatesAreRejected() throws {
    XCTAssertThrowsError(
      try RetentionTimeCalculator.Cohort(
        startedAt: date("2026-11-01T09:00:00+08:00"), timeZoneID: "Not/A_TimeZone"))
    XCTAssertThrowsError(
      try RetentionTimeCalculator.Cohort(
        startedAt: Date(timeIntervalSince1970: .nan), timeZoneID: "Asia/Taipei"))
    let invalid = RetentionTimeCalculator.Session(
      id: "nan", startTime: Date(timeIntervalSince1970: .nan), endTime: nil)
    XCTAssertThrowsError(
      try RetentionTimeCalculator.contributions(
        for: invalid, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00")))
    XCTAssertThrowsError(
      try RetentionTimeCalculator.periods(
        for: [], cohort: taipeiCohort(), asOf: Date(timeIntervalSince1970: .infinity)))
  }

  func testMalformedBreakIsNotSilentlyCountedAsLockedTime() throws {
    let start = date("2026-11-01T09:00:00+08:00")
    let cases: [(Date?, Date?)] = [
      (nil, start.addingTimeInterval(1800)),
      (start.addingTimeInterval(3600), start.addingTimeInterval(1800)),
    ]
    for (breakStart, breakEnd) in cases {
      let session = RetentionTimeCalculator.Session(
        id: "bad-break", startTime: start, endTime: start.addingTimeInterval(7200),
        breakStartTime: breakStart, breakEndTime: breakEnd)
      XCTAssertThrowsError(
        try RetentionTimeCalculator.contributions(
          for: session, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00")))
    }
  }

  func testZeroLengthSessionAndTimeBeforeEntryProduceNoUsage() throws {
    let start = date("2026-11-01T09:00:00+08:00")
    XCTAssertTrue(
      try RetentionTimeCalculator.contributions(
        for: .init(id: "zero", startTime: start, endTime: start), cohort: taipeiCohort(),
        asOf: date("2026-11-04T00:00:00+08:00")
      ).isEmpty)
    XCTAssertTrue(
      try RetentionTimeCalculator.periods(
        for: [], cohort: taipeiCohort(), asOf: date("2026-11-01T08:00:00+08:00")
      ).isEmpty)
  }

  func testLateFirstSessionDateStillStartsPeriodOneAtMidnight() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-11-01T23:00:00+08:00"), timeZoneID: "Asia/Taipei")
    let periods = try RetentionTimeCalculator.periods(
      for: [], cohort: cohort, asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(periods.first?.startTime, date("2026-11-01T00:00:00+08:00"))
    XCTAssertEqual(periods.first?.endTime, date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(periods.first?.isActive, false)
  }

  func testLongFinishedSessionSplitsEveryDayWithoutLosingSeconds() throws {
    let session = RetentionTimeCalculator.Session(
      id: "long", startTime: date("2026-11-01T23:00:00+08:00"),
      endTime: date("2026-11-05T01:00:00+08:00"))
    let contributions = try RetentionTimeCalculator.contributions(
      for: session, cohort: taipeiCohort(), asOf: date("2026-11-06T00:00:00+08:00"))
    XCTAssertEqual(contributions.map(\.lockedSeconds), [3600, 86400, 86400, 86400, 3600])
    XCTAssertEqual(contributions.map(\.periodIndex), [1, 1, 1, 2, 2])
    XCTAssertEqual(contributions.first?.key, "long:2026-11-01")
  }

  func testMatchesSixInstallPostHogProof() throws {
    // Same worked example as the saved PostHog proof, shifted to November 1.
    let fixtures: [[[String]]] = [
      [
        ["a1", "2026-11-01T09:00:00+08:00", "2026-11-01T11:00:00+08:00"],
        ["a3", "2026-11-07T09:00:00+08:00", "2026-11-07T11:00:00+08:00"],
      ],
      [
        ["b1", "2026-11-01T09:00:00+08:00", "2026-11-01T09:40:00+08:00"],
        ["b2", "2026-11-02T09:00:00+08:00", "2026-11-02T09:50:00+08:00"],
        ["b3", "2026-11-03T09:00:00+08:00", "2026-11-03T09:30:00+08:00"],
        ["b4", "2026-11-04T09:00:00+08:00", "2026-11-04T10:59:59+08:00"],
        ["b5", "2026-11-07T09:00:00+08:00", "2026-11-07T11:00:00+08:00"],
      ],
      [
        ["c1", "2026-11-01T09:00:00+08:00", "2026-11-01T10:59:59+08:00"],
        ["c2", "2026-11-04T09:00:00+08:00", "2026-11-04T10:00:00+08:00"],
      ],
      [
        ["d1", "2026-11-01T23:00:00+08:00", "2026-11-01T23:30:00+08:00"],
        ["d2", "2026-11-03T23:00:00+08:00", "2026-11-04T01:00:00+08:00"],
        ["d3", "2026-11-04T02:00:00+08:00", "2026-11-04T03:00:00+08:00"],
      ],
      [["e1", "2026-11-03T22:00:00+08:00", "2026-11-04T02:00:00+08:00"]],
      [],
    ]
    var activeCounts = [0, 0, 0, 0]
    for fixture in fixtures {
      let sessions = fixture.map {
        RetentionTimeCalculator.Session(id: $0[0], startTime: date($0[1]), endTime: date($0[2]))
      }
      let periods = try RetentionTimeCalculator.periods(
        for: sessions, cohort: taipeiCohort(), asOf: date("2026-11-13T00:00:00+08:00"))
      for (index, period) in periods.prefix(4).enumerated() where period.isActive == true {
        activeCounts[index] += 1
      }
    }
    XCTAssertEqual(activeCounts, [3, 2, 2, 0])
  }

  func testOneDayCanQualifyWithoutDailyUse() throws {
    let session = RetentionTimeCalculator.Session(
      id: "scheduled-emergency-unlock", startTime: date("2026-11-02T10:00:00+08:00"),
      endTime: date("2026-11-02T12:00:00+08:00"))
    let periods = try RetentionTimeCalculator.periods(
      for: [session], cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(periods.first?.lockedSeconds, 7200)
    XCTAssertEqual(periods.first?.isActive, true)
  }

  func testFractionBelowTwoHoursDoesNotRoundUp() throws {
    let start = date("2026-11-01T09:00:00+08:00")
    let session = RetentionTimeCalculator.Session(
      id: "below", startTime: start, endTime: start.addingTimeInterval(7199.999))
    let periods = try RetentionTimeCalculator.periods(
      for: [session], cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(periods.first?.isActive, false)
    XCTAssertLessThan(try XCTUnwrap(periods.first?.lockedSeconds), 7200)
  }

  func testRunningAndNotYetFinishedSessionsContributeNoTime() throws {
    let start = date("2026-11-01T09:00:00+08:00")
    let sessions = [
      RetentionTimeCalculator.Session(id: "running", startTime: start, endTime: nil),
      RetentionTimeCalculator.Session(
        id: "future-end", startTime: start,
        endTime: date("2026-11-05T00:00:00+08:00")),
    ]
    let periods = try RetentionTimeCalculator.periods(
      for: sessions, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(periods.map(\.lockedSeconds), [0, 0])
    XCTAssertEqual(periods.map(\.isActive), [false, nil])
  }

  func testSessionAlreadyRunningAtEntryIsExcludedEntirely() throws {
    let session = RetentionTimeCalculator.Session(
      id: "pre-baseline", startTime: date("2026-10-31T22:00:00+08:00"),
      endTime: date("2026-11-01T12:00:00+08:00"))
    XCTAssertTrue(
      try RetentionTimeCalculator.contributions(
        for: session, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00")
      ).isEmpty)
  }

  func testSessionEndingAtMidnightDoesNotAddTimeToNextDay() throws {
    let session = RetentionTimeCalculator.Session(
      id: "boundary", startTime: date("2026-11-03T22:00:00+08:00"),
      endTime: date("2026-11-04T00:00:00+08:00"))
    let contributions = try RetentionTimeCalculator.contributions(
      for: session, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(contributions.map(\.localDate), ["2026-11-03"])
    XCTAssertEqual(contributions.map(\.lockedSeconds), [7200])
  }

  func testLateCompletionRecalculatesEarlierPeriod() throws {
    let session = RetentionTimeCalculator.Session(
      id: "late", startTime: date("2026-11-03T22:00:00+08:00"),
      endTime: date("2026-11-04T02:00:00+08:00"))
    let before = try RetentionTimeCalculator.periods(
      for: [session], cohort: taipeiCohort(), asOf: date("2026-11-04T01:00:00+08:00"))
    let after = try RetentionTimeCalculator.periods(
      for: [session], cohort: taipeiCohort(), asOf: date("2026-11-04T03:00:00+08:00"))
    XCTAssertEqual(before.map(\.lockedSeconds), [0, 0])
    XCTAssertEqual(after.map(\.lockedSeconds), [7200, 7200])
    XCTAssertEqual(after.map(\.isActive), [true, nil])
  }

  func testUserCanReturnAfterMissingAPeriod() throws {
    let sessions = [
      RetentionTimeCalculator.Session(
        id: "first", startTime: date("2026-11-01T09:00:00+08:00"),
        endTime: date("2026-11-01T11:00:00+08:00")),
      RetentionTimeCalculator.Session(
        id: "returned", startTime: date("2026-11-07T09:00:00+08:00"),
        endTime: date("2026-11-07T11:00:00+08:00")),
    ]
    let periods = try RetentionTimeCalculator.periods(
      for: sessions, cohort: taipeiCohort(), asOf: date("2026-11-10T00:00:00+08:00"))
    XCTAssertEqual(periods.map(\.isActive), [true, false, true, nil])
  }

  func testThresholdReachedInUnfinishedPeriodStillShowsPending() throws {
    let session = RetentionTimeCalculator.Session(
      id: "early", startTime: date("2026-11-01T09:00:00+08:00"),
      endTime: date("2026-11-01T11:00:00+08:00"))
    let periods = try RetentionTimeCalculator.periods(
      for: [session], cohort: taipeiCohort(), asOf: date("2026-11-01T12:00:00+08:00"))
    XCTAssertEqual(periods.first?.lockedSeconds, 7200)
    XCTAssertFalse(try XCTUnwrap(periods.first?.isComplete))
    XCTAssertNil(try XCTUnwrap(periods.first).isActive)
  }

  func testOpenBreakExcludesTimeThroughSessionEnd() throws {
    let session = RetentionTimeCalculator.Session(
      id: "open-break", startTime: date("2026-11-01T09:00:00+08:00"),
      endTime: date("2026-11-01T12:00:00+08:00"),
      breakStartTime: date("2026-11-01T10:00:00+08:00"))
    let contributions = try RetentionTimeCalculator.contributions(
      for: session, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(contributions.map(\.lockedSeconds), [3600])
  }

  func testBreakIsClippedToSessionBounds() throws {
    let start = date("2026-11-01T09:00:00+08:00")
    let cases: [(Double, Double, Double)] = [
      (-3600, 1800, 5400), (5400, 10800, 5400), (-3600, 10800, 0),
      (-3600, -1800, 7200), (9000, 10800, 7200),
    ]
    for (breakStart, breakEnd, expected) in cases {
      let session = RetentionTimeCalculator.Session(
        id: "clipped", startTime: start, endTime: start.addingTimeInterval(7200),
        breakStartTime: start.addingTimeInterval(breakStart),
        breakEndTime: start.addingTimeInterval(breakEnd))
      let contributions = try RetentionTimeCalculator.contributions(
        for: session, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00"))
      XCTAssertEqual(contributions.reduce(0) { $0 + $1.lockedSeconds }, expected)
    }
  }

  func testSavedTimeZoneControlsDatesAfterTravel() throws {
    let session = RetentionTimeCalculator.Session(
      id: "new-york", startTime: date("2026-11-03T18:00:00-05:00"),
      endTime: date("2026-11-03T20:00:00-05:00"))
    let contributions = try RetentionTimeCalculator.contributions(
      for: session, cohort: taipeiCohort(), asOf: date("2026-11-05T00:00:00+08:00"))
    XCTAssertEqual(contributions.map(\.localDate), ["2026-11-04"])
    XCTAssertEqual(contributions.map(\.periodIndex), [2])
  }

  func testFallBackCountsRealSecondsAndThreeCalendarDays() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-10-30T09:00:00-07:00"), timeZoneID: "America/Los_Angeles")
    let session = RetentionTimeCalculator.Session(
      id: "fall-back", startTime: date("2026-11-01T01:00:00-07:00"),
      endTime: date("2026-11-01T02:00:00-08:00"))
    let periods = try RetentionTimeCalculator.periods(
      for: [session], cohort: cohort, asOf: date("2026-11-02T00:00:00-08:00"))
    let first = try XCTUnwrap(periods.first)
    XCTAssertEqual(first.lockedSeconds, 7200)
    XCTAssertEqual(first.endTime.timeIntervalSince(first.startTime), 73 * 3600)
    XCTAssertEqual(first.isActive, true)
  }

  func testSpringForwardDoesNotInventAnExtraHour() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-03-06T09:00:00-08:00"), timeZoneID: "America/Los_Angeles")
    let session = RetentionTimeCalculator.Session(
      id: "spring-forward", startTime: date("2026-03-08T01:30:00-08:00"),
      endTime: date("2026-03-08T03:30:00-07:00"))
    let periods = try RetentionTimeCalculator.periods(
      for: [session], cohort: cohort, asOf: date("2026-03-09T00:00:00-07:00"))
    let first = try XCTUnwrap(periods.first)
    XCTAssertEqual(first.lockedSeconds, 3600)
    XCTAssertEqual(first.endTime.timeIntervalSince(first.startTime), 71 * 3600)
    XCTAssertEqual(first.isActive, false)
  }

  func testConflictingDuplicateRequiresCallerToResolveRevision() throws {
    let start = date("2026-11-01T09:00:00+08:00")
    let sessions = [
      RetentionTimeCalculator.Session(
        id: "same", startTime: start, endTime: start.addingTimeInterval(7200)),
      RetentionTimeCalculator.Session(
        id: "same", startTime: start, endTime: start.addingTimeInterval(3600)),
    ]
    XCTAssertThrowsError(
      try RetentionTimeCalculator.periods(
        for: sessions, cohort: taipeiCohort(), asOf: date("2026-11-04T00:00:00+08:00"))
    ) { error in
      XCTAssertEqual(
        error as? RetentionTimeCalculator.CalculationError, .conflictingSession(id: "same"))
    }
  }

  func testCompletedSessionContributesItsLockedSeconds() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-11-01T09:00:00+08:00"), timeZoneID: "Asia/Taipei")
    let session = RetentionTimeCalculator.Session(
      id: "manual", startTime: date("2026-11-01T09:00:00+08:00"),
      endTime: date("2026-11-01T11:00:00+08:00"))

    let contributions = try RetentionTimeCalculator.contributions(
      for: session, cohort: cohort, asOf: date("2026-11-04T00:00:00+08:00"))

    XCTAssertEqual(contributions.count, 1)
    XCTAssertEqual(contributions.first?.lockedSeconds, 7200)
    XCTAssertEqual(contributions.first?.localDate, "2026-11-01")
    XCTAssertEqual(contributions.first?.periodIndex, 1)
  }
  func testRepeatedSessionDoesNotDoubleCountTime() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-11-01T09:00:00+08:00"), timeZoneID: "Asia/Taipei")
    let session = RetentionTimeCalculator.Session(
      id: "replayed", startTime: date("2026-11-01T09:00:00+08:00"),
      endTime: date("2026-11-01T10:00:00+08:00"))
    let periods = try RetentionTimeCalculator.periods(
      for: [session, session], cohort: cohort, asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(periods.first?.lockedSeconds, 3600)
    XCTAssertEqual(periods.first?.isActive, false)
  }

  func testThreeDaysSumToTwoHoursAndCurrentPeriodRemainsPending() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-11-01T09:00:00+08:00"), timeZoneID: "Asia/Taipei")
    let sessions = [
      RetentionTimeCalculator.Session(
        id: "40", startTime: date("2026-11-01T09:00:00+08:00"),
        endTime: date("2026-11-01T09:40:00+08:00")),
      RetentionTimeCalculator.Session(
        id: "50", startTime: date("2026-11-02T09:00:00+08:00"),
        endTime: date("2026-11-02T09:50:00+08:00")),
      RetentionTimeCalculator.Session(
        id: "30", startTime: date("2026-11-03T09:00:00+08:00"),
        endTime: date("2026-11-03T09:30:00+08:00")),
    ]
    let periods = try RetentionTimeCalculator.periods(
      for: sessions, cohort: cohort, asOf: date("2026-11-04T00:00:00+08:00"))
    XCTAssertEqual(periods.map(\.lockedSeconds), [7200, 0])
    XCTAssertEqual(periods.map(\.isActive), [true, nil])
    XCTAssertEqual(periods.first?.startTime, date("2026-11-01T00:00:00+08:00"))
    XCTAssertEqual(periods.first?.endTime, date("2026-11-04T00:00:00+08:00"))
  }

  func testBreakCrossingMidnightIsExcludedFromBothPeriods() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-11-01T09:00:00+08:00"), timeZoneID: "Asia/Taipei")
    let session = RetentionTimeCalculator.Session(
      id: "with-break", startTime: date("2026-11-03T22:00:00+08:00"),
      endTime: date("2026-11-04T03:00:00+08:00"),
      breakStartTime: date("2026-11-03T23:30:00+08:00"),
      breakEndTime: date("2026-11-04T00:30:00+08:00"))
    let contributions = try RetentionTimeCalculator.contributions(
      for: session, cohort: cohort, asOf: date("2026-11-04T04:00:00+08:00"))
    XCTAssertEqual(contributions.map(\.lockedSeconds), [5400, 9000])
  }

  func testMidnightSessionSplitsAcrossThirdAndFourthDays() throws {
    let cohort = try RetentionTimeCalculator.Cohort(
      startedAt: date("2026-11-01T23:00:00+08:00"), timeZoneID: "Asia/Taipei")
    let session = RetentionTimeCalculator.Session(
      id: "midnight", startTime: date("2026-11-03T23:00:00+08:00"),
      endTime: date("2026-11-04T01:00:00+08:00"))
    let contributions = try RetentionTimeCalculator.contributions(
      for: session, cohort: cohort, asOf: date("2026-11-04T02:00:00+08:00"))

    XCTAssertEqual(contributions.map(\.localDate), ["2026-11-03", "2026-11-04"])
    XCTAssertEqual(contributions.map(\.dayOffset), [2, 3])
    XCTAssertEqual(contributions.map(\.periodIndex), [1, 2])
    XCTAssertEqual(contributions.map(\.lockedSeconds), [3600, 3600])
  }
}
