import Combine
import Foundation

/// Remote policy is kept in memory so a network outage cannot strand an offline user.
struct AppUpdateConfiguration: Decodable, Equatable {
  let minimumVersion: String
  let updateMessage: String?
  let enabled: Bool?

  func requiresUpdate(installedVersion: String) -> Bool {
    guard enabled != false,
      let installed = Self.components(installedVersion),
      let minimum = Self.components(minimumVersion)
    else { return false }
    return installed.lexicographicallyPrecedes(minimum)
  }

  private static func components(_ version: String) -> [Int]? {
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    guard (1...3).contains(parts.count) else { return nil }
    var numbers: [Int] = []
    for part in parts {
      guard !part.isEmpty, part.utf8.allSatisfy({ (48...57).contains($0) }),
        let number = Int(part)
      else { return nil }
      numbers.append(number)
    }
    return numbers + Array(repeating: 0, count: 3 - numbers.count)
  }
}

/// Recovery and authorization finish in their existing UI before navigation is gated.
enum AppUpdatePolicy {
  static func shouldGate(
    updateRequired: Bool, isBlocking: Bool, isOnboarding: Bool, isAuthorized: Bool
  ) -> Bool {
    updateRequired && !isBlocking && !isOnboarding && isAuthorized
  }
}

@MainActor
final class AppUpdateManager: ObservableObject {
  static let configurationURL = URL(string: "https://do-card.online/app-config.json")!
  static let appStoreURL = URL(string: "https://apps.apple.com/app/id6758519666")!

  @Published private(set) var requiredUpdate: AppUpdateConfiguration?
  @Published private(set) var isChecking = false

  private let installedVersion: String
  private let endpoint: URL
  private let session: URLSession

  init(
    installedVersion: String = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString")
      as? String ?? "",
    endpoint: URL = AppUpdateManager.configurationURL,
    session: URLSession? = nil
  ) {
    self.installedVersion = installedVersion
    self.endpoint = endpoint
    if let session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.ephemeral
      configuration.timeoutIntervalForRequest = 8
      configuration.timeoutIntervalForResource = 10
      configuration.urlCache = nil
      self.session = URLSession(configuration: configuration)
    }
  }

  func checkForUpdate() async {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }
    do {
      guard endpoint.scheme == "https" else { throw URLError(.badURL) }
      var request = URLRequest(
        url: endpoint, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
        timeoutInterval: 8)
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200,
        http.url?.scheme == "https", data.count <= 16_384
      else { throw URLError(.badServerResponse) }
      let configuration = try JSONDecoder().decode(AppUpdateConfiguration.self, from: data)
      requiredUpdate =
        configuration.requiresUpdate(installedVersion: installedVersion)
        ? configuration : nil
    } catch {
      // A failed refresh also clears a previous requirement, allowing offline use.
      requiredUpdate = nil
    }
  }
}
