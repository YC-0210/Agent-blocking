import Combine
import Foundation
import OSLog

private let log = Logger(subsystem: "online.do.card.app", category: "MacPairing")

/// Generates pairing codes, stores the iPhone's permanent token in UserDefaults,
/// and reports back when the Chrome Extension claims the code.
@MainActor
final class MacPairingService: ObservableObject {

  // MARK: - Stored identity (persisted in App Group)

  /// All Mac sync state lives in the App Group so the DeviceActivityMonitor
  /// extension can read iphone_token + write to the retry queue when a
  /// scheduled session starts/stops in the background.
  static let appGroupSuiteName = "group.DO.version3"

  static var sharedDefaults: UserDefaults {
    UserDefaults(suiteName: appGroupSuiteName) ?? .standard
  }

  static let iphoneTokenKey = "macSync.iphoneToken"
  static let hasEverSyncedKey = "macSync.hasEverSynced"
  static let pendingEndQueueKey = "macSync.pendingEndQueue"

  /// Keychain access group shared with DoCardDeviceMonitor extension. Both
  /// targets list `$(AppIdentifierPrefix)online.do.card.app.shared` in their
  /// `keychain-access-groups` entitlement.
  static let keychainAccessGroup = KeychainHelper.sharedAccessGroup

  /// The iPhone's permanent identifier. Storage hierarchy (priority order):
  ///   1. Keychain (shared access group, kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly)
  ///   2. App Group UserDefaults (legacy storage, kept as migration source)
  ///   3. UserDefaults.standard (pre-App-Group legacy)
  /// On read, finds the highest-priority entry and migrates downward entries
  /// up to Keychain (then deletes the lower copy). On miss, generates fresh
  /// UUID into Keychain.
  ///
  /// Why Keychain: anon-key holders with iCloud/iTunes backup access could
  /// previously lift the token from the .plist and spoof session start/end
  /// for that iPhone. Keychain with ThisDeviceOnly + AfterFirstUnlock blocks
  /// backup exfiltration while still letting the DeviceActivityMonitor
  /// extension read after device boot.
  static var iphoneToken: String {
    // 1. Keychain — primary source post-migration
    if let kc = KeychainHelper.loadString(iphoneTokenKey, accessGroup: keychainAccessGroup) {
      return kc
    }
    // 2. App Group UserDefaults — legacy, migrate up
    if let legacy = sharedDefaults.string(forKey: iphoneTokenKey) {
      KeychainHelper.saveString(
        iphoneTokenKey,
        value: legacy,
        accessGroup: keychainAccessGroup,
        accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      )
      sharedDefaults.removeObject(forKey: iphoneTokenKey)
      return legacy
    }
    // 3. UserDefaults.standard — pre-App-Group legacy, migrate up
    if let preAppGroup = UserDefaults.standard.string(forKey: iphoneTokenKey) {
      KeychainHelper.saveString(
        iphoneTokenKey,
        value: preAppGroup,
        accessGroup: keychainAccessGroup,
        accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      )
      UserDefaults.standard.removeObject(forKey: iphoneTokenKey)
      return preAppGroup
    }
    // 4. Fresh — write to Keychain only
    let fresh = UUID().uuidString
    KeychainHelper.saveString(
      iphoneTokenKey,
      value: fresh,
      accessGroup: keychainAccessGroup,
      accessibility: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    )
    return fresh
  }

  static func resetIphoneToken() {
    KeychainHelper.delete(iphoneTokenKey, accessGroup: keychainAccessGroup)
    sharedDefaults.removeObject(forKey: iphoneTokenKey)
    UserDefaults.standard.removeObject(forKey: iphoneTokenKey)
  }

