import FamilyControls
import Foundation

// Main-app-only setup checks. Notification delivery does not load legacy app models.
extension AgentFocusDevice {
  #if !AGENT_BLOCKING
    static var applicationLimit: Int { Entitlements.premiumAppLimit }
  #endif

  static func approve(
    policy: AgentFocusPolicy, selection: FamilyActivitySelection, pairingID: String
  ) throws {
    guard AuthorizationCenter.shared.authorizationStatus.grantsScreenTimeAccess else {
      throw Failure.unauthorized
    }
    guard
      !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty,
      selection.applicationTokens.count <= applicationLimit
    else { throw Failure.emptySelection }
    #if !AGENT_BLOCKING
      guard SharedData.getActiveStrategySharedSession() == nil,
        SharedData.getActiveScheduleSharedSession() == nil,
        !SharedData.profileSnapshots.values.contains(where: {
          $0.schedules.contains(where: { $0.isActive })
        })
      else { throw Failure.activeSession }
    #endif
    try phone().approve(policy: policy, selection: selection, pairingID: pairingID)
  }

  static func updateSelection(
    _ selection: FamilyActivitySelection, pairingID: String, expectedModeID: String
  ) throws {
    guard AuthorizationCenter.shared.authorizationStatus.grantsScreenTimeAccess else {
      throw Failure.unauthorized
    }
    guard
      !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty,
      selection.applicationTokens.count <= applicationLimit
    else { throw Failure.emptySelection }
    try phone(lockTimeout: 0.2).updateSelection(
      selection, pairingID: pairingID, expectedModeID: expectedModeID)
  }

}
