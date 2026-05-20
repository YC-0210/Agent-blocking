import Combine
import Foundation
import OSLog
import UIKit

private let log = Logger(subsystem: "online.do.card.app", category: "MacSessionSync")

/// Pushes session start/end events to Supabase so the Chrome Extension can
/// project the matching DNR rules. Ends are critical (user's Mac stays
/// blocked until 'ended' lands), so they get a persistent retry queue.
@MainActor
final class MacSessionSyncService: ObservableObject {

  static let shared = MacSessionSyncService()

  enum Status: Equatable {
    case idle      // not in a session, or not paired
    case syncing   // request in flight
    case synced    // last sync 2xx
    case failed    // last sync failed; either retrying (end) or gave up (start)
  }

  @Published private(set) var status: Status = .idle
  @Published private(set) var pendingEndCount: Int = 0

  /// Reflects whether the user has ever paired (UserDefaults flag set after a
  /// successful start). False until the first session.start succeeds, which is
  /// fine for the Mac-status UI: nothing to show before pairing anyway.
  private static let hasUsedSyncKey = MacPairingService.hasEverSyncedKey

  private static let pendingEndQueueKey = MacPairingService.pendingEndQueueKey

  private static var sharedDefaults: UserDefaults { MacPairingService.sharedDefaults }

  private var retryTimer: Timer?
  private var foregroundObserver: NSObjectProtocol?

