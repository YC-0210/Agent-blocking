import Combine
import FamilyControls
import ManagedSettings
import SwiftUI

@MainActor
class RequestAuthorizer: ObservableObject {
  @Published var isAuthorized = false

  private var cancellables = Set<AnyCancellable>()

  init() {
    // Set initial state from current authorization status
    isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved

    // Observe authorization changes (e.g. user revokes Screen Time access)
    startObservingAuthorizationChanges()
  }

  func requestAuthorization() {
    Task {
      do {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        print("Individual authorization successful")
        self.isAuthorized = true
      } catch {
        print("Error requesting authorization: \(error)")
        self.isAuthorized = false
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

        if wasAuthorized && status != .approved {
          print("⚠️ Family Controls authorization was revoked. Clearing restrictions.")
          // Clear any active restrictions since we no longer have permission
          let blocker = AppBlockerUtil()
          blocker.deactivateRestrictions()
        }
      }
      .store(in: &cancellables)
  }
}
