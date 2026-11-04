import Combine
import FamilyControls
import ManagedSettings
import OSLog
import SwiftUI

private let raLog = Logger(subsystem: "online.do.card.app", category: "RequestAuthorizer")

@MainActor
class RequestAuthorizer: ObservableObject {
  @Published var isAuthorized = false

  private var cancellables = Set<AnyCancellable>()

  init() {
    // Set initial state from current authorization status
    isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    SharedData.recordRetentionAuthorization(approved: isAuthorized)

    // Observe authorization changes (e.g. user revokes Screen Time access)
    startObservingAuthorizationChanges()
  }

  func requestAuthorization() {
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        raLog.debug("Individual authorization successful")
        self.isAuthorized = true
        SharedData.recordRetentionAuthorization(
          approved: AuthorizationCenter.shared.authorizationStatus == .approved)
      } catch {
        raLog.error("Error requesting authorization: \(error)")
        self.isAuthorized = false
        SharedData.recordRetentionAuthorization(
          approved: AuthorizationCenter.shared.authorizationStatus == .approved)
      }
    }
  }

  func getAuthorizationStatus() -> AuthorizationStatus {
    return AuthorizationCenter.shared.authorizationStatus
  }

  // MARK: - Authorization Change Observation

  private func startObservingAuthorizationChanges() {
    AuthorizationCenter.shared.$authorizationStatus
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        let wasAuthorized = self?.isAuthorized ?? false
        self?.isAuthorized = (status == .approved)
        SharedData.recordRetentionAuthorization(approved: status == .approved)

        if wasAuthorized && status != .approved {
          raLog.warning("⚠️ Family Controls authorization was revoked. Clearing restrictions.")
          // Clear any active restrictions since we no longer have permission
          let blocker = AppBlockerUtil()
          blocker.deactivateRestrictions()
        }
      }
      .store(in: &cancellables)
  }
}
