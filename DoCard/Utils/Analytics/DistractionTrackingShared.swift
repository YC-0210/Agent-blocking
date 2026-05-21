import Foundation

/// Constants and App Group storage for distraction-usage threshold tracking,
/// shared between the main app and the DeviceActivityMonitor extension.
///
/// Foundation-only on purpose so it compiles cleanly in the extension target
/// (added to that target via the project's membershipExceptions). Stores only a
/// coarse daily usage *bucket* — never raw minutes, never which app — so the
/// privacy exposure of distraction tracking stays minimal.
enum DistractionTrackingShared {
  static let appGroup = "group.DO.version3"

  /// Single daily-repeating DeviceActivity used ONLY for usage threshold events.
  /// Deliberately distinct from every blocking activity name so the monitor
  /// extension can route it separately and never run blocking logic for it.
  static let activityName = "docard.distraction.daily"

  /// Threshold ladder. Buckets: 0 = <15m, 1 = 15–30, 2 = 30–60, 3 = 60–120,
  /// 4 = 120m+. A crossed threshold raises that day's bucket to its value.
  static let thresholds: [(eventName: String, minutes: Int, bucket: Int)] = [
    ("distraction.t15", 15, 1),
    ("distraction.t30", 30, 2),
    ("distraction.t60", 60, 3),
    ("distraction.t120", 120, 4),
  ]

  static func bucket(forEventName name: String) -> Int? {
    thresholds.first { $0.eventName == name }?.bucket
  }

  // MARK: - Storage

  private static var suite: UserDefaults {
    UserDefaults(suiteName: appGroup) ?? .standard
  }

  private static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = .current
    return f
  }()

  private static let keyPrefix = "distractionBucket_"

  private static func dayKey(_ date: Date) -> String {
    keyPrefix + dayFormatter.string(from: date)
  }

  /// Marks a day as tracked with a baseline bucket of 0 (used so a tracked day
  /// with low usage is distinguishable from a day with no tracking at all).
  /// Called from the extension's intervalDidStart for the distraction activity.
  static func ensureDayTracked(on date: Date = Date()) {
    let key = dayKey(date)
    if suite.object(forKey: key) == nil {
      suite.set(0, forKey: key)
    }
  }

  /// Raises a day's recorded bucket to at least `bucket` (keeps the daily max).
  static func recordBucketReached(_ bucket: Int, on date: Date = Date()) {
    let key = dayKey(date)
    let current = suite.object(forKey: key) as? Int ?? 0
    if bucket > current {
      suite.set(bucket, forKey: key)
    }
  }

  /// The recorded bucket (0–4) for `date`, or nil if that day was not tracked.
  static func bucket(for date: Date) -> Int? {
    suite.object(forKey: dayKey(date)) as? Int
  }

  /// Removes bucket keys older than `keepingDays` to bound storage growth.
  static func pruneOldDays(keepingDays: Int = 120) {
    let cutoff = Calendar.current.date(byAdding: .day, value: -keepingDays, to: Date())
    guard let cutoff else { return }
    let cutoffStr = dayFormatter.string(from: cutoff)
    for key in suite.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
      let dayPart = String(key.dropFirst(keyPrefix.count))
      if dayPart < cutoffStr {
        suite.removeObject(forKey: key)
      }
    }
  }
}
