import SwiftUI

class NavigationManager: ObservableObject {
  @Published var profileId: String? = nil
  @Published var link: URL? = nil

  @Published var navigateToProfileId: String? = nil

  func handleLink(_ url: URL) {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
    guard let path = components?.path else { return }

    let parts = path.split(separator: "/")
    if let basePath = parts[safe: 0], let rawToken = parts[safe: 1] {
      // SECURITY (V-11): Resolve opaque token to real profile UUID.
      // Falls back to using the raw value for backwards compatibility with
      // existing deep links that may still contain direct UUIDs.
      let resolvedId = SharedData.resolveToken(String(rawToken)) ?? String(rawToken)

      switch String(basePath) {
      case "profile":
        self.profileId = resolvedId
        self.link = url
      case "navigate":
        self.navigateToProfileId = resolvedId
        self.link = url
      default:
        break
      }
    }
  }

  func clearNavigation() {
    profileId = nil
    link = nil
    navigateToProfileId = nil
  }
}
