import Foundation
import SwiftData

/// Builds one day's anonymized usage rollup from local on-device data.
///
/// Pure aggregation: reads SwiftData + local settings and returns a row to
/// upload. Sends only counts/flags — never any content (no captions, app names,
/// or images). All per-day metrics are attributed to the calendar day (user-local)
/// of the relevant event's timestamp.
enum DailyUsageAggregator {

  /// ISO day string ("yyyy-MM-dd") used for the `date` column and the
  /// "already reported" bookkeeping. POSIX locale so it never localizes.
  static let dayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
  }()

  /// Builds the rollup for the calendar day containing `day` (user-local time).
  /// Returns nil only if the date math fails.
  @MainActor
  static func buildRow(for day: Date, context: ModelContext) -> UsageDailyRow? {
    let cal = Calendar.current
    let dayStart = cal.startOfDay(for: day)
    guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }

    // --- Focus sessions started on `day` and finished ---
    let sessionDescriptor = FetchDescriptor<BlockedProfileSession>(
      predicate: #Predicate { s in
        s.startTime >= dayStart && s.startTime < dayEnd && s.endTime != nil
      }
    )
    let sessions = (try? context.fetch(sessionDescriptor)) ?? []

    let focusSeconds = sessions.reduce(0.0) { $0 + $1.duration }
    let focusMinutes = Int((focusSeconds / 60.0).rounded())

    let scheduled = sessions.filter { $0.triggerSource == "scheduled" }
    let scheduledCompleted = scheduled.filter { $0.endReason == "timer_expired" }.count
    let scheduledInterrupted = scheduled.filter {
      $0.endReason == "emergency_unlock" || $0.endReason == "card_tap"
    }.count

    // --- NFC taps on `day` ---
    let nfcTapCount = NFCTapEvent.tapEvents(since: dayStart, in: context)
      .filter { $0.timestamp < dayEnd }
      .count

    // --- Emergency unlocks on `day` ---
    let emergencyCount = EmergencyUnlockEvent.events(since: dayStart, in: context)
      .filter { $0.timestamp < dayEnd }
      .count

    // --- Schedule active count (current configuration, not day-specific) ---
    let profiles = (try? BlockedProfiles.fetchProfiles(in: context)) ?? []
    let scheduleActiveCount = profiles.reduce(0) { sum, profile in
      sum + profile.schedules.filter { $0.isActive }.count
    }

    // --- Gallery (current state) ---
    let photos = MotivationPhoto.allSorted(in: context)
    let galleryHasCaption = photos.contains {
      !$0.caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    let galleryShownOnMain: Bool = {
      let defaults = UserDefaults.standard
      if defaults.object(forKey: "showMotivationGalleryOnHome") == nil { return true }
      return defaults.bool(forKey: "showMotivationGalleryOnHome")
    }()

    // --- Context ---
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    return UsageDailyRow(
      installID: AnalyticsIdentity.installID,
      date: dayFormatter.string(from: dayStart),
      appVersion: appVersion,
      subscriptionTier: SharedData.effectiveSubscriptionTier.rawValue,
      focusMinutesTotal: focusMinutes,
      focusSessionCount: sessions.count,
      nfcTapCount: nfcTapCount,
      scheduleActiveCount: scheduleActiveCount,
      scheduledFired: scheduled.count,
      scheduledCompleted: scheduledCompleted,
      scheduledInterrupted: scheduledInterrupted,
      // Phase 2: per-day co-focus / mac-sync counters are not yet wired (those
      // features keep no local per-day usage log). Tracked as a follow-up.
      cofocusUsed: false,
      cofocusSessionCount: 0,
      macsyncUsed: false,
      macsyncSessionCount: 0,
      galleryPhotoCount: photos.count,
      galleryHasCaption: galleryHasCaption,
      galleryShownOnMain: galleryShownOnMain,
      emergencyUnlockCount: emergencyCount,
      // Phase 2: focus_score left nil to avoid diverging from the in-app weekly
      // score; wired from the canonical ReportViewModel calc as a follow-up.
      focusScore: nil
    )
  }
}
