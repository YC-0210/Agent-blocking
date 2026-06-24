import CryptoKit
import FamilyControls
import Foundation
import OSLog
import Security

private let logger = Logger(subsystem: "app.docard", category: "SharedData")

/// Represents the user's subscription tier. Defined here so extensions can access it.
enum SubscriptionTier: String, Codable {
    case free
    case premium
}

enum SharedData {
  private static let emergencyUnlockedSchedulePrefix = "emergencyUnlockedSchedule_"
  private static let cardTapSuppressedSchedulePrefix = "cardTapSuppressedSchedule_"
  private static let scheduleSuppressionPrefixes = [
    emergencyUnlockedSchedulePrefix,
    cardTapSuppressedSchedulePrefix,
  ]

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
    case activeStrategySession
    case activeScheduleSession
    case completedScheduleSessions
    case subscriptionTier
    case subscriptionExpirationDate
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
    suite.synchronize()
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
    suite.synchronize()
  }

  // EMERGENCY_UNLOCK_AUDIT: expose thin wrappers so app + extension can reuse
  // the existing signed App Group storage without duplicating HMAC logic.
  static func writeSignedDouble(_ value: Double, forKey key: String) {
    guard let data = try? JSONEncoder().encode(value) else {
      logger.error("Failed to encode Double for signed key '\(key, privacy: .public)'")
      return
    }
    signedWrite(data, forKey: key)
  }

  static func readVerifiedDouble(forKey key: String) -> Double? {
    guard let data = verifiedRead(forKey: key) else { return nil }
    return try? JSONDecoder().decode(Double.self, from: data)
  }

  static func removeSignedValue(forKey key: String) {
    signedRemove(forKey: key)
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

    var schedules: [BlockedProfileSchedule]

    /// Backward-compatible decoder: reads legacy `schedule` key into `schedules` array.
    enum CodingKeys: String, CodingKey {
      case id, name, selectedActivity, createdAt, updatedAt
      case blockingStrategyId, strategyData, order
      case enableLiveActivity, reminderTimeInSeconds, customReminderMessage
      case enableBreaks, breakTimeInMinutes
      case enableAllowMode, enableAllowModeDomains, enableSafariBlocking
      case domains, physicalUnblockNFCTagIds
      case schedules, schedule // legacy key
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      id = try container.decode(UUID.self, forKey: .id)
      name = try container.decode(String.self, forKey: .name)
      selectedActivity = try container.decode(FamilyActivitySelection.self, forKey: .selectedActivity)
      createdAt = try container.decode(Date.self, forKey: .createdAt)
      updatedAt = try container.decode(Date.self, forKey: .updatedAt)
      blockingStrategyId = try container.decodeIfPresent(String.self, forKey: .blockingStrategyId)
      strategyData = try container.decodeIfPresent(Data.self, forKey: .strategyData)
      order = try container.decode(Int.self, forKey: .order)
      enableLiveActivity = try container.decode(Bool.self, forKey: .enableLiveActivity)
      reminderTimeInSeconds = try container.decodeIfPresent(UInt32.self, forKey: .reminderTimeInSeconds)
      customReminderMessage = try container.decodeIfPresent(String.self, forKey: .customReminderMessage)
      enableBreaks = try container.decode(Bool.self, forKey: .enableBreaks)
      breakTimeInMinutes = try container.decodeIfPresent(Int.self, forKey: .breakTimeInMinutes) ?? 15
      enableAllowMode = try container.decode(Bool.self, forKey: .enableAllowMode)
      enableAllowModeDomains = try container.decode(Bool.self, forKey: .enableAllowModeDomains)
      enableSafariBlocking = try container.decode(Bool.self, forKey: .enableSafariBlocking)
      domains = try container.decodeIfPresent([String].self, forKey: .domains)
      physicalUnblockNFCTagIds = try container.decodeIfPresent([String].self, forKey: .physicalUnblockNFCTagIds)

      // Migration: try new `schedules` key first, fall back to legacy `schedule` key
      if let arr = try container.decodeIfPresent([BlockedProfileSchedule].self, forKey: .schedules) {
        schedules = arr
      } else if let single = try container.decodeIfPresent(BlockedProfileSchedule.self, forKey: .schedule) {
        schedules = [single]
      } else {
        schedules = []
      }
    }

    init(
      id: UUID, name: String, selectedActivity: FamilyActivitySelection,
      createdAt: Date, updatedAt: Date, blockingStrategyId: String? = nil,
      strategyData: Data? = nil, order: Int, enableLiveActivity: Bool,
      reminderTimeInSeconds: UInt32? = nil, customReminderMessage: String? = nil,
      enableBreaks: Bool, breakTimeInMinutes: Int = 15,
      enableAllowMode: Bool, enableAllowModeDomains: Bool,
      enableSafariBlocking: Bool, domains: [String]? = nil,
      physicalUnblockNFCTagIds: [String]? = nil,
      schedules: [BlockedProfileSchedule] = []
    ) {
      self.id = id
      self.name = name
      self.selectedActivity = selectedActivity
      self.createdAt = createdAt
      self.updatedAt = updatedAt
      self.blockingStrategyId = blockingStrategyId
      self.strategyData = strategyData
      self.order = order
      self.enableLiveActivity = enableLiveActivity
      self.reminderTimeInSeconds = reminderTimeInSeconds
      self.customReminderMessage = customReminderMessage
      self.enableBreaks = enableBreaks
      self.breakTimeInMinutes = breakTimeInMinutes
      self.enableAllowMode = enableAllowMode
      self.enableAllowModeDomains = enableAllowModeDomains
      self.enableSafariBlocking = enableSafariBlocking
      self.domains = domains
      self.physicalUnblockNFCTagIds = physicalUnblockNFCTagIds
      self.schedules = schedules
    }

    func encode(to encoder: Encoder) throws {
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode(id, forKey: .id)
      try container.encode(name, forKey: .name)
      try container.encode(selectedActivity, forKey: .selectedActivity)
      try container.encode(createdAt, forKey: .createdAt)
      try container.encode(updatedAt, forKey: .updatedAt)
      try container.encodeIfPresent(blockingStrategyId, forKey: .blockingStrategyId)
      try container.encodeIfPresent(strategyData, forKey: .strategyData)
      try container.encode(order, forKey: .order)
      try container.encode(enableLiveActivity, forKey: .enableLiveActivity)
      try container.encodeIfPresent(reminderTimeInSeconds, forKey: .reminderTimeInSeconds)
      try container.encodeIfPresent(customReminderMessage, forKey: .customReminderMessage)
      try container.encode(enableBreaks, forKey: .enableBreaks)
      try container.encode(breakTimeInMinutes, forKey: .breakTimeInMinutes)
      try container.encode(enableAllowMode, forKey: .enableAllowMode)
      try container.encode(enableAllowModeDomains, forKey: .enableAllowModeDomains)
      try container.encode(enableSafariBlocking, forKey: .enableSafariBlocking)
      try container.encodeIfPresent(domains, forKey: .domains)
      try container.encodeIfPresent(physicalUnblockNFCTagIds, forKey: .physicalUnblockNFCTagIds)
      try container.encode(schedules, forKey: .schedules)
    }
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

    /// How the session was initiated: "manual" | "scheduled" | "shortcut" | "deeplink"
    var triggerSource: String = "manual"
    /// How the session ended: "card_tap" | "timer_expired" | "emergency_unlock" | nil
    var endReason: String?
    /// Immutable timer duration captured when the session starts.
    /// Used for timer-session recovery even if the profile's strategyData changes later.
    var plannedDurationMinutes: Int?
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
  static var activeStrategySharedSession: SessionSnapshot? {
    get {
      guard let data = verifiedRead(forKey: Key.activeStrategySession.rawValue) else { return nil }
      return (try? JSONDecoder().decode(SessionSnapshot.self, from: data)) ?? nil
    }
    set {
      if let newValue {
        if let data = try? JSONEncoder().encode(newValue) {
          signedWrite(data, forKey: Key.activeStrategySession.rawValue)
        } else {
          logger.error("Failed to encode activeStrategySharedSession, preserving existing data")
        }
      } else {
        signedRemove(forKey: Key.activeStrategySession.rawValue)
      }
    }
  }

  static var activeScheduleSharedSession: SessionSnapshot? {
    get {
      guard let data = verifiedRead(forKey: Key.activeScheduleSession.rawValue) else { return nil }
      return (try? JSONDecoder().decode(SessionSnapshot.self, from: data)) ?? nil
    }
    set {
      if let newValue {
        if let data = try? JSONEncoder().encode(newValue) {
          signedWrite(data, forKey: Key.activeScheduleSession.rawValue)
        } else {
          logger.error("Failed to encode activeScheduleSharedSession, preserving existing data")
        }
      } else {
        signedRemove(forKey: Key.activeScheduleSession.rawValue)
      }
    }
  }

  static func createSessionForSchedular(for profileID: UUID) {
    activeScheduleSharedSession = SessionSnapshot(
      id: UUID().uuidString,
      tag: profileID.uuidString,
      blockedProfileId: profileID,
      startTime: Date(),
      forceStarted: true,
      triggerSource: "scheduled")
  }

  static func createActiveStrategySharedSession(for session: SessionSnapshot) {
    activeStrategySharedSession = session
  }

  static func getActiveStrategySharedSession() -> SessionSnapshot? {
    activeStrategySharedSession
  }

  static func getActiveScheduleSharedSession() -> SessionSnapshot? {
    activeScheduleSharedSession
  }

  static func getActiveSharedSession() -> SessionSnapshot? {
    activeStrategySharedSession ?? activeScheduleSharedSession
  }

  static func endActiveStrategySharedSession(endReason: String = "timer_expired") {
    guard var existingSession = activeStrategySharedSession else { return }

    existingSession.endTime = Date()
    existingSession.endReason = endReason
    completedSessionsInSchedular.append(existingSession)

    activeStrategySharedSession = nil
  }

  static func endActiveScheduleSharedSession(endReason: String = "timer_expired") {
    guard var existingSession = activeScheduleSharedSession else { return }

    existingSession.endTime = Date()
    existingSession.endReason = endReason
    completedSessionsInSchedular.append(existingSession)

    activeScheduleSharedSession = nil
  }

  static func flushActiveStrategySession() {
    activeStrategySharedSession = nil
  }

  static func flushActiveScheduleSession() {
    activeScheduleSharedSession = nil
  }

  static func getCompletedSessionsForSchedular() -> [SessionSnapshot] {
    completedSessionsInSchedular
  }

  static func flushCompletedSessionsForSchedular() {
    completedSessionsInSchedular = []
  }

  static func setBreakStartTime(date: Date) {
    guard var activeSession = activeStrategySharedSession else { return }
    activeSession.breakStartTime = date
    activeStrategySharedSession = activeSession
  }

  static func setBreakEndTime(date: Date) {
    guard var activeSession = activeStrategySharedSession else { return }
    activeSession.breakEndTime = date
    activeStrategySharedSession = activeSession
  }

  static func setEndTime(date: Date) {
    guard var activeSession = activeStrategySharedSession else { return }
    activeSession.endTime = date
    activeStrategySharedSession = activeSession
  }

  static func currentScheduledProfileSnapshot(now: Date = Date(), calendar: Calendar = .current)
    -> ProfileSnapshot?
  {
    profileSnapshots.values
      .filter { snapshot in
        isScheduleCurrentlyActiveAndUnsuppressed(profile: snapshot, now: now, calendar: calendar)
      }
      .sorted { $0.updatedAt > $1.updatedAt }
      .first
  }

  static func isScheduleCurrentlyActiveAndUnsuppressed(
    profile: ProfileSnapshot,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> Bool {
    hasUnsuppressedScheduleWindow(profile, now: now, calendar: calendar)
  }

  private static func hasUnsuppressedScheduleWindow(
    _ snapshot: ProfileSnapshot,
    now: Date,
    calendar: Calendar
  ) -> Bool {
    return snapshot.schedules.contains { schedule in
      guard schedule.isCurrentlyInWindow(now: now, calendar: calendar) else { return false }
      guard let activityWeekday = activeWeekdayForCurrentWindow(
        schedule: schedule,
        now: now,
        calendar: calendar
      ) else {
        return false
      }

      let activityId = "\(snapshot.id.uuidString).\(schedule.id.uuidString)_\(activityWeekday.rawValue)"

      for prefix in scheduleSuppressionPrefixes {
        let suppressKey = prefix + activityId
        guard let windowEndTimestamp = readVerifiedDouble(forKey: suppressKey) else { continue }

        if now < Date(timeIntervalSince1970: windowEndTimestamp) {
          return false
        }

        removeSignedValue(forKey: suppressKey)
      }

      return true
    }
  }

  private static func activeWeekdayForCurrentWindow(
    schedule: BlockedProfileSchedule,
    now: Date,
    calendar: Calendar
  ) -> Weekday? {
    let currentWeekdayRaw = calendar.component(.weekday, from: now)
    let currentTotalMinutes =
      (calendar.component(.hour, from: now) * 60) + calendar.component(.minute, from: now)
    let startTotalMinutes = schedule.startHour * 60 + schedule.startMinute
    let endTotalMinutes = schedule.endHour * 60 + schedule.endMinute

    guard let currentWeekday = Weekday(rawValue: currentWeekdayRaw) else { return nil }

    if !schedule.isNextDay {
      return currentWeekday
    }

    if schedule.days.contains(currentWeekday), currentTotalMinutes >= startTotalMinutes {
      return currentWeekday
    }

    let previousWeekdayRaw = currentWeekdayRaw == 1 ? 7 : currentWeekdayRaw - 1
    guard
      let previousWeekday = Weekday(rawValue: previousWeekdayRaw),
      schedule.days.contains(previousWeekday),
      currentTotalMinutes < endTotalMinutes
    else {
      return nil
    }

    return previousWeekday
  }

  private static func endDateForCurrentWindow(
    schedule: BlockedProfileSchedule,
    activityWeekday: Weekday,
    now: Date,
    calendar: Calendar
  ) -> Date? {
    let nowWeekdayRaw = calendar.component(.weekday, from: now)
    let startsToday = activityWeekday.rawValue == nowWeekdayRaw
    let baseDate = schedule.isNextDay && startsToday
      ? calendar.date(byAdding: .day, value: 1, to: now)
      : now

    guard let baseDate else { return nil }

    return calendar.date(
      bySettingHour: schedule.endHour,
      minute: schedule.endMinute,
      second: 0,
      of: baseDate
    )
  }

  private static func currentScheduleSuppressionWindows(
    for profile: ProfileSnapshot,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [String: Date] {
    profile.schedules.reduce(into: [:]) { suppressions, schedule in
      guard schedule.isCurrentlyInWindow(now: now, calendar: calendar) else { return }
      guard
        let activityWeekday = activeWeekdayForCurrentWindow(
          schedule: schedule,
          now: now,
          calendar: calendar
        ),
        let windowEnd = endDateForCurrentWindow(
          schedule: schedule,
          activityWeekday: activityWeekday,
          now: now,
          calendar: calendar
        )
      else {
        return
      }

      let activityId = "\(profile.id.uuidString).\(schedule.id.uuidString)_\(activityWeekday.rawValue)"
      suppressions[activityId] = windowEnd
    }
  }

  private static func writeScheduleSuppressionFlags(
    for profile: ProfileSnapshot,
    prefix: String,
    now: Date = Date(),
    calendar: Calendar = .current
  ) {
    let suppressions = currentScheduleSuppressionWindows(for: profile, now: now, calendar: calendar)
    for (activityId, windowEnd) in suppressions {
      let suppressKey = prefix + activityId
      writeSignedDouble(windowEnd.timeIntervalSince1970, forKey: suppressKey)
    }
  }

  static func writeEmergencyUnlockSuppressionFlags(
    for profile: ProfileSnapshot,
    triggerSource: String
  ) {
    guard triggerSource == "scheduled" else { return }
    writeScheduleSuppressionFlags(
      for: profile,
      prefix: emergencyUnlockedSchedulePrefix
    )
  }

  static func writeCardTapSuppressionFlags(
    for profile: ProfileSnapshot,
    triggerSource: String,
    endReason: String?
  ) {
    guard triggerSource == "scheduled", endReason == "card_tap" else { return }
    writeScheduleSuppressionFlags(
      for: profile,
      prefix: cardTapSuppressedSchedulePrefix
    )
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

  // MARK: – Subscription State (shared with extensions)

  /// The current subscription tier. Extensions read this to enforce free-tier limits.
  static var subscriptionTier: SubscriptionTier {
    get {
      guard let data = verifiedRead(forKey: Key.subscriptionTier.rawValue),
            let tier = try? JSONDecoder().decode(SubscriptionTier.self, from: data)
      else { return .free }
      return tier
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        signedWrite(data, forKey: Key.subscriptionTier.rawValue)
      }
    }
  }

  /// The subscription expiration date. Used for billing grace period logic.
  static var subscriptionExpirationDate: Date? {
    get {
      guard let data = verifiedRead(forKey: Key.subscriptionExpirationDate.rawValue),
            let date = try? JSONDecoder().decode(Date.self, from: data)
      else { return nil }
      return date
    }
    set {
      if let newValue {
        if let data = try? JSONEncoder().encode(newValue) {
          signedWrite(data, forKey: Key.subscriptionExpirationDate.rawValue)
        }
      } else {
        signedRemove(forKey: Key.subscriptionExpirationDate.rawValue)
      }
    }
  }

  /// Checks the effective tier, accounting for App Store billing grace period (16 days).
  /// Extensions should use this instead of reading `subscriptionTier` directly.
  static var effectiveSubscriptionTier: SubscriptionTier {
    #if DEBUG
    if let forced = debugForcedTier { return forced }
    #endif
    let tier = subscriptionTier
    if tier == .premium { return .premium }

    // Grace period: if subscription expired within the last 16 days, treat as premium
    if let expiration = subscriptionExpirationDate {
      let gracePeriod: TimeInterval = 16 * 24 * 60 * 60
      if Date().timeIntervalSince(expiration) < gracePeriod {
        return .premium
      }
    }

    return .free
  }

  #if DEBUG
  /// Debug-only override for `effectiveSubscriptionTier`. Lets a developer preview
  /// the free (or premium) experience on a real device without changing their real
  /// subscription. Stored in the App Group so the extensions honor it too. Compiled
  /// out entirely in release builds — it can never affect the App Store version.
  /// `nil` = use the real tier.
  static var debugForcedTier: SubscriptionTier? {
    get {
      guard let raw = suite.string(forKey: "debugForcedSubscriptionTier") else { return nil }
      return SubscriptionTier(rawValue: raw)
    }
    set {
      if let newValue {
        suite.set(newValue.rawValue, forKey: "debugForcedSubscriptionTier")
      } else {
        suite.removeObject(forKey: "debugForcedSubscriptionTier")
      }
      suite.synchronize()
    }
  }
  #endif
}
