import Foundation
import OSLog

private let log = Logger(subsystem: "app.docard.monitor", category: "MacExtensionSync")

/// Best-effort Supabase writer that runs from the DeviceActivityMonitor
/// extension whenever a session lifecycle event fires there — both
/// `ScheduleTimerActivity` (scheduled blocking starts/ends) and
/// `StrategyTimerActivity` (per-session timer expires while app is in
/// background). Self-contained (no dependency on @MainActor singletons or
/// SwiftData) so it compiles for both the main app target and the extension
/// target.
///
/// On PATCH failure during `notifySessionEnded()`, the iphone_token is
/// appended to the App Group's pendingEndQueue so the main app's
/// `MacSessionSyncService.flushQueue()` can retry on next foreground or
/// 30s timer tick. POST failures during `notifySessionStarted()` are NOT
/// retried for the same reason manual-session starts aren't: a delayed block
/// halfway through the window is worse UX than no block.
enum MacExtensionSyncWriter {

  // App Group storage shared with the main app's MacPairingService /
  // MacSessionSyncService. Keys must match.
  private static let appGroupSuiteName = "group.DO.version3"
  private static let iphoneTokenKey = "macSync.iphoneToken"
  private static let pendingEndQueueKey = "macSync.pendingEndQueue"
  private static let hasEverSyncedKey = "macSync.hasEverSynced"

  // Mirror of MacSupabaseClient constants. Duplicated here to keep this file
  // self-contained for the extension target. Keep in sync if values change.
  private static let supabaseURL = URL(
    string: "https://wbhicuxbvnketbdqywds.supabase.co"
  )!
  private static let anonKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6IndiaGljdXhidm5rZXRiZHF5d2RzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkzOTM1MjksImV4cCI6MjA4NDk2OTUyOX0.WJv_uaZTyFkTFgHoKXh9-4rW5WJVancLTVI5n7o0It8"

  /// Extensions get a small time budget per callback. URLSession requests in a
  /// healthy network finish in well under this window; we cap to avoid the
  /// system killing the extension while we're still waiting.
  private static let requestTimeoutSeconds: TimeInterval = 5

  // MARK: - Public API

  /// Called from extension-side timer activities (ScheduleTimerActivity.start
  /// or StrategyTimerActivity.stop's schedule-resume branch) after
  /// restrictions have been activated locally. Synchronously POSTs an
  /// `active` row to `mac_sessions` so paired Chromes pick it up on their
  /// next poll.
  static func notifySessionStarted() {
    guard let token = readIphoneToken(), !token.isEmpty else {
      log.info("session start: no iphone_token, skipping Mac sync")
      return
    }

    let body: [String: Any] = [
      "iphone_token": token,
      "state": "active",
      "blocked_domains": [],
      "started_at": ISO8601DateFormatter().string(from: Date()),
    ]

    let ok = sendRequest(
      method: "POST",
      path: "mac_sessions",
      query: nil,
      body: body
    )

    if ok {
      // Mark "has ever synced" so the main app's status badge appears next time
      // the user opens the foreground UI.
      sharedDefaults()?.set(true, forKey: hasEverSyncedKey)
    } else {
      log.error("session start Supabase POST failed (best-effort, no retry)")
    }
  }

  /// Called from extension-side timer activities when a session ends in the
  /// background (schedule window closes, or per-session strategy timer
  /// expires). PATCHes the active session for this token to `ended`. Failure
  /// → token is appended to the App Group retry queue for the main app's
  /// `MacSessionSyncService` to resend on next foreground. Without this,
  /// listening Chromes would stay blocked indefinitely after a network blip.
  static func notifySessionEnded() {
    guard let token = readIphoneToken(), !token.isEmpty else {
      log.info("session end: no iphone_token, skipping Mac sync")
      return
    }

    let body: [String: Any] = [
      "state": "ended",
      "ended_at": ISO8601DateFormatter().string(from: Date()),
    ]

    let query = "iphone_token=eq.\(token)&state=eq.active"

    let ok = sendRequest(
      method: "PATCH",
      path: "mac_sessions",
      query: query,
      body: body
    )

    if !ok {
      log.error("session end Supabase PATCH failed — queueing for retry")
      enqueueEnd(token: token)
    }
  }

  // MARK: - Storage helpers

  private static func sharedDefaults() -> UserDefaults? {
    UserDefaults(suiteName: appGroupSuiteName)
  }

  private static func readIphoneToken() -> String? {
    sharedDefaults()?.string(forKey: iphoneTokenKey)
  }

  private static func enqueueEnd(token: String) {
    guard let defaults = sharedDefaults() else { return }
    var queue = defaults.stringArray(forKey: pendingEndQueueKey) ?? []
    if !queue.contains(token) {
      queue.append(token)
      defaults.set(queue, forKey: pendingEndQueueKey)
    }
  }

  // MARK: - Network

  /// Synchronous-ish HTTP via URLSession + DispatchSemaphore so the call
  /// completes within the extension's runtime budget. Returns true on 2xx.
  private static func sendRequest(
    method: String,
    path: String,
    query: String?,
    body: [String: Any]
  ) -> Bool {
    var components = URLComponents(
      url: supabaseURL.appendingPathComponent("rest/v1/\(path)"),
      resolvingAgainstBaseURL: false
    )!
    if let query = query {
      components.query = query
    }
    guard let url = components.url else { return false }

    var req = URLRequest(url: url)
    req.httpMethod = method
    req.setValue(anonKey, forHTTPHeaderField: "apikey")
    req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // RLS identification — see MacSupabaseClient for full notes. Extension reads
    // iphone_token from the App Group (same key the main app uses).
    if let token = readIphoneToken(), !token.isEmpty {
      req.setValue(token, forHTTPHeaderField: "X-Iphone-Token")
    }
    req.setValue("return=minimal", forHTTPHeaderField: "Prefer")
    req.timeoutInterval = requestTimeoutSeconds

    do {
      req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
    } catch {
      log.error("Failed to serialize body: \(error.localizedDescription, privacy: .public)")
      return false
    }

    var success = false
    let semaphore = DispatchSemaphore(value: 0)

    URLSession.shared.dataTask(with: req) { _, response, error in
      defer { semaphore.signal() }
      if let error = error {
        log.error("HTTP error: \(error.localizedDescription, privacy: .public)")
        return
      }
      if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
        success = true
      } else if let http = response as? HTTPURLResponse {
        log.error("HTTP \(http.statusCode) on \(method) \(path)")
      }
    }.resume()

    _ = semaphore.wait(timeout: .now() + requestTimeoutSeconds + 1)
    return success
  }
}
