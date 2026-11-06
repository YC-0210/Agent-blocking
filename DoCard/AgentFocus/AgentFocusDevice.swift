import CryptoKit
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import Security

/// Native adapter at the persisted phone interface. Agent shields never clear a legacy store.
enum AgentFocusDevice {
  static let storeName = ManagedSettingsStore.Name("doCardAgentRestrictions")
  static let activityPrefix = "doCardAgentExpiry_"
  typealias Phone = AgentFocusPhone<FamilyActivitySelection>

  enum Failure: Error {
    case unavailable, unauthorized, emptySelection, activeSession
  }

  @MainActor
  static func prepareAuthorization() async throws {
    // AuthorizationCenter starts undetermined in every process. Restore the
    // existing individual grant before opening the native settings store.
    if AuthorizationCenter.shared.authorizationStatus == .notDetermined {
      try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }
  }

  static func receive(_ command: FocusCommand, pairingID: String) throws -> FocusReceipt {
    try phone().receive(command, pairingID: pairingID)
  }
  static func status(pairingID: String? = nil) throws -> Phone.Status? {
    try phone().status(pairingID: pairingID)
  }
  static func pendingReceipts(pairingID: String) throws -> [FocusReceipt] {
    try phone().pendingReceipts(pairingID: pairingID)
  }
  static func acknowledge(_ id: String, pairingID: String) throws {
    try phone().acknowledge(id, pairingID: pairingID)
  }
  static func emergencyUnlock() throws {
    let localPhone: Phone
    do { localPhone = try phone() } catch {
      clearShields()
      throw error
    }
    try localPhone.emergencyUnlock()
  }

  static func reconcile(lockTimeout: TimeInterval? = nil) throws {
    try phone(lockTimeout: lockTimeout).reconcile(
      authorized: authorizationDecision)
  }
  // AuthorizationCenter starts as notDetermined in a newly launched process.
  // Only an explicit denial invalidates the persisted phone approval.
  private static var authorizationDecision: Bool? {
    let read = { () -> Bool? in
      if AuthorizationCenter.shared.authorizationStatus.grantsScreenTimeAccess { return true }
      switch AuthorizationCenter.shared.authorizationStatus {
      case .approved: return true
      case .denied: return false
      case .notDetermined: return nil
      @unknown default: return nil
      }
    }
    return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
  }

  static func intervalStarted(_ activity: DeviceActivityName) {
    handleInterval(activity, event: "start")
  }

  static func intervalEnded(_ activity: DeviceActivityName) {
    handleInterval(activity, event: "end")
  }

  private static func handleInterval(_ activity: DeviceActivityName, event: String) {
    guard activity.rawValue.hasPrefix(activityPrefix) else { return }
    let role = activity.rawValue == activityPrefix + "recovery" ? "recovery" : "primary"
    let trace = role + "_" + event
    recordExpiryEvent(trace + "_entered", activity: activity)
    do {
      // startMonitoring may synchronously wait for its start callback while holding
      // the phone lock. A start wake-up is opportunistic and must never wait on it.
      let ending = event == "end"
      let expired = try phone(lockTimeout: ending ? 0.2 : 0, expiryOnly: true)
        .expire(retryFor: ending ? 5 : 0)
      recordExpiryEvent(trace + (expired ? "_expired" : "_ignored"), activity: activity)
    } catch {
      recordExpiryEvent(trace + "_failed", activity: activity)
    }
  }

  private struct ExpiryEvent: Encodable {
    let event: String
    let at: Double
    let sessionID: String?
    let endAt: Double?
    let activityName: String?
    let nextStartAt: Double?
    let nextEndAt: Double?
  }