  /// "Nuclear" revoke. Rotates the iPhone's identity so any previously paired
  /// browser silently stops receiving future sessions. Old browsers keep
  /// their stale chrome_token in local storage and continue polling — but new
  /// sessions are written under a different iphone_token, so RLS hides
  /// everything from them. Users still need to clear the browser popup
  /// themselves on each Mac for full cleanup.
  ///
  /// Two-phase work:
  ///   1. Best-effort DELETE all `mac_browser_clients` rows for the CURRENT
  ///      iphone_token (uses X-Iphone-Token header which still matches).
  ///      Token rotation alone makes old clients functionally inert; this
  ///      DELETE is housekeeping so the row count doesn't grow indefinitely.
  ///   2. Local rotation: wipe Keychain + UserDefaults so next read generates
  ///      a fresh UUID.
  ///
  /// Order matters: the DELETE MUST happen before the rotation, because the
  /// RLS DELETE policy requires `iphone_token = request_iphone_token()` and
  /// after rotation our header would be a fresh UUID that matches nothing.
  ///
  /// Callers MUST also invoke `MacSessionSyncService.shared.prepareForRevoke()`
  /// FIRST so any in-flight active session gets ended under the old token —
  /// otherwise listening browsers stay stuck on the last 'active' row forever.
  /// The pendingEndQueue is intentionally NOT wiped here so that cleanup
  /// entry survives revocation.
  static func revokeAllMacPairings() async {
    // Phase 1: best-effort remote cleanup BEFORE rotating.
    let oldToken = iphoneToken
    do {
      _ = try await MacSupabaseClient.request(
        method: "DELETE",
        path: "mac_browser_clients",
        queryItems: [URLQueryItem(name: "iphone_token", value: "eq.\(oldToken)")],
        prefer: "return=minimal",
        decoding: EmptyResponse.self
      )
    } catch {
      log.error("revokeAllMacPairings: best-effort browser_clients cleanup failed: \(error.localizedDescription, privacy: .public)")
      // Continue regardless — rotation still makes old clients inert.
    }

    // Also clean up the shared blocked_domains row. The new iphone_token
    // post-rotation will get a fresh empty row created by the trigger when
    // the next browser claims a code, so leaving the old row around just
    // accumulates orphans.
    do {
      _ = try await MacSupabaseClient.request(
        method: "DELETE",
        path: "mac_settings",
        queryItems: [URLQueryItem(name: "iphone_token", value: "eq.\(oldToken)")],
        prefer: "return=minimal",
        decoding: EmptyResponse.self
      )
    } catch {
      log.error("revokeAllMacPairings: best-effort mac_settings cleanup failed: \(error.localizedDescription, privacy: .public)")
    }

    // Phase 2: local rotation.
    KeychainHelper.delete(iphoneTokenKey, accessGroup: keychainAccessGroup)
    sharedDefaults.removeObject(forKey: iphoneTokenKey)
    sharedDefaults.removeObject(forKey: hasEverSyncedKey)
    UserDefaults.standard.removeObject(forKey: iphoneTokenKey)
    UserDefaults.standard.removeObject(forKey: hasEverSyncedKey)
  }

  // MARK: - Pairing session state

  enum State: Equatable {
    case idle
    case generating
    case awaitingClaim(code: String, expiresAt: Date)
    /// At least one browser has claimed this code. The code stays visible so
    /// the user can keep entering it in additional browsers (Safari, etc.)
    /// during the 10-minute window. Resolves to `.paired` when the user taps
    /// "完成" or when the countdown expires.
    case claimedAdditionalsOpen(code: String, expiresAt: Date)
    case paired(at: Date)
    case failed(message: String)
  }

  @Published private(set) var state: State = .idle

  private var pollTask: Task<Void, Never>?

  deinit {
    pollTask?.cancel()
  }

  // MARK: - Public API

  /// Generates a fresh 6-character code and uploads it to Supabase. Cancels any
  /// in-flight polling so callers can safely call this on "重新產生".
  func generateNewPairingCode() async {
    pollTask?.cancel()
    pollTask = nil
    state = .generating

    let code = Self.makePairingCode()
    let token = Self.iphoneToken
    let expiresAt = Date().addingTimeInterval(10 * 60)

    do {
      try await upsertPairing(code: code, token: token, expiresAt: expiresAt)
      state = .awaitingClaim(code: code, expiresAt: expiresAt)
      startPollingForClaim(code: code, expiresAt: expiresAt)
    } catch {
      log.error("Pairing upsert failed: \(error.localizedDescription, privacy: .public)")
      state = .failed(message: String(localized: "無法連線，請稍後再試"))
    }
  }

  /// Stops polling and forgets local pairing UI state. Does not unpair on the server side.
  func cancel() {
    pollTask?.cancel()
    pollTask = nil
    if case .awaitingClaim = state {
      state = .idle
    }
  }

  /// Called when the user taps "完成" on the claimed-but-still-open screen,
  /// signalling they're done pairing additional browsers. Stops the poll task
  /// and finalizes to `.paired`.
  func confirmPaired() {
    pollTask?.cancel()
    pollTask = nil
    if case .claimedAdditionalsOpen = state {
      state = .paired(at: Date())
    }
  }

