import CryptoKit
import FamilyControls
import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "app.docard", category: "SharedData")

enum SharedData {
  private static let suite: UserDefaults = {
    guard let defaults = UserDefaults(suiteName: "group.DO.version3") else {
      // Fallback to standard UserDefaults if App Group is unavailable
      logger.warning("App Group unavailable, falling back to standard UserDefaults")
      return UserDefaults.standard
    }
    return defaults
  }()

  // MARK: – Keys
  private enum Key: String {
    case profileSnapshots
    case activeScheduleSession
    case completedScheduleSessions
  }

  // MARK: – HMAC Integrity Verification (V-17)
  // Detects tampering of shared settings stored in UserDefaults on jailbroken devices.
  // A 256-bit HMAC key is stored in Keychain; each value's signature lives alongside
  // the data in UserDefaults under "<key>.hmac".

  private static let hmacKeychainService = "com.do-app.security"

  /// Loads raw data from Keychain for the given account key.
  private static func loadKeychainData(_ account: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: hmacKeychainService,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else { return nil }
    return data
  }

  /// Saves raw data to Keychain for the given account key.
  private static func saveKeychainData(_ account: String, data: Data) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: hmacKeychainService,
      kSecAttrAccount as String: account,
    ]
    let attributes: [String: Any] = [kSecValueData as String: data]
    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if updateStatus == errSecItemNotFound {
      var newItem = query
      newItem[kSecValueData as String] = data
      newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      SecItemAdd(newItem as CFDictionary, nil)
    }
  }

  private static let hmacSigningKey: SymmetricKey? = {
    let keychainKey = "sharedDataHMACKey"

    // Try to load existing key from Keychain
    if let existingData = loadKeychainData(keychainKey) {
      return SymmetricKey(data: existingData)
    }

    // Extensions may not have Keychain write access — only generate in the main app
    let isExtension = Bundle.main.bundleURL.pathExtension == "appex"
    if isExtension {
      return nil
    }

    // First launch: generate a new 256-bit key and persist it
    let newKey = SymmetricKey(size: .bits256)
    let keyData = newKey.withUnsafeBytes { Data($0) }
    saveKeychainData(keychainKey, data: keyData)
    return SymmetricKey(data: keyData)
  }()

  /// Computes HMAC-SHA256 for the given data.
  private static func signData(_ data: Data) -> Data? {
    guard let key = hmacSigningKey else { return nil }
    let mac = HMAC<SHA256>.authenticationCode(for: data, using: key)
    return Data(mac)
  }

  /// Checks whether the data matches its HMAC signature.
  private static func isDataAuthentic(_ data: Data, signature: Data) -> Bool {
    guard let key = hmacSigningKey else { return true } // Degrade gracefully in extensions
    return HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: data, using: key)
  }

  /// Writes data + HMAC signature to UserDefaults.
  private static func signedWrite(_ data: Data, forKey key: String) {
    suite.set(data, forKey: key)
    if let sig = signData(data) {
      suite.set(sig, forKey: key + ".hmac")
    }
  }

  /// Reads data from UserDefaults and verifies its HMAC.
  /// Returns nil if the signature does not match (possible tampering).
  private static func verifiedRead(forKey key: String) -> Data? {
    guard let data = suite.data(forKey: key) else { return nil }

    // No HMAC key available (e.g. extension without Keychain access) — skip verification
    guard hmacSigningKey != nil else { return data }

    guard let storedSig = suite.data(forKey: key + ".hmac") else {
      // Upgrade path: data exists from before V-17. Sign it now and return.
      if let sig = signData(data) {
        suite.set(sig, forKey: key + ".hmac")
      }
      return data
    }

    if isDataAuthentic(data, signature: storedSig) {
      return data
    }

    logger.error("HMAC verification failed for '\(key, privacy: .public)' – data may have been tampered with")
    return nil
  }

  /// Removes data and its HMAC signature from UserDefaults.
  private static func signedRemove(forKey key: String) {
    suite.removeObject(forKey: key)
    suite.removeObject(forKey: key + ".hmac")
  }

  // MARK: – Serializable snapshot of a profile (no sessions)
  struct ProfileSnapshot: Codable, Equatable {
    var id: UUID
    var name: String
    var selectedActivity: FamilyActivitySelection
    var createdAt: Date
    var updatedAt: Date
    var blockingStrategyId: String?
    var strategyData: Data?
    var order: Int

    var enableLiveActivity: Bool
    var reminderTimeInSeconds: UInt32?
    var customReminderMessage: String?
    var enableBreaks: Bool
    var breakTimeInMinutes: Int = 15
    var enableAllowMode: Bool
    var enableAllowModeDomains: Bool
    var enableSafariBlocking: Bool

    var domains: [String]?
    var physicalUnblockNFCTagIds: [String]?

    var schedule: BlockedProfileSchedule?
  }

  // MARK: – Serializable snapshot of a session (no profile object)
  struct SessionSnapshot: Codable, Equatable {
    var id: String
    var tag: String
    var blockedProfileId: UUID

    var startTime: Date
    var endTime: Date?

    var breakStartTime: Date?
    var breakEndTime: Date?

    var forceStarted: Bool
  }

  // MARK: – Persisted snapshots keyed by profile ID (UUID string)
  static var profileSnapshots: [String: ProfileSnapshot] {
    get {
      guard let data = verifiedRead(forKey: Key.profileSnapshots.rawValue) else { return [:] }
      return (try? JSONDecoder().decode([String: ProfileSnapshot].self, from: data)) ?? [:]
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        signedWrite(data, forKey: Key.profileSnapshots.rawValue)
      } else {
        logger.error("Failed to encode profileSnapshots, preserving existing data")
      }
    }
  }

  static func snapshot(for profileID: String) -> ProfileSnapshot? {
    profileSnapshots[profileID]
  }

  static func setSnapshot(_ snapshot: ProfileSnapshot, for profileID: String) {
    var all = profileSnapshots
    all[profileID] = snapshot
    profileSnapshots = all
  }

  static func removeSnapshot(for profileID: String) {
    var all = profileSnapshots
    all.removeValue(forKey: profileID)
    profileSnapshots = all
  }

  // MARK: – Persisted array of scheduled sessions
  static var completedSessionsInSchedular: [SessionSnapshot] {
    get {
      guard let data = verifiedRead(forKey: Key.completedScheduleSessions.rawValue) else { return [] }
      return (try? JSONDecoder().decode([SessionSnapshot].self, from: data)) ?? []
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        signedWrite(data, forKey: Key.completedScheduleSessions.rawValue)
      } else {
        logger.error("Failed to encode completedScheduleSessions, preserving existing data")
      }
    }
  }

  // MARK: – Active session (shared between app and extensions)
  static var activeSharedSession: SessionSnapshot? {
    get {
      guard let data = verifiedRead(forKey: Key.activeScheduleSession.rawValue) else { return nil }
      return (try? JSONDecoder().decode(SessionSnapshot.self, from: data)) ?? nil
    }
    set {
      if let newValue {
        if let data = try? JSONEncoder().encode(newValue) {
          signedWrite(data, forKey: Key.activeScheduleSession.rawValue)
        } else {
          logger.error("Failed to encode activeSharedSession, preserving existing data")
        }
      } else {
        signedRemove(forKey: Key.activeScheduleSession.rawValue)
      }
    }
  }

  static func createSessionForSchedular(for profileID: UUID) {
    activeSharedSession = SessionSnapshot(
      id: UUID().uuidString,
      tag: profileID.uuidString,
      blockedProfileId: profileID,
      startTime: Date(),
      forceStarted: true)
  }

  static func createActiveSharedSession(for session: SessionSnapshot) {
    activeSharedSession = session
  }

  static func getActiveSharedSession() -> SessionSnapshot? {
    activeSharedSession
  }

  static func endActiveSharedSession() {
    guard var existingScheduledSession = activeSharedSession else { return }

    existingScheduledSession.endTime = Date()
    completedSessionsInSchedular.append(existingScheduledSession)

    activeSharedSession = nil
  }

  static func flushActiveSession() {
    activeSharedSession = nil
  }

  static func getCompletedSessionsForSchedular() -> [SessionSnapshot] {
    completedSessionsInSchedular
  }

  static func flushCompletedSessionsForSchedular() {
    completedSessionsInSchedular = []
  }

  static func setBreakStartTime(date: Date) {
    activeSharedSession?.breakStartTime = date
  }

  static func setBreakEndTime(date: Date) {
    activeSharedSession?.breakEndTime = date
  }

  static func setEndTime(date: Date) {
    activeSharedSession?.endTime = date
  }

  // MARK: – Widget Deep Link Opaque Tokens (V-11)
  // Maps short random tokens to profile UUIDs so widget URLs don't expose raw UUIDs.

  private static let widgetTokensKey = "widgetDeepLinkTokens"

  /// Returns an opaque token for the given profile ID. Reuses existing token if one exists.
  static func opaqueToken(for profileId: String) -> String {
    var mapping = tokenToProfileMapping()

    // Check if a token already exists for this profile
    if let existing = mapping.first(where: { $0.value == profileId }) {
      return existing.key
    }

    // Generate a short random token (12 hex chars = 6 bytes of entropy)
    let token = (0..<6).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    mapping[token] = profileId
    saveTokenMapping(mapping)
    return token
  }

  /// Resolves an opaque token back to the original profile UUID string. Returns nil if not found.
  static func resolveToken(_ token: String) -> String? {
    let mapping = tokenToProfileMapping()
    return mapping[token]
  }

  private static func tokenToProfileMapping() -> [String: String] {
    guard let data = suite.data(forKey: widgetTokensKey),
      let mapping = try? JSONDecoder().decode([String: String].self, from: data)
    else { return [:] }
    return mapping
  }

  private static func saveTokenMapping(_ mapping: [String: String]) {
    if let data = try? JSONEncoder().encode(mapping) {
      suite.set(data, forKey: widgetTokensKey)
    }
  }
}
