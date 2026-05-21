import Foundation
import OSLog

private let log = Logger(subsystem: "online.do.card.app", category: "UsageAnalytics")

/// One day's anonymized usage rollup for a single install. The database holds at
/// most one row per (install_id, date). Optional fields are omitted from the JSON
/// when nil, so the column's NULL/default applies. Distraction columns are added
/// in Phase 3 and intentionally absent here.
struct UsageDailyRow: Encodable {
  let installID: String
  let date: String  // "yyyy-MM-dd" — the user-local day being summarized
  let appVersion: String?
  let subscriptionTier: String?  // "free" | "premium"

  // core usage
  let focusMinutesTotal: Int
  let focusSessionCount: Int
  let nfcTapCount: Int

  // schedule
  let scheduleActiveCount: Int
  let scheduledFired: Int
  let scheduledCompleted: Int
  let scheduledInterrupted: Int

  // co-focus
  let cofocusUsed: Bool
  let cofocusSessionCount: Int

  // mac / chrome / safari sync
  let macsyncUsed: Bool
  let macsyncSessionCount: Int

  // gallery (motivation photos)
  let galleryPhotoCount: Int
  let galleryHasCaption: Bool
  let galleryShownOnMain: Bool

  // behavior quality
  let emergencyUnlockCount: Int
  let focusScore: Double?

  enum CodingKeys: String, CodingKey {
    case installID = "install_id"
    case date
    case appVersion = "app_version"
    case subscriptionTier = "subscription_tier"
    case focusMinutesTotal = "focus_minutes_total"
    case focusSessionCount = "focus_session_count"
    case nfcTapCount = "nfc_tap_count"
    case scheduleActiveCount = "schedule_active_count"
    case scheduledFired = "scheduled_fired"
    case scheduledCompleted = "scheduled_completed"
    case scheduledInterrupted = "scheduled_interrupted"
    case cofocusUsed = "cofocus_used"
    case cofocusSessionCount = "cofocus_session_count"
    case macsyncUsed = "macsync_used"
    case macsyncSessionCount = "macsync_session_count"
    case galleryPhotoCount = "gallery_photo_count"
    case galleryHasCaption = "gallery_has_caption"
    case galleryShownOnMain = "gallery_shown_on_main"
    case emergencyUnlockCount = "emergency_unlock_count"
    case focusScore = "focus_score"
  }
}

/// Thin REST client that posts daily usage rollups to Supabase.
///
/// Reuses the project's Supabase base URL + anon key (defined in MacSupabaseClient)
/// but deliberately omits the X-Iphone-Token header: usage_daily is an anonymous,
/// insert-only table with no per-row ownership, so no RLS identification is needed.
enum UsageAnalyticsClient {

  private static let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.timeoutIntervalForResource = 15
    return URLSession(configuration: config)
  }()

  /// POSTs one daily rollup row.
  ///
  /// Idempotency comes from the table's unique (install_id, date) constraint: a
  /// resend of the same day returns HTTP 409, which is treated as success
  /// ("already sent"). A plain INSERT is used rather than an upsert on purpose —
  /// PostgREST upsert (ON CONFLICT) needs a SELECT policy to inspect the
  /// conflicting row, which would break the table's insert-only privacy model.
  /// `return=minimal` is required because the anon role has INSERT but no SELECT
  /// privilege — asking PostgREST to return the inserted row would otherwise fail.
  static func upload(_ row: UsageDailyRow) async throws {
    let url = MacSupabaseClient.baseURL.appendingPathComponent("rest/v1/usage_daily")

    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue(MacSupabaseClient.anonKey, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(MacSupabaseClient.anonKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
    req.httpBody = try JSONEncoder().encode(row)

    let (data, response): (Data, URLResponse)
    do {
      (data, response) = try await session.data(for: req)
    } catch {
      throw MacSupabaseError.transportError(error)
    }

    guard let http = response as? HTTPURLResponse else {
      throw MacSupabaseError.httpError(-1, "no response")
    }

    // 409 = duplicate (install_id, date) already present — already sent today.
    if http.statusCode == 409 {
      return
    }
    guard (200...299).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      log.error("usage_daily upload failed: \(http.statusCode) \(body, privacy: .public)")
      throw MacSupabaseError.httpError(http.statusCode, body)
    }
  }
}
