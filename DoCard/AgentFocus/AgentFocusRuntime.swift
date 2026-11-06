import Combine
import FamilyControls
import Foundation
import Security
import UIKit
import UserNotifications

private final class AgentFocusRedirectPolicy: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) { completionHandler(nil) }
}

@MainActor
final class AgentFocusRuntime: ObservableObject {
  static let shared = AgentFocusRuntime()
  let enabled = true
  @Published var configured = false
  @Published var message = ""
  @Published var setupRelay = ""
  @Published var setupCode = ""
  @Published private(set) var focusStatus: AgentFocusDevice.Phone.Status?
  @Published private(set) var connectionPending = false
  private var syncing = false
  private var pushToken: String?
  private let redirectPolicy = AgentFocusRedirectPolicy()
  private lazy var transport = URLSession(
    configuration: .ephemeral, delegate: redirectPolicy, delegateQueue: nil)

  typealias Pairing = AgentFocusPairing
  private struct Redeemed: Decodable {
    let deviceId: String
    let deviceToken: String
  }
  private struct Code: Encodable { let code: String }
  enum Failure: Error {
    case invalidRelay, requestFailed, missingPairing
    case keychain(OSStatus)
  }

  init() {
    if let pairing = try? AgentFocusPairingStore.load() {
      do {
        focusStatus = try AgentFocusDevice.phone(lockTimeout: 0.2).status(
          pairingID: pairing.deviceId)
        configured = focusStatus != nil
      } catch {
        // A saved pairing with temporarily unreadable state is not a fresh setup.
        configured = true
      }
    }
  }

  private func refreshFocusStatus(pairingID: String? = nil) {
    // A busy notification extension must not stall the UI or look like a finished session.
    focusStatus = try? AgentFocusDevice.phone(lockTimeout: 0.2).status(pairingID: pairingID)
  }

  func openSetup(_ url: URL) -> Bool {
    guard url.scheme == "docard-agent", url.host == "setup" else { return false }
    guard !StrategyManager.shared.activeSessionStatus.isBlocking,
      !SharedData.profileSnapshots.values.contains(where: {
        $0.schedules.contains(where: { $0.isActive })
      }
      )
    else {
      message = String(
        localized: "End existing sessions and disable scheduled modes before agent setup.",
        table: "AgentFocus")
      return false
    }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if configured {
      if (try? AgentFocusDevice.status()?.session) != nil {
        message = String(
          localized: "End the current session before changing agent setup.", table: "AgentFocus")
        return true
      }
      configured = false
    }
    setupRelay = query.first(where: { $0.name == "relay" })?.value ?? ""
    setupCode = query.first(where: { $0.name == "code" })?.value ?? ""
    return true
  }

  func approve(
    relay: String, code: String, selection: FamilyActivitySelection,
    maximumMinutes: Int, startMinute: Int, endMinute: Int
  ) async {
    do {
      guard let url = URL(string: relay),
        let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
        parts.scheme == "https", parts.host != nil, parts.user == nil, parts.password == nil,
        parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/",
        !code.isEmpty, (15...1440).contains(maximumMinutes),
        startMinute >= 0, endMinute <= 1440, startMinute < endMinute
      else { throw Failure.invalidRelay }
      let policy = AgentFocusPolicy(
        modeID: UUID().uuidString, maximumMinutes: maximumMinutes,
        startMinute: startMinute, endMinute: endMinute, timeZone: TimeZone.current.identifier)
      let redeemedData = try await request(
        relay: url, path: "v1/pairings/redeem", body: Code(code: code))
      let redeemed = try JSONDecoder().decode(Redeemed.self, from: redeemedData)
      try AgentFocusDevice.approve(
        policy: policy, selection: selection, pairingID: redeemed.deviceId)
      try AgentFocusPairingStore.save(
        Pairing(relay: url, deviceId: redeemed.deviceId, deviceToken: redeemed.deviceToken))
      configured = true
      message = String(
        localized: "Connected. Return to your agent to manage focus.", table: "AgentFocus")
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound,
      ])
      UIApplication.shared.registerForRemoteNotifications()
      await sync()
    } catch {
      message =
        String(
          localized:
            "Setup failed. Check Screen Time access, app selection, relay address and pairing code, then try again.",
          table: "AgentFocus")
    }
  }

  func emergencyUnlock() {
    do {
      try AgentFocusDevice.emergencyUnlock()
      message = String(
        localized: "Agent session ended. Your agent remains connected.", table: "AgentFocus")
    } catch {
      message = String(
        localized:
          "Agent shields cleared. Could not save the session ending; reopen DO Card to retry.",
        table: "AgentFocus")
    }
    refreshFocusStatus()
    Task { await sync() }
  }

  func registered(token: Data) {
    pushToken = token.map { String(format: "%02x", $0) }.joined()
    Task { await sync() }
  }

  func sync() async {
    guard enabled, configured, !syncing else { return }
    syncing = true
    defer { syncing = false }
    do {
      try AgentFocusDevice.reconcile()
      let pairing = try AgentFocusPairingStore.load()
      // Show reconciled local state before the relay's network wait.
      refreshFocusStatus(pairingID: pairing.deviceId)
      defer { refreshFocusStatus(pairingID: pairing.deviceId) }
      let worker = AgentFocusDelivery(phone: try AgentFocusDevice.phone(), pairing: pairing)
      let result = await worker.run(pushToken: pushToken)
      if result == .synced {
        if connectionPending { message = "" }
        connectionPending = false
        pushToken = nil
      } else {
        connectionPending = true
        message =
          String(
            localized: "Waiting to sync with your agent. Emergency Unlock works here.",
            table: "AgentFocus")
      }
    } catch {
      connectionPending = true
      refreshFocusStatus()
      message =
        String(
          localized: "Waiting to sync with your agent. Emergency Unlock works here.",
          table: "AgentFocus")
    }
  }

  private func request<T: Encodable>(relay: URL, path: String, body: T) async throws -> Data {
    try await request(relay: relay, path: path, token: nil, data: JSONEncoder().encode(body))
  }
  private func request(relay: URL, path: String, token: String?, data: Data?) async throws -> Data {
    var request = URLRequest(url: relay.appendingPathComponent(path))
    request.httpMethod = data == nil ? "GET" : "POST"
    request.httpBody = data
    request.timeoutInterval = 10
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
    let (body, response) = try await transport.data(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
    else {
      throw Failure.requestFailed
    }
    return body
  }

}

final class AgentFocusAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate
{
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    application.registerForRemoteNotifications()
    return true
  }
  func application(
    _ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data
  ) {
    Task { @MainActor in AgentFocusRuntime.shared.registered(token: token) }
  }
  func application(
    _ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    Task { @MainActor in
      AgentFocusRuntime.shared.message =
        String(
          localized: "Push registration failed. Open DO Card to receive pending commands.",
          table: "AgentFocus")
    }
  }
  func application(
    _ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) {
    guard userInfo["docardAgent"] as? Bool == true else {
      completionHandler(.noData)
      return
    }
    Task { @MainActor in
      await AgentFocusRuntime.shared.sync()
      completionHandler(.newData)
    }
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    guard response.notification.request.content.userInfo["docardAgent"] as? Bool == true else {
      completionHandler()
      return
    }
    Task { @MainActor in
      await AgentFocusRuntime.shared.sync()
      completionHandler()
    }
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler(
      notification.request.content.userInfo["docardAgent"] as? Bool == true
        ? [.banner, .sound] : [])
  }
}