  private init() {
    pendingEndCount = loadQueue().count

    foregroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.willEnterForegroundNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor in
        self?.flushQueue()
        await self?.reconcileSessionState()
      }
    }

    // Best-effort periodic flush for cases where the app stays foregrounded
    // through a network blip (e.g. session ended while AirPort hiccupped).
    retryTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.flushQueue() }
    }
  }

  deinit {
    if let observer = foregroundObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    retryTimer?.invalidate()
  }

  // MARK: - Public API

  /// Fire-and-forget. Failure must never block the iPhone-side Screen Time flow.
  ///
  /// Note: previously took a `blockedDomains: [String]` argument that was
  /// always defaulted to `[]` and projected into mac_sessions.blocked_domains.
  /// Removed in May 2026 — Supabase column kept (defaults to '{}' server-side)
  /// in case a future "iPhone-pushed default block list" feature reactivates
  /// it; for now the client side is silent on the field.
  func startSession() {
    // Premium gate (write-layer enforcement, v2.0.6+). Mac/Chrome/Safari sync
    // is a Premium feature; free users (or premium users past the 16-day
    // grace period) must not push session-active rows. Mirrors the
    // SettingsTabView entry-point gate. We deliberately only gate START —
    // END remains unguarded so any session row created while the user was
    // premium still cleans up cleanly after a mid-session downgrade.
    guard SharedData.effectiveSubscriptionTier == .premium else {
      log.info("startSession: skipping Mac sync — tier is free")
      return
    }
    let token = MacPairingService.iphoneToken
    Task {
      await sendStart(token: token)
    }
  }

  func endSession() {
    let token = MacPairingService.iphoneToken
    Task {
      await sendEnd(token: token)
    }
  }

  /// Called BEFORE the iPhone rotates its token. Pushes an 'ended' for the
  /// current token into the retry queue so any Chrome still listening on it
  /// gets unblocked — even if revoke happens mid-session, and even if the
  /// PATCH fails right now (queue retries on foreground / 30s timer).
  func prepareForRevoke() {
    let token = MacPairingService.iphoneToken
    appendToQueue(token: token)
    Task { await sendEnd(token: token, fromQueue: true) }
  }

  /// Called after the user invokes "解除所有 Mac 連動" so the in-memory status
  /// matches the wiped UserDefaults state. pendingEndCount is left alone —
  /// the queue may still hold a cleanup entry from prepareForRevoke.
  func resetAfterRevoke() {
    status = .idle
  }

  func flushQueue() {
    let queue = loadQueue()
    guard !queue.isEmpty else { return }
    Task {
      for token in queue {
        await sendEnd(token: token, fromQueue: true)
      }
    }
  }

  /// Plan B fallback for the schedule path. The DeviceActivityMonitor extension
  /// fires Supabase writes best-effort but has no retry queue for START
  /// failures (extension may be killed before retry). This catches the gap by
  /// comparing local SharedData state against Supabase whenever the user
  /// brings the app to the foreground.
  ///
  /// Two cases handled:
  /// - iPhone has active scheduled session, Supabase has no active row →
  ///   the schedule's POST failed; resend it.
  /// - iPhone has no active session, Supabase has an active row →
  ///   a previous end failed beyond what the queue caught; PATCH it.
  func reconcileSessionState() async {
    let token = MacPairingService.iphoneToken
    let hasLocalActive = SharedData.getActiveSharedSession() != nil

    let url = "mac_sessions"
    let queryItems = [
      URLQueryItem(name: "iphone_token", value: "eq.\(token)"),
      URLQueryItem(name: "state", value: "eq.active"),
      URLQueryItem(name: "select", value: "id"),
      URLQueryItem(name: "limit", value: "1"),
    ]

    let supabaseHasActive: Bool
    do {
      let rows: [ReconcileRow] = try await MacSupabaseClient.request(
        method: "GET",
        path: url,
        queryItems: queryItems,
        decoding: [ReconcileRow].self
      )
      supabaseHasActive = !rows.isEmpty
    } catch {
      log.error("reconcile query failed: \(error.localizedDescription, privacy: .public)")
      return
    }

    if hasLocalActive && !supabaseHasActive {
      // Premium gate: free users SHOULD have no Supabase row matching a
      // local active session — that's the correct steady-state for free
      // tier. Don't resend; this branch is only meaningful for premium.
      guard SharedData.effectiveSubscriptionTier == .premium else {
        log.info("reconcile: local active but Supabase missing — tier is free, skipping resend")
        return
      }
      log.info("reconcile: local active but Supabase missing — resending start")
      await sendStart(token: token)
    } else if !hasLocalActive && supabaseHasActive {
      // Cleanup path — always run regardless of tier. A free user landing
      // here means they downgraded after starting a premium session; the
      // stale Supabase row must still be ended so paired Chromes unblock.
      log.info("reconcile: Supabase active but local cleared — sending end")
      await sendEnd(token: token, fromQueue: true)
    }
  }

  // MARK: - Network

  private func sendStart(token: String) async {
    status = .syncing

    let body = SessionStartInsert(
      iphoneToken: token,
      state: "active",
      startedAt: ISO8601DateFormatter().string(from: Date())
    )

    do {
      _ = try await MacSupabaseClient.request(
        method: "POST",
        path: "mac_sessions",
        body: body,
        prefer: "return=minimal",
        decoding: EmptyResponse.self
      )
      status = .synced
      Self.sharedDefaults.set(true, forKey: Self.hasUsedSyncKey)
    } catch {
      log.error("startSession sync failed: \(error.localizedDescription, privacy: .public)")
      status = .failed
      // Intentionally do NOT queue start retries. If the user's Mac wasn't
      // blocked at the moment they swiped, retrying minutes later when the
      // session is half-elapsed creates a worse experience than just no-op'ing.
    }
  }

  private func sendEnd(token: String, fromQueue: Bool = false) async {
    status = .syncing

    let body = SessionEndPatch(
      state: "ended",
      endedAt: ISO8601DateFormatter().string(from: Date())
    )

    do {
      _ = try await MacSupabaseClient.request(
        method: "PATCH",
        path: "mac_sessions",
        queryItems: [
          URLQueryItem(name: "iphone_token", value: "eq.\(token)"),
          URLQueryItem(name: "state", value: "eq.active"),
        ],
        body: body,
        prefer: "return=minimal",
        decoding: EmptyResponse.self
      )
      status = .synced
      removeFromQueue(token: token)
    } catch {
      log.error("endSession sync failed (queued=\(fromQueue)): \(error.localizedDescription, privacy: .public)")
      status = .failed
      if !fromQueue {
        appendToQueue(token: token)
      }
    }
  }

  // MARK: - Persistent retry queue

  private func loadQueue() -> [String] {
    Self.sharedDefaults.stringArray(forKey: Self.pendingEndQueueKey) ?? []
  }

  private func saveQueue(_ tokens: [String]) {
    Self.sharedDefaults.set(tokens, forKey: Self.pendingEndQueueKey)
    pendingEndCount = tokens.count
  }

  private func appendToQueue(token: String) {
    var queue = loadQueue()
    if !queue.contains(token) {
      queue.append(token)
      saveQueue(queue)
    }
  }

  private func removeFromQueue(token: String) {
    var queue = loadQueue()
    queue.removeAll { $0 == token }
    saveQueue(queue)
  }
}

// MARK: - DTOs

private struct SessionStartInsert: Encodable {
  let iphoneToken: String
  let state: String
  let startedAt: String

  enum CodingKeys: String, CodingKey {
    case iphoneToken = "iphone_token"
    case state
    case startedAt = "started_at"
  }
}

private struct ReconcileRow: Decodable {
  let id: String
}

private struct SessionEndPatch: Encodable {
  let state: String
  let endedAt: String

  enum CodingKeys: String, CodingKey {
    case state
    case endedAt = "ended_at"
  }
}
