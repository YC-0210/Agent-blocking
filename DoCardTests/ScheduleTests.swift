import Foundation
import XCTest

@testable import DoCard

/// Agreed schedule-window cases A1–C7 plus equal-time validation and 24-hour boundaries.
/// These tests call production rules without saved app data, OS blocking, or clock changes.
final class ScheduleTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
    return calendar
  }

  // November 2, 2026 is Monday; November 7 is Saturday.
  private func date(day: Int, hour: Int, minute: Int = 0, second: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(
        year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second))!
  }

  private func schedule(
    days: [Weekday] = [.monday],
    startHour: Int = 22, startMinute: Int = 40,
    endHour: Int = 6, endMinute: Int = 0,
    isNextDay: Bool = true, endType: ScheduleEndType = .specificTime
  ) -> BlockedProfileSchedule {
    BlockedProfileSchedule(
      days: days, startHour: startHour, startMinute: startMinute,
      endHour: endHour, endMinute: endMinute, endType: endType, isNextDay: isNextDay)
  }

  private func assertWindow(
    _ schedule: BlockedProfileSchedule,
    day: Int, hour: Int, minute: Int = 0, second: Int = 0,
    expected: Bool, message: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertNil(
      schedule.timeValidationError, "Fixture must be a valid time range", file: file, line: line)
    let now = date(day: day, hour: hour, minute: minute, second: second)
    XCTAssertEqual(
      schedule.isCurrentlyInWindow(now: now, calendar: calendar), expected,
      message, file: file, line: line)
  }

  func testA1BeforeOvernightStart() {
    assertWindow(
      schedule(), day: 2, hour: 22, minute: 39, second: 59,
      expected: false, message: "A1: Do not start before Monday 22:40")
  }

  func testA2ExactOvernightStart() {
    assertWindow(
      schedule(), day: 2, hour: 22, minute: 40, second: 0,
      expected: true, message: "A2: Include the exact overnight start")
  }

  func testA3BeforeMidnight() {
    assertWindow(
      schedule(), day: 2, hour: 23, minute: 30, second: 0,
      expected: true, message: "A3: Monday evening is in the overnight window")
  }

  func testA4LastSecondBeforeMidnight() {
    assertWindow(
      schedule(), day: 2, hour: 23, minute: 59, second: 59,
      expected: true, message: "A4: Do not end just before midnight")
  }

  func testA5OvernightWindowIncludesTuesdayMidnight() {
    assertWindow(
      schedule(), day: 3, hour: 0, minute: 0, second: 0,
      expected: true, message: "A5: Monday window remains active at Tuesday midnight")
  }

  func testA6FollowingMorning() {
    assertWindow(
      schedule(), day: 3, hour: 3, minute: 0, second: 0,
      expected: true, message: "A6: Tuesday need not be selected for Monday overnight")
  }

  func testA7LastSecondBeforeOvernightEnd() {
    assertWindow(
      schedule(), day: 3, hour: 5, minute: 59, second: 59,
      expected: true, message: "A7: Include the last second before the overnight end")
  }

  func testA8ExactOvernightEnd() {
    assertWindow(
      schedule(), day: 3, hour: 6, minute: 0, second: 0,
      expected: false, message: "A8: Exclude the exact overnight end")
  }

  func testA9AfterOvernightEnd() {
    assertWindow(
      schedule(), day: 3, hour: 6, minute: 0, second: 1,
      expected: false, message: "A9: Do not continue past the overnight end")
  }

  func testA10MorningBeforeSelectedStartDay() {
    assertWindow(
      schedule(), day: 2, hour: 3, minute: 0, second: 0,
      expected: false, message: "A10: Sunday was not a selected start day")
  }

  func testA11UnselectedEvening() {
    assertWindow(
      schedule(), day: 3, hour: 22, minute: 40, second: 0,
      expected: false, message: "A11: Tuesday evening must not start another window")
  }

  func testA12FollowingWeek() {
    assertWindow(
      schedule(), day: 9, hour: 22, minute: 40, second: 0,
      expected: true, message: "A12: Repeat on the following Monday")
  }

  func testB1BeforeSameDayStart() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 10, isNextDay: false), day: 2, hour: 8,
      minute: 59, second: 59,
      expected: false, message: "B1: Do not start before Monday 09:00")
  }

  func testB2ExactSameDayStart() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 10, isNextDay: false), day: 2, hour: 9,
      minute: 0, second: 0,
      expected: true, message: "B2: Include the exact same-day start")
  }

  func testB3InsideSameDayWindow() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 10, isNextDay: false), day: 2, hour: 9,
      minute: 30, second: 0,
      expected: true, message: "B3: Monday 09:30 is inside the window")
  }

  func testB4LastSecondBeforeSameDayEnd() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 10, isNextDay: false), day: 2, hour: 9,
      minute: 59, second: 59,
      expected: true, message: "B4: Include the final second of the same-day window")
  }

  func testB5ExactSameDayEnd() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 10, isNextDay: false), day: 2, hour: 10,
      minute: 0, second: 0,
      expected: false, message: "B5: Exclude the exact same-day end")
  }

  func testB6SameTimeOnUnselectedDay() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 10, isNextDay: false), day: 3, hour: 9,
      minute: 30, second: 0,
      expected: false, message: "B6: Tuesday is not selected")
  }

  func testC1SaturdayToSunday() {
    assertWindow(
      schedule(days: [.saturday]), day: 8, hour: 3, minute: 0, second: 0,
      expected: true, message: "C1: Wrap Saturday to Sunday correctly")
  }

  func testC2SaturdayToSundayEnd() {
    assertWindow(
      schedule(days: [.saturday]), day: 8, hour: 6, minute: 0, second: 0,
      expected: false, message: "C2: End at Sunday 06:00 after weekday wrap")
  }

  func testC3MultipleSelectedDays() {
    assertWindow(
      schedule(days: [.monday, .wednesday]), day: 5, hour: 3, minute: 0, second: 0,
      expected: true, message: "C3: Wednesday start continues into Thursday")
  }

  func testC4GapBetweenSelectedDays() {
    assertWindow(
      schedule(days: [.monday, .wednesday]), day: 4, hour: 3, minute: 0, second: 0,
      expected: false, message: "C4: Unselected Tuesday cannot create a Wednesday morning window")
  }

  func testC5NoSelectedDays() {
    assertWindow(
      schedule(days: []), day: 3, hour: 3, minute: 0, second: 0,
      expected: false, message: "C5: Empty day selection disables the schedule")
  }

  func testC6EndAtMidnight() {
    assertWindow(
      schedule(endHour: 0), day: 3, hour: 0, minute: 0, second: 0,
      expected: false, message: "C6: A fixed midnight end is excluded")
  }

  func testC7StartAtMidnight() {
    assertWindow(
      schedule(startHour: 0, startMinute: 0, endHour: 1, isNextDay: false), day: 2, hour: 0,
      minute: 0, second: 0,
      expected: true, message: "C7: A midnight start is included")
  }

  func testFullDayBeforeStart() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 9), day: 2, hour: 8, minute: 59, second: 59,
      expected: false, message: "24-hour: inactive just before Monday start")
  }

  func testFullDayExactStart() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 9), day: 2, hour: 9, minute: 0, second: 0,
      expected: true, message: "24-hour: include Monday 09:00")
  }

  func testFullDayMidnight() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 9), day: 3, hour: 0, minute: 0, second: 0,
      expected: true, message: "24-hour: remain active after the date changes")
  }

  func testFullDayLastSecond() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 9), day: 3, hour: 8, minute: 59, second: 59,
      expected: true, message: "24-hour: include the final second")
  }

  func testFullDayExactEnd() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 9), day: 3, hour: 9, minute: 0, second: 0,
      expected: false, message: "24-hour: exclude Tuesday 09:00")
  }

  func testFullDayAfterEnd() {
    assertWindow(
      schedule(startHour: 9, startMinute: 0, endHour: 9), day: 3, hour: 9, minute: 0, second: 1,
      expected: false, message: "24-hour: remain inactive after the end")
  }

  func testSameDayEqualTimesAreRejected() {
    let value = schedule(startHour: 9, startMinute: 0, endHour: 9, isNextDay: false)
    XCTAssertEqual(value.timeValidationError, .endNotAfterStart)
  }

  func testSameDayEarlierEndIsRejected() {
    let value = schedule(startHour: 9, startMinute: 30, endHour: 9, endMinute: 29, isNextDay: false)
    XCTAssertEqual(value.timeValidationError, .endNotAfterStart)
  }

  func testNextDayEqualTimesAreAcceptedAs24Hours() {
    let value = schedule(startHour: 9, startMinute: 0, endHour: 9)
    XCTAssertNil(value.timeValidationError)
    XCTAssertEqual(value.totalDurationInSeconds, 86_400)
  }

  func testNextDayLaterEndPreservesExistingMismatchValidation() {
    let value = schedule(startHour: 9, startMinute: 0, endHour: 9, endMinute: 1)
    XCTAssertEqual(value.timeValidationError, .nextDayEndAfterStart)
  }

  func testCardTapEndPreservesExemptionFromTimeValidation() {
    let value = schedule(
      startHour: 9, startMinute: 0, endHour: 9, isNextDay: false, endType: .cardTap)
    XCTAssertNil(value.timeValidationError)
  }
}
