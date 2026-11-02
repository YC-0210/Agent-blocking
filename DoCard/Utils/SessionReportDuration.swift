import Foundation

/// Completed-session report time. Saved elapsed timestamps remain unchanged.
enum SessionReportDuration {
  static func seconds(
    start: Date, end: Date, breakStart: Date? = nil, breakEnd: Date? = nil
  ) -> TimeInterval {
    let elapsed = max(0, end.timeIntervalSince(start))
    guard let breakStart, let breakEnd else { return elapsed }
    let paused = max(0, min(end, breakEnd).timeIntervalSince(max(start, breakStart)))
    return elapsed - paused
  }
}
