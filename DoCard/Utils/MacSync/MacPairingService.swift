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
  /// Chrome silently stops receiving future sessions. Existing Chromes keep
  /// their stale token in local storage and continue polling — but the new
  /// sessions will be written under a different token, so they never see
  /// anything. Users still need to clear the Chrome popup themselves on each
  /// Mac.
  ///
  /// Callers MUST invoke `MacSessionSyncService.shared.prepareForRevoke()`
  /// FIRST so any in-flight active session gets ended under the old token —
  /// otherwise listening Chromes stay stuck on the last 'active' row forever.
  /// The pendingEndQueue is intentionally NOT wiped here so that cleanup
  /// entry survives revocation.
  static func revokeAllMacPairings() {
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

  /// True if the Chrome Extension has claimed at least one pairing for this iPhone.
  /// Read once on view appear; not reactive.
  static func isAlreadyPairedToMac() async -> Bool {
    do {
      let rows: [PairingRow] = try await MacSupabaseClient.request(
        method: "GET",
        path: "mac_pairings",
        queryItems: [
          URLQueryItem(name: "iphone_token", value: "eq.\(iphoneToken)"),
          URLQueryItem(name: "select", value: "chrome_token,paired_at"),
        ],
        decoding: [PairingRow].self
      )
      return rows.contains { ($0.chrome_token?.isEmpty == false) }
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
            // Only transition once. Subsequent claims (other browsers using
            // the same code) overwrite chrome_token but we can't distinguish
            // them from the first — staying in claimedAdditionalsOpen is
            // intentional. User taps "完成" to commit, OR countdown expires.
            if case .awaitingClaim = self.state {
              self.state = .claimedAdditionalsOpen(code: code, expiresAt: expiresAt)
            }
          }
          // Don't exit the loop — keep ticking so countdown expiry hits.
        }
      }
    }
  }

  private static func checkClaim(code: String) async -> Bool {
    do {
      let rows: [PairingRow] = try await MacSupabaseClient.request(
        method: "GET",
        path: "mac_pairings",
        queryItems: [
          URLQueryItem(name: "pairing_code", value: "eq.\(code)"),
          URLQueryItem(name: "select", value: "chrome_token,paired_at"),
        ],
        decoding: [PairingRow].self
      )
      return rows.first?.chrome_token?.isEmpty == false
    } catch {
      return false
    }
  }

  private func upsertPairing(code: String, token: String, expiresAt: Date) async throws {
    // Use on_conflict on iphone_token so that re-pairing replaces the prior row
    // (clearing chrome_token / paired_at) instead of failing the unique constraint.
    // Explicit null is sent for chrome_token/paired_at because PostgREST's merge
    // would otherwise leave the previous (claimed) values in place.
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

private struct PairingRow: Decodable {
  let chrome_token: String?
  let paired_at: String?
}

private struct PairingInsert: Encodable {
  let pairingCode: String
  let iphoneToken: String
  let expiresAt: String

  enum CodingKeys: String, CodingKey {
    case pairingCode = "pairing_code"
    case iphoneToken = "iphone_token"
    case expiresAt = "expires_at"
    case chromeToken = "chrome_token"
    case pairedAt = "paired_at"
  }

  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(pairingCode, forKey: .pairingCode)
    try c.encode(iphoneToken, forKey: .iphoneToken)
    try c.encode(expiresAt, forKey: .expiresAt)
    try c.encodeNil(forKey: .chromeToken)
    try c.encodeNil(forKey: .pairedAt)
  }
}