  private static func recordExpiryEvent(
    _ event: String, session: AgentFocusSession? = nil, activity: DeviceActivityName? = nil,
    schedule: DeviceActivitySchedule? = nil
  ) {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.DO.version3")
    else { return }
    let next = schedule?.nextInterval
    let entry = ExpiryEvent(
      event: event, at: Date().timeIntervalSince1970 * 1000,
      sessionID: session?.id, endAt: session?.endAt, activityName: activity?.rawValue,
      nextStartAt: next.map { $0.start.timeIntervalSince1970 * 1000 },
      nextEndAt: next.map { $0.end.timeIntervalSince1970 * 1000 })
    // Fixed diagnostic filenames, no app tokens, credentials or legacy model initialization.
    try? JSONEncoder().encode(entry).write(
      to: directory.appendingPathComponent("agent-expiry-" + event + ".json"),
      options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
  }

  static func phone(lockTimeout: TimeInterval? = nil, expiryOnly: Bool = false) throws -> Phone {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.DO.version3")
    else { throw Failure.unavailable }
    // Read on the main queue before taking the phone lock. A cold extension's
    // unknown status cannot override the owner's persisted approval.
    let authorization = expiryOnly ? nil : authorizationDecision
    return Phone(
      directory: directory,
      emergency: AgentEmergencyStorage(read: readEmergency, write: writeEmergency),
      now: { Date().timeIntervalSince1970 * 1000 },
      apply: {
        guard !expiryOnly else { throw Failure.unavailable }
        try install($0, selection: $1, authorization: authorization)
      },
      release: clearShields,
      lockTimeout: lockTimeout,
      summarize: {
        .init(
          applications: $0.applicationTokens.count, categories: $0.categoryTokens.count,
          websites: $0.webDomainTokens.count)
      },
      identify: AgentSelectedAppMetadata.identifiers,
      identifyRevision: AgentSelectedAppMetadata.selectionIdentity)
  }

  static func permitsSelectedAppSharing() -> Bool? {
    let read = { () -> Bool? in
      #if DO_CARD_APP_DATA_ACCESS_PROBE
        if #available(iOS 26.4, *) {
          switch AuthorizationCenter.shared.authorizationStatus {
          case .approvedWithDataAccess: return true
          case .notDetermined: return nil
          default: return false
          }
        }
      #endif
      return false
    }
    return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
  }

  private static var emergencyQuery: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "online.do.card.agent.emergency",
      kSecAttrAccount as String: "cancellation-v1",
      kSecAttrAccessGroup as String: KeychainHelper.sharedAccessGroup,
    ]
  }

  private static func readEmergency() throws -> AgentEmergencyCancellation? {
    var query = emergencyQuery
    query[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else { throw Failure.unavailable }
    return try JSONDecoder().decode(AgentEmergencyCancellation.self, from: data)
  }

  private static func writeEmergency(_ cancellation: AgentEmergencyCancellation) throws {
    let data = try JSONEncoder().encode(cancellation)
    let status = SecItemUpdate(
      emergencyQuery as CFDictionary,
      [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = emergencyQuery
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
        throw Failure.unavailable
      }
    } else if status != errSecSuccess {
      throw Failure.unavailable
    }
  }

  private static func clearShields() {
    ManagedSettingsStore(named: storeName).clearAllSettings()
    // Never synchronously query/stop DeviceActivity from a release callback. After
    // reboot that XPC call can stall and prevent durable expiry from completing.
  }

  private static func install(
    _ session: AgentFocusSession, selection: FamilyActivitySelection, authorization: Bool?
  )
    throws
  {
    // The phone has already validated pairing, saved selection, mode and duration.
    // Reject known denial; unknown defers to the native monitoring operation.
    guard authorization != false else {
      throw Failure.unauthorized
    }
    guard
      !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty
    else { throw Failure.emptySelection }
    let schedules = session.expirySchedules()
    let center = DeviceActivityCenter()
    // Recurring time-of-day windows survive beyond a one-shot calendar interval.
    // Every callback still checks the absolute persisted deadline and can only release.
    let name = DeviceActivityName(activityPrefix + "current")
    let primary = DeviceActivitySchedule(
      intervalStart: schedules.primary.intervalStart,
      intervalEnd: schedules.primary.intervalEnd, repeats: schedules.primary.repeats)
    let recoveryName = DeviceActivityName(activityPrefix + "recovery")
    let recovery = DeviceActivitySchedule(
      intervalStart: schedules.recovery.intervalStart,
      intervalEnd: schedules.recovery.intervalEnd, repeats: schedules.recovery.repeats)
    recordExpiryEvent("primary_registration_entered", session: session, activity: name)
    try center.startMonitoring(name, during: primary)
    recordExpiryEvent("primary_registration_returned", session: session, activity: name)
    recordExpiryEvent("recovery_registration_entered", session: session, activity: recoveryName)
    try center.startMonitoring(recoveryName, during: recovery)
    recordExpiryEvent("recovery_registration_returned", session: session, activity: recoveryName)
    recordExpiryEvent("registered", session: session, activity: name, schedule: primary)
    recordExpiryEvent(
      "recovery_registered", session: session, activity: recoveryName, schedule: recovery)
    let store = ManagedSettingsStore(named: storeName)
    store.shield.applications =
      selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
    store.shield.applicationCategories =
      selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
    store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    store.shield.webDomainCategories =
      selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
  }
}

