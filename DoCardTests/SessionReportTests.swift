import Foundation
import SwiftData
import XCTest

@testable import DoCard

@MainActor
private final class ReportFixture {
  let container: ModelContainer
  let context: ModelContext
  let work: BlockedProfiles
  let calendar: Calendar

  init() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
    self.calendar = calendar
    let schema = Schema(versionedSchema: AppSchemaV5.self)
    container = try ModelContainer(
      for: schema,
      configurations: ModelConfiguration(
        schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    context = ModelContext(container)
    context.autosaveEnabled = false
    work = BlockedProfiles(name: "Work")
    context.insert(work)
    try context.save()
  }

  func date(day: Int = 2, hour: Int, minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  func makeReport() -> ReportViewModel {
    let now = date(hour: 12)
    return ReportViewModel(calendar: calendar, now: { now })
  }

  @discardableResult
  func session(
    id: String, profile: BlockedProfiles? = nil, start: Date, end: Date?,
    breakStart: Date? = nil, breakEnd: Date? = nil
  ) throws -> BlockedProfileSession {
    let session = BlockedProfileSession(tag: "report-test", blockedProfile: profile ?? work)
    session.id = id
    session.startTime = start
    session.endTime = end
    session.endReason = end == nil ? nil : "card_tap"
    session.breakStartTime = breakStart
    session.breakEndTime = breakEnd
    context.insert(session)
    try context.save()
    return session
  }
}

@MainActor
final class SessionReportTests: XCTestCase {
  func testP1EmptyHistoryShowsZeroAndNoRanking() throws {
    let fixture = try ReportFixture()
    let report = fixture.makeReport()
    report.load(context: fixture.context, isPremium: false)

    XCTAssertEqual(report.totalBlockDuration, 0)
    XCTAssertEqual(report.sessionCount, 0)
    XCTAssertEqual(report.averageSessionDuration, 0)
    XCTAssertTrue(report.topProfiles.isEmpty)
    XCTAssertTrue(report.averageSessionDuration.isFinite)
  }

  func testP2ReloadKeepsTotalCountAndAverageStable() throws {
    let fixture = try ReportFixture()
    try fixture.session(
      id: "thirty", start: fixture.date(hour: 9), end: fixture.date(hour: 9, minute: 30))
    try fixture.session(
      id: "twenty", start: fixture.date(hour: 10), end: fixture.date(hour: 10, minute: 20))
    let report = fixture.makeReport()

    for _ in 0..<2 {
      report.load(context: fixture.context, isPremium: false)
      XCTAssertEqual(report.totalBlockDuration, 3000, accuracy: 0.001)
      XCTAssertEqual(report.sessionCount, 2)
      XCTAssertEqual(report.averageSessionDuration, 1500, accuracy: 0.001)
    }
  }

  func testP3ActiveSessionIsExcludedFromCompletedReport() throws {
    let fixture = try ReportFixture()
    try fixture.session(
      id: "completed", start: fixture.date(hour: 9), end: fixture.date(hour: 9, minute: 30))
    try fixture.session(id: "active", start: fixture.date(hour: 10), end: nil)
    let report = fixture.makeReport()
    report.load(context: fixture.context, isPremium: false)

    XCTAssertEqual(report.totalBlockDuration, 1800, accuracy: 0.001)
    XCTAssertEqual(report.sessionCount, 1)
    XCTAssertEqual(report.averageSessionDuration, 1800, accuracy: 0.001)
    XCTAssertEqual(report.topProfiles.first?.duration, 1800)
    XCTAssertEqual(report.weekTrend?.last?.sessionCount, 1)
  }

  func testP4ReportsSubtractTheSavedBreak() throws {
    let fixture = try ReportFixture()
    try fixture.session(
      id: "with-break", start: fixture.date(hour: 9), end: fixture.date(hour: 10),
      breakStart: fixture.date(hour: 9, minute: 20), breakEnd: fixture.date(hour: 9, minute: 30))
    let report = fixture.makeReport()
    report.load(context: fixture.context, isPremium: false)

    XCTAssertEqual(report.totalBlockDuration, 3000, accuracy: 0.001)
    XCTAssertEqual(report.sessionCount, 1)
    XCTAssertEqual(report.averageSessionDuration, 3000, accuracy: 0.001)
    XCTAssertEqual(report.topProfiles.first?.duration, 3000)
    XCTAssertEqual(report.weekTrend?.last?.duration, 3000)
  }

  func testP7WholeSessionBelongsToItsStartingWeek() throws {
    let fixture = try ReportFixture()
    try fixture.session(
      id: "sunday-to-monday", start: fixture.date(day: 1, hour: 23, minute: 50),
      end: fixture.date(hour: 0, minute: 20))
    let report = fixture.makeReport()
    report.load(context: fixture.context, isPremium: false)

    XCTAssertEqual(report.totalBlockDuration, 0, accuracy: 0.001)
    XCTAssertEqual(report.sessionCount, 0)
    let trend = try XCTUnwrap(report.weekTrend)
    XCTAssertEqual(trend.count, 4)
    let currentWeek = try XCTUnwrap(trend.last)
    let previousStart = try XCTUnwrap(
      fixture.calendar.date(byAdding: .day, value: -7, to: fixture.date(hour: 0)))
    let previousWeek = try XCTUnwrap(trend.first { $0.weekStart == previousStart })
    XCTAssertEqual(previousWeek.duration, 1800, accuracy: 0.001)
    XCTAssertEqual(previousWeek.sessionCount, 1)
    XCTAssertEqual(currentWeek.weekStart, fixture.date(hour: 0))
    XCTAssertEqual(currentWeek.duration, 0, accuracy: 0.001)
    XCTAssertEqual(currentWeek.sessionCount, 0)
  }

  func testP7ExactMondayStartBelongsToTheNewWeek() throws {
    let fixture = try ReportFixture()
    try fixture.session(
      id: "exact-monday", start: fixture.date(hour: 0), end: fixture.date(hour: 0, minute: 15))
    let report = fixture.makeReport()
    report.load(context: fixture.context, isPremium: false)

    XCTAssertEqual(report.totalBlockDuration, 900, accuracy: 0.001)
    XCTAssertEqual(report.sessionCount, 1)
    let trend = try XCTUnwrap(report.weekTrend)
    let currentWeek = try XCTUnwrap(trend.last)
    XCTAssertEqual(currentWeek.weekStart, fixture.date(hour: 0))
    XCTAssertEqual(currentWeek.duration, 900, accuracy: 0.001)
    XCTAssertEqual(currentWeek.sessionCount, 1)
    XCTAssertTrue(trend.dropLast().allSatisfy { $0.duration == 0 && $0.sessionCount == 0 })
  }

  func testP8GroupsSessionsAndRanksTheTopThreeProfiles() throws {
    let fixture = try ReportFixture()
    let study = BlockedProfiles(name: "Study")
    let reading = BlockedProfiles(name: "Reading")
    let family = BlockedProfiles(name: "Family")
    for profile in [study, reading, family] { fixture.context.insert(profile) }
    try fixture.session(
      id: "work-one", start: fixture.date(hour: 6), end: fixture.date(hour: 6, minute: 20))
    try fixture.session(
      id: "work-two", start: fixture.date(hour: 7), end: fixture.date(hour: 7, minute: 20))
    try fixture.session(
      id: "study", profile: study, start: fixture.date(hour: 8),
      end: fixture.date(hour: 8, minute: 30))
    try fixture.session(
      id: "reading", profile: reading, start: fixture.date(hour: 9),
      end: fixture.date(hour: 9, minute: 20))
    try fixture.session(
      id: "family", profile: family, start: fixture.date(hour: 10),
      end: fixture.date(hour: 10, minute: 10))
    let report = fixture.makeReport()
    report.load(context: fixture.context, isPremium: false)

    XCTAssertEqual(report.totalBlockDuration, 6000, accuracy: 0.001)
    XCTAssertEqual(report.sessionCount, 5)
    XCTAssertEqual(report.topProfiles.map(\.id), [fixture.work.id, study.id, reading.id])
    XCTAssertEqual(report.topProfiles.map(\.name), ["Work", "Study", "Reading"])
    XCTAssertEqual(report.topProfiles.map(\.duration), [2400, 1800, 1200])
  }
}
