import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

@MainActor
class RequestAuthorizer: ObservableObject {
  @Published var isAuthorized = false

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
}
