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
  private var syncing = false
  private var pushToken: String?
  private let redirectPolicy = AgentFocusRedirectPolicy()
  private lazy var transport = URLSession(
    configuration: .ephemeral, delegate: redirectPolicy, delegateQueue: nil)
  private let credentialAccount = "docard-agent-pairing-v1"

  struct Pairing: Codable {
    let relay: URL
    let deviceId: String
    let deviceToken: String
  }
  private struct Redeemed: Decodable {
    let deviceId: String
    let deviceToken: String
  }
  private struct Commands: Decodable { let commands: [FocusCommand] }
  private struct Code: Encodable { let code: String }
  private struct Push: Encodable { let token: String }
  private struct Snapshot: Encodable {
    let modeID: String
    let sessionID: String?
    let endAt: Double?
    let requiresRenewalApproval: Bool
    let maximumMinutes: Int
    let startMinute: Int
    let endMinute: Int
    let timeZone: String
  }
  enum Failure: Error {
    case invalidRelay, requestFailed, missingPairing
    case keychain(OSStatus)
  }

  init() {
    if let pairing = try? loadPairing() {
      configured = (try? AgentFocusDevice.status(pairingID: pairing.deviceId)) != nil
    }
  }

  func openSetup(_ url: URL) -> Bool {
    guard url.scheme == "docard-agent", url.host == "setup" else { return false }
    guard !StrategyManager.shared.activeSessionStatus.isBlocking,
      !SharedData.profileSnapshots.values.contains(where: {
        $0.schedules.contains(where: { $0.isActive })
      }
      )
    else {
      message = "End existing sessions and disable scheduled modes before agent setup."
      return false
    }
    let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    if configured {
      if (try? AgentFocusDevice.status()?.session) != nil {
        message = "End the current session before changing agent setup."
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
      try savePairing(
        Pairing(relay: url, deviceId: redeemed.deviceId, deviceToken: redeemed.deviceToken))
      configured = true
      message = "Connected. Return to Codex to manage focus."
      _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [
        .alert, .sound,
      ])
      UIApplication.shared.registerForRemoteNotifications()
      await sync()
    } catch {
      message =
        "Setup failed: \(error.localizedDescription). Check access, app selection, relay and pairing code."
    }
  }

  func emergencyUnlock() {
    do {
      try AgentFocusDevice.emergencyUnlock()
      message = "Agent session ended. Your agent remains connected."
    } catch {
      message = "Agent shields cleared. Could not save the session ending; reopen DO Card to retry."
    }
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
      let pairing = try loadPairing()
      if let token = pushToken {
        _ = try await request(pairing, path: "v1/device/push", body: Push(token: token))
        pushToken = nil
      }
      // Retry persisted receipts before fetching more work. A lost acknowledgement cannot restart a session.
      try await uploadReceipts(pairing)
      let data = try await request(pairing, path: "v1/device/commands")
      let commands = try JSONDecoder().decode(Commands.self, from: data).commands
      for command in commands {
        _ = try AgentFocusDevice.receive(command, pairingID: pairing.deviceId)
      }
      try await uploadReceipts(pairing)
      try await publishSnapshot(pairing)
    } catch {
      message =
        "Connection pending. Current focus still ends at its approved time. Emergency Unlock works here."
    }
  }

  private func publishSnapshot(_ pairing: Pairing) async throws {
    let status = try AgentFocusDevice.status(pairingID: pairing.deviceId)
    let snapshot = status.map { status in
      Snapshot(
        modeID: status.policy.modeID, sessionID: status.session?.id,
        endAt: status.session?.endAt, requiresRenewalApproval: status.requiresRenewalApproval,
        maximumMinutes: status.policy.maximumMinutes, startMinute: status.policy.startMinute,
        endMinute: status.policy.endMinute, timeZone: status.policy.timeZone)
    }
    if let snapshot { _ = try await request(pairing, path: "v1/device/snapshot", body: snapshot) }
  }

  private func uploadReceipts(_ pairing: Pairing) async throws {
    let receipts = try AgentFocusDevice.pendingReceipts(pairingID: pairing.deviceId)
    for receipt in receipts {
      _ = try await request(pairing, path: "v1/device/receipts", body: receipt)
      try AgentFocusDevice.acknowledge(receipt.id, pairingID: pairing.deviceId)
    }
  }

  private func request(_ pairing: Pairing, path: String) async throws -> Data {
    try await request(relay: pairing.relay, path: path, token: pairing.deviceToken, data: nil)
  }
  private func request<T: Encodable>(_ pairing: Pairing, path: String, body: T) async throws -> Data
  {
    try await request(
      relay: pairing.relay, path: path, token: pairing.deviceToken, data: JSONEncoder().encode(body)
    )
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

  private func loadPairing() throws -> Pairing {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "online.do.card.agent",
      kSecAttrAccount as String: credentialAccount,
      kSecReturnData as String: true,
    ]
    var result: CFTypeRef?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { throw Failure.missingPairing }
    return try JSONDecoder().decode(Pairing.self, from: data)
  }
  private func savePairing(_ pairing: Pairing) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "online.do.card.agent",
      kSecAttrAccount as String: credentialAccount,
    ]
    let data = try JSONEncoder().encode(pairing)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var item = query
      item[kSecValueData as String] = data
      item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let added = SecItemAdd(item as CFDictionary, nil)
      guard added == errSecSuccess else { throw Failure.keychain(added) }
    } else if status != errSecSuccess {
      throw Failure.keychain(status)
    }
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
        "Push registration failed. Open DO Card to receive pending commands."
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
