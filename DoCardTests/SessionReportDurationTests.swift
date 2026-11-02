import Foundation
import XCTest

@testable import DoCard

final class SessionReportDurationTests: XCTestCase {
  func testP4DeductsOnlyBreakTimeInsideSession() {
    let cases: [(name: String, start: Int?, end: Int?, expectedMinutes: Int)] = [
      ("no break", nil, nil, 60),
      ("09:20–09:30", 560, 570, 50),
      ("touches session start", 540, 550, 50),
      ("touches session end", 590, 600, 50),
      ("08:55–09:05: only five minutes inside", 535, 545, 55),
    ]
    func date(_ minute: Int) -> Date { Date(timeIntervalSince1970: Double(minute * 60)) }

    for input in cases {
      let actual = SessionReportDuration.seconds(
        start: date(540), end: date(600),
        breakStart: input.start.map(date), breakEnd: input.end.map(date))
      XCTAssertEqual(actual, Double(input.expectedMinutes * 60), accuracy: 0.001, input.name)
    }
  }
}