extension AuthorizationStatus {
  /// Data access is an additional approval, not revocation of Screen Time access.
  var grantsScreenTimeAccess: Bool {
    if self == .approved { return true }
    #if DO_CARD_APP_DATA_ACCESS_PROBE
      if #available(iOS 26.4, *), self == .approvedWithDataAccess { return true }
    #endif
    return false
  }
}

/// Cache contains selected identities only, bound to the exact local application tokens.
/// This lets background delivery describe the same selection without enumerating installed apps.
enum AgentSelectedAppMetadata {
  private struct Entry: Codable {
    let fingerprint: String
    let identifiers: [String]
    let selectionIdentity: String?
  }

  private static var file: URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.DO.version3")?
      .appendingPathComponent("agent-selected-app-identities.json")
  }

  private static func fingerprint(_ selection: FamilyActivitySelection) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let tokens = try selection.applicationTokens.map {
      try encoder.encode($0).base64EncodedString()
    }.sorted()
    return SHA256.hash(data: try JSONEncoder().encode(tokens)).map { String(format: "%02x", $0) }
      .joined()
  }

  static func identifiers(for selection: FamilyActivitySelection) -> [String]? {
    entry(for: selection)?.identifiers
  }

  static func selectionIdentity(for selection: FamilyActivitySelection) -> String? {
    entry(for: selection)?.selectionIdentity
  }

  private static func entry(for selection: FamilyActivitySelection) -> Entry? {
    guard let file, let data = try? Data(contentsOf: file),
      let entry = try? JSONDecoder().decode(Entry.self, from: data),
      entry.fingerprint == (try? fingerprint(selection))
    else { return nil }
    return entry
  }

  private static func clear(_ file: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: file.path) else { return false }
    do {
      try FileManager.default.removeItem(at: file)
      return true
    } catch { return false }
  }

  @MainActor
  static func refresh(_ selection: FamilyActivitySelection) async -> Bool {
    #if DO_CARD_APP_DATA_ACCESS_PROBE
      guard #available(iOS 26.4, *), let file else { return false }
      if AuthorizationCenter.shared.authorizationStatus == .notDetermined { return false }
      guard AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess else {
        return clear(file)
      }
      do {
        let ids: [String]
        if let cached = entry(for: selection) {
          if cached.selectionIdentity != nil { return false }
          // Migrate the previously verified cache without fetching an app inventory again.
          ids = cached.identifiers
        } else {
          let applications = try await FamilyActivityData.shared.installedApplications
          ids = Set(
            applications.compactMap { application -> String? in
              guard let token = application.token, selection.applicationTokens.contains(token),
                let identifier = application.bundleIdentifier,
                identifier.range(
                  of: "^[a-zA-Z0-9-]+(?:\\.[a-zA-Z0-9-]+)+$", options: .regularExpression) != nil,
                identifier.utf8.count <= 255
              else { return nil }
              return identifier
            }
          ).sorted()
        }
        guard ids.count <= 50 else { return false }
        // Recheck after the asynchronous API call; permission may have changed.
        if AuthorizationCenter.shared.authorizationStatus == .notDetermined { return false }
        guard AuthorizationCenter.shared.authorizationStatus == .approvedWithDataAccess else {
          return clear(file)
        }
        let entry = Entry(
          fingerprint: try fingerprint(selection), identifiers: ids,
          selectionIdentity: UUID().uuidString)
        try JSONEncoder().encode(entry).write(
          to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
      } catch {
        // A failed refresh cannot publish a partial or unverified installed-app list.
      }
    #endif
    return false
  }
}
