import Darwin
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Shared by the app and monitor. Agent shields never clear the existing card/schedule store.
enum AgentFocusDevice {
  static let storeName = ManagedSettingsStore.Name("doCardAgentRestrictions")
  static let activityPrefix = "doCardAgentExpiry_"

  struct Record: Codable {
    var policy: AgentFocusPolicy?
    var selection: FamilyActivitySelection?
    var state = AgentFocusState()
    var receipts: [FocusReceipt] = []
  }

  enum Failure: Error {
    case unavailable, unauthorized, subscriptionRequired, emptySelection, activeSession
  }

  static func withRecord<T>(_ operation: (inout Record) throws -> T) throws -> T {
    guard
      let directory = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.DO.version3")
    else { throw Failure.unavailable }
    let lockURL = directory.appendingPathComponent("agent-focus.lock")
    let fd = open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { throw Failure.unavailable }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw Failure.unavailable }
    defer { flock(fd, LOCK_UN) }
    let url = directory.appendingPathComponent("agent-focus.json")
    var record: Record
    if FileManager.default.fileExists(atPath: url.path) {
      record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
    } else {
      record = Record()
    }
    let result = try operation(&record)
    try JSONEncoder().encode(record).write(
      to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    return result
  }

  static func approve(policy: AgentFocusPolicy, selection: FamilyActivitySelection) throws {
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
      }
      )
    else { throw Failure.activeSession }
    try withRecord { record in
      guard record.state.session == nil else { throw Failure.activeSession }
      record.policy = policy
      record.selection = selection
      // Keep sequence and emergency cutoff when replacing a policy.
      record.state.lastReceipt = nil
    }
  }

  static func receive(_ command: FocusCommand) throws -> FocusReceipt {
    try withRecord { record in
      guard let policy = record.policy, let selection = record.selection else {
        throw Failure.unavailable
      }
      let phone = controller(policy: policy, selection: selection, state: record.state)
      let receipt = phone.receive(command, now: Date().timeIntervalSince1970 * 1000)
      record.state = phone.state
      if !record.receipts.contains(where: { $0.id == receipt.id }) {
        record.receipts.append(receipt)
      }
      return receipt
    }
  }

  static func emergencyUnlock() throws {
    // Hardware release remains available even if the record is missing or corrupt.
    ManagedSettingsStore(named: storeName).clearAllSettings()
    try withRecord { record in
      if let session = record.state.session {
        DeviceActivityCenter().stopMonitoring([activityName(session.id)])
      }
      record.state.session = nil
      record.state.lastReceipt = nil
      record.state.lastEmergencyAt = Date().timeIntervalSince1970 * 1000
    }
  }

  static func reconcile() throws {
    try withRecord { record in
      guard let policy = record.policy, let selection = record.selection else { return }
      let phone = controller(policy: policy, selection: selection, state: record.state)
      if AuthorizationCenter.shared.authorizationStatus != .approved
        || SharedData.effectiveSubscriptionTier != .premium
      {
        try phone.emergencyUnlock(now: Date().timeIntervalSince1970 * 1000)
      } else {
        try phone.restore(now: Date().timeIntervalSince1970 * 1000)
      }
      record.state = phone.state
    }
  }

  static func intervalEnded(_ activity: DeviceActivityName) {
    guard activity.rawValue.hasPrefix(activityPrefix) else { return }
    // Reconcile checks the CURRENT absolute end; a late callback cannot end a new session.
    try? reconcile()
  }

  private static func activityName(_ id: String) -> DeviceActivityName {
    DeviceActivityName(activityPrefix + id)
  }

  private static func controller(
    policy: AgentFocusPolicy, selection: FamilyActivitySelection, state: AgentFocusState
  ) -> AgentFocusController {
    AgentFocusController(
      policy: policy, state: state,
      start: { session in
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
        // Register independent local expiry BEFORE applying any shields.
        let now = Date()
        let end = Date(timeIntervalSince1970: session.endAt / 1000)
        var start = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second], from: now)
        var finish = Calendar.current.dateComponents(
          [.year, .month, .day, .hour, .minute, .second], from: end)
        start.timeZone = .current
        finish.timeZone = .current
        let center = DeviceActivityCenter()
        if !center.activities.contains(activityName(session.id)) {
          try center.startMonitoring(
            activityName(session.id),
            during: DeviceActivitySchedule(
              intervalStart: start, intervalEnd: finish, repeats: false))
        }
        let store = ManagedSettingsStore(named: storeName)
        store.shield.applications =
          selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories =
          selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains =
          selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories =
          selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
      },
      stop: {
        ManagedSettingsStore(named: storeName).clearAllSettings()
        if let session = state.session {
          DeviceActivityCenter().stopMonitoring([activityName(session.id)])
        }
      })
  }
}
