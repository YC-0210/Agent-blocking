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
      switch AuthorizationCenter.shared.authorizationStatus {
      case .approved: return true
      case .denied: return false
      case .notDetermined: return nil
      @unknown default: return nil
      }
    }
    return Thread.isMainThread ? read() : DispatchQueue.main.sync(execute: read)
  }

  static func intervalEnded(_ activity: DeviceActivityName) {
    guard activity.rawValue.hasPrefix(activityPrefix) else { return }
    try? reconcile()
  }

  static func phone(lockTimeout: TimeInterval? = nil) throws -> Phone {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.DO.version3")
    else { throw Failure.unavailable }
    // Read on the main queue before taking the phone lock. A cold extension's
    // unknown status cannot override the owner's persisted approval.
    let authorization = authorizationDecision
    return Phone(
      directory: directory,
      emergency: AgentEmergencyStorage(read: readEmergency, write: writeEmergency),
      now: { Date().timeIntervalSince1970 * 1000 },
      apply: { try install($0, selection: $1, authorization: authorization) },
      release: clearShields,
      lockTimeout: lockTimeout)
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
    let center = DeviceActivityCenter()
    center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(activityPrefix) })
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
    let now = Date()
    let end = Date(timeIntervalSince1970: session.endAt / 1000)
    // APNs delivery and restoration can leave less than Apple's 15-minute minimum.
    // Backdate only the monitoring window, never the approved end or shield duration.
    // One extra second preserves the minimum after DateComponents truncation.
    let monitoringStart = min(now, end.addingTimeInterval(-901))
    var start = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: monitoringStart)
    var finish = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: end)
    start.timeZone = .current
    finish.timeZone = .current
    let center = DeviceActivityCenter()
    let name = DeviceActivityName(activityPrefix + session.id)
    if !center.activities.contains(name) {
      try center.startMonitoring(
        name,
        during: DeviceActivitySchedule(
          intervalStart: start, intervalEnd: finish, repeats: false))
    }
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
