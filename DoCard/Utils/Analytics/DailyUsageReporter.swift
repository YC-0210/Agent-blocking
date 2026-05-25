import Foundation
import SwiftData

/// Sends anonymized daily usage rollups, backfilling any missed days.
///
/// Safe to call on every launch/foreground: it self-throttles via a stored
/// "last reported day" marker and is a no-op when analytics is disabled or the
/// first-run disclosure has not been shown yet. On a normal day this uploads
/// just yesterday; if the user skipped a few days it backfills the gap (capped
/// at `maxBackfillDays`) so trend analysis isn't biased by missing days.
@MainActor
enum DailyUsageReporter {
  private static let suite: UserDefaults =
    UserDefaults(suiteName: "group.DO.version3") ?? .standard
  private static let lastReportedDayKey = "analyticsLastReportedDay"

  /// Cap on how many past days a single run will backfill, so a long gap (or a
  /// corrupted marker) can never trigger an unbounded upload burst.
  private static let maxBackfillDays = 14

  static func reportIfNeeded(context: ModelContext) async {
    // No upload until the user is opted in (default ON) and has seen the notice.
    guard AnalyticsConsent.isGeneralEnabled, AnalyticsConsent.disclosureShown else { return }

    let cal = Calendar.current
    let today = cal.startOfDay(for: Date())
    guard let yesterday = cal.date(byAdding: .day, value: -1, to: today) else { return }

    // First day to (re)send. With a marker, resume from the day after it but
    // never reach back further than maxBackfillDays. Without one (first run),
    // send only yesterday — don't dump historical days on first report.
    let firstDay: Date
    if let marker = suite.string(forKey: lastReportedDayKey),
       let lastReported = DailyUsageAggregator.dayFormatter.date(from: marker) {
      guard let next = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: lastReported))
      else { return }
      let earliest = cal.date(byAdding: .day, value: -maxBackfillDays, to: today) ?? next
      firstDay = max(next, earliest)
    } else {
      firstDay = yesterday
    }

    guard firstDay <= yesterday else { return }  // already up to date

    // Upload oldest → newest, advancing the marker per success so a mid-run
    // failure simply resumes next launch. A duplicate day returns 409, which the
    // client treats as success.
    var day = firstDay
    while day <= yesterday {
      guard let row = DailyUsageAggregator.buildRow(for: day, context: context) else { break }
      do {
        try await UsageAnalyticsClient.upload(row)
        suite.set(DailyUsageAggregator.dayFormatter.string(from: day), forKey: lastReportedDayKey)
      } catch {
        break  // leave marker at last success; retry from here next launch
      }
      guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
      day = next
    }
  }
}
