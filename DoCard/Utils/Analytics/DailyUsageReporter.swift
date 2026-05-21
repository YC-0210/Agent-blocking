import Foundation
import SwiftData

/// Sends yesterday's anonymized usage rollup once per day.
///
/// Safe to call on every launch/foreground: it self-throttles via a stored
/// "last reported day" marker and is a no-op when analytics is disabled or the
/// first-run disclosure has not been shown yet.
@MainActor
enum DailyUsageReporter {
  private static let suite: UserDefaults =
    UserDefaults(suiteName: "group.DO.version3") ?? .standard
  private static let lastReportedDayKey = "analyticsLastReportedDay"

  static func reportIfNeeded(context: ModelContext) async {
    // No upload until the user is opted in (default ON) and has seen the notice.
    guard AnalyticsConsent.isGeneralEnabled, AnalyticsConsent.disclosureShown else { return }

    let cal = Calendar.current
    guard let yesterday = cal.date(byAdding: .day, value: -1, to: Date()) else { return }
    let dayString = DailyUsageAggregator.dayFormatter.string(from: cal.startOfDay(for: yesterday))

    // Already sent this day's rollup.
    if suite.string(forKey: lastReportedDayKey) == dayString { return }

    guard let row = DailyUsageAggregator.buildRow(for: yesterday, context: context) else { return }

    do {
      try await UsageAnalyticsClient.upload(row)
      suite.set(dayString, forKey: lastReportedDayKey)
    } catch {
      // Leave the marker unset so the next launch retries.
    }
  }
}