  /// True if at least one browser is currently paired to this iPhone.
  /// Read once on view appear; not reactive. Queries `mac_browser_clients`
  /// (one row per paired browser) post-schema-split — the legacy
  /// `mac_pairings.chrome_token` column no longer exists.
  static func isAlreadyPairedToMac() async -> Bool {
    do {
      let rows: [BrowserClientRow] = try await MacSupabaseClient.request(
        method: "GET",
        path: "mac_browser_clients",
        queryItems: [
          URLQueryItem(name: "iphone_token", value: "eq.\(iphoneToken)"),
          URLQueryItem(name: "select", value: "id"),
        ],
        decoding: [BrowserClientRow].self
      )
      return !rows.isEmpty
    } catch {
      log.error("isAlreadyPairedToMac check failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  // MARK: - Internals

  private func startPollingForClaim(code: String, expiresAt: Date) {
    pollTask = Task { [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        if Task.isCancelled { return }

        if Date() > expiresAt {
          await MainActor.run {
            guard let self else { return }
            switch self.state {
            case .awaitingClaim:
              self.state = .failed(message: String(localized: "配對碼已過期，請重新產生"))
            case .claimedAdditionalsOpen:
              // At least one browser already paired during the window —
              // expiry is a successful end state, not a failure.
              self.state = .paired(at: Date())
            default:
              break
            }
          }
          return
        }

        let claimed = await Self.checkClaim(code: code)
        if claimed {
          await MainActor.run {
            guard let self else { return }
            // Transition once on the FIRST detected claim, then stay in
            // claimedAdditionalsOpen so the user can keep entering the same
            // code into more browsers. Each new browser inserts its own row
            // into mac_browser_clients (same pairing_code), so the table
            // grows independently — but UI stays in this single state until
            // the user taps "完成" or the countdown expires.
            if case .awaitingClaim = self.state {
              self.state = .claimedAdditionalsOpen(code: code, expiresAt: expiresAt)
            }
          }
          // Don't exit the loop — keep ticking so countdown expiry hits.
        }
      }
    }
  }

  /// Checks if any browser has claimed this pairing code yet. Queries the
  /// `mac_browser_clients` table (one row per browser claim, indexed by
  /// pairing_code). Returns true if at least one row exists for this code.
  private static func checkClaim(code: String) async -> Bool {
    do {
      let rows: [BrowserClientRow] = try await MacSupabaseClient.request(
        method: "GET",
        path: "mac_browser_clients",
        queryItems: [
          URLQueryItem(name: "pairing_code", value: "eq.\(code)"),
          URLQueryItem(name: "select", value: "id"),
        ],
        decoding: [BrowserClientRow].self
      )
      return !rows.isEmpty
    } catch {
      return false
    }
  }

  private func upsertPairing(code: String, token: String, expiresAt: Date) async throws {
    // Use on_conflict on iphone_token so that re-pairing replaces the prior row
    // instead of failing the unique constraint. Post-schema-split mac_pairings
    // only carries the pairing code itself — chrome_token / paired_at moved
    // to mac_browser_clients, so we don't need to null them out anymore.
    let body = PairingInsert(
      pairingCode: code,
      iphoneToken: token,
      expiresAt: ISO8601DateFormatter().string(from: expiresAt)
    )

    _ = try await MacSupabaseClient.request(
      method: "POST",
      path: "mac_pairings",
      queryItems: [URLQueryItem(name: "on_conflict", value: "iphone_token")],
      body: body,
      prefer: "resolution=merge-duplicates,return=minimal",
      decoding: EmptyResponse.self
    )
  }

  // MARK: - Code generator

  /// 6 chars, uppercase A–Z + 2–9 (no 0/1/O/I to reduce confusion).
  private static func makePairingCode() -> String {
    let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
    return String((0..<6).map { _ in alphabet.randomElement()! })
  }
}

// MARK: - DTOs

/// Minimal projection of `mac_browser_clients`. Only `id` is selected because
/// existence is the only fact we need at the call sites — checkClaim and
/// isAlreadyPairedToMac just count rows.
private struct BrowserClientRow: Decodable {
  let id: String
}

private struct PairingInsert: Encodable {
  let pairingCode: String
  let iphoneToken: String
  let expiresAt: String

  enum CodingKeys: String, CodingKey {
    case pairingCode = "pairing_code"
    case iphoneToken = "iphone_token"
    case expiresAt = "expires_at"
  }
}
