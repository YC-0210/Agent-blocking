import Combine
import Dispatch
import FamilyControls

@MainActor
final class RequestAuthorizer: ObservableObject {
  @Published private(set) var isAuthorized = false
  private var observation: AnyCancellable?

  init() {
    isAuthorized = AuthorizationCenter.shared.authorizationStatus.grantsScreenTimeAccess
    observation = AuthorizationCenter.shared.$authorizationStatus
      .receive(on: DispatchQueue.main)
      .sink { [weak self] status in
        self?.isAuthorized = status.grantsScreenTimeAccess
      }
  }

  func requestAuthorization() {
    Task {
      try? await AuthorizationCenter.shared.requestAuthorization(for: .individual)
      isAuthorized = AuthorizationCenter.shared.authorizationStatus.grantsScreenTimeAccess
    }
  }
}
