import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Native adapter at the persisted phone interface. Agent shields never clear a legacy store.
enum AgentFocusDevice {
  static let storeName = ManagedSettingsStore.Name("doCardAgentRestrictions")
  static let activityPrefix = "doCardAgentExpiry_"
  typealias Phone = AgentFocusPhone<FamilyActivitySelection>

  enum Failure: Error {
    case unavailable, unauthorized, subscriptionRequired, emptySelection, activeSession
  }

  static func approve(
    policy: AgentFocusPolicy, selection: FamilyActivitySelection, pairingID: String
  ) throws {
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
      throw Failure.unauthorized
    }
    guard SharedData.effectiveSubscriptionTier == .premium else {
      throw Failure.subscriptionRequired
    }
    guard
      !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty,
      selection.applicationTokens.count <= Entitlements.premiumAppLimit
    else { throw Failure.emptySelection }
    guard SharedData.getActiveStrategySharedSession() == nil,
      SharedData.getActiveScheduleSharedSession() == nil,
      !SharedData.profileSnapshots.values.contains(where: {
        $0.schedules.contains(where: { $0.isActive })
      })
    else { throw Failure.activeSession }
    try phone().approve(policy: policy, selection: selection, pairingID: pairingID)
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

  static func reconcile() throws {
    try phone().reconcile(
      authorized: AuthorizationCenter.shared.authorizationStatus == .approved
        && SharedData.effectiveSubscriptionTier == .premium)
  }
  static func intervalEnded(_ activity: DeviceActivityName) {
    guard activity.rawValue.hasPrefix(activityPrefix) else { return }
    try? reconcile()
  }

  private static func phone() throws -> Phone {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.DO.version3")
    else { throw Failure.unavailable }
    return Phone(
      directory: directory, now: { Date().timeIntervalSince1970 * 1000 },
      apply: install, release: clearShields)
  }

  private static func clearShields() {
    ManagedSettingsStore(named: storeName).clearAllSettings()
    let center = DeviceActivityCenter()
    center.stopMonitoring(center.activities.filter { $0.rawValue.hasPrefix(activityPrefix) })
  }

  private static func install(_ session: AgentFocusSession, selection: FamilyActivitySelection)
    throws
  {
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
      throw Failure.unauthorized
    }
    guard SharedData.effectiveSubscriptionTier == .premium else {
      throw Failure.subscriptionRequired
    }
    guard
      !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty
    else { throw Failure.emptySelection }
    let now = Date()
    let end = Date(timeIntervalSince1970: session.endAt / 1000)
    var start = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: now)
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
