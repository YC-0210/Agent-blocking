import FamilyControls
import Foundation

// Main-app-only setup checks. Notification delivery does not load legacy app models.
extension AgentFocusDevice {
  static func approve(
    policy: AgentFocusPolicy, selection: FamilyActivitySelection, pairingID: String
  ) throws {
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
      throw Failure.unauthorized
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

  static func updateSelection(
    _ selection: FamilyActivitySelection, pairingID: String, expectedModeID: String
  ) throws {
    guard AuthorizationCenter.shared.authorizationStatus == .approved else {
      throw Failure.unauthorized
    }
    guard
      !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
        || !selection.webDomainTokens.isEmpty,
      selection.applicationTokens.count <= Entitlements.premiumAppLimit
    else { throw Failure.emptySelection }
    try phone(lockTimeout: 0.2).updateSelection(
      selection, pairingID: pairingID, expectedModeID: expectedModeID)
  }

}
