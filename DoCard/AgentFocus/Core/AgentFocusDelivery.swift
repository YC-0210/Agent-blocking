import Foundation

struct AgentFocusPairing: Codable, Sendable {
  let relay: URL
  let deviceId: String
  let deviceToken: String
}

enum AgentFocusDeliveryOutcome: Equatable {
  case applied, rejected, pending, synced, expired, expiryChecked
  var notificationBody: String {
    switch self {
    case .expired: "Your expired focus session was released."
    case .expiryChecked: "Focus expiry checked."
    case .applied: "Your focus request was applied."
    case .rejected: "Your phone rejected the focus request. Open DO Card to check your settings."
    case .pending, .synced: "A focus request is waiting. Open DO Card if it does not apply."
    }
  }
}

/// A single bounded sync, usable by the main app or notification extension without UIKit.
final class AgentFocusDelivery<Selection: Codable>: @unchecked Sendable {
  typealias Outcome = AgentFocusDeliveryOutcome
  enum Failure: Error { case invalidRelay, unavailable, budgetExpired }
  private struct Commands: Decodable { let commands: [FocusCommand] }
  private struct Result: Decodable {
    let command: FocusCommand
    let status: String
  }
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
    let appGroups: [AgentAppGroup]
    let activeAppGroupID: String?
  }
  private final class RedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(
      _ session: URLSession, task: URLSessionTask,
      willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
      completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
  }
  private let phone: AgentFocusPhone<Selection>
  private let pairing: AgentFocusPairing
  private let transport: URLSession

  init(
    phone: AgentFocusPhone<Selection>, pairing: AgentFocusPairing,
    configuration: URLSessionConfiguration = .ephemeral
  ) {
    self.phone = phone
    self.pairing = pairing
    configuration.timeoutIntervalForRequest = 5
    configuration.timeoutIntervalForResource = 18
    transport = URLSession(
      configuration: configuration, delegate: RedirectPolicy(), delegateQueue: nil)
  }
  deinit { transport.invalidateAndCancel() }

  func run(commandID: String? = nil, pushToken: String? = nil, expiryCheck: Bool = false) async
    -> Outcome
  {
    let deadline = ContinuousClock.now.advanced(by: .seconds(18))
    // Bound the complete network operation, including a server that keeps sending bytes.
    let timeout = Task { [transport] in
      do {
        try await Task.sleep(for: .seconds(18))
        transport.invalidateAndCancel()
      } catch { /* Normal completion cancels the deadline task. */  }
    }
    defer { timeout.cancel() }
    var localReceipt: FocusReceipt?
    var expiryOutcome: Outcome?
    do {
      try check(deadline)
      try validateRelay()
      if expiryCheck {
        // A push is only a wake-up hint. The phone's own stored deadline decides.
        let outcome: Outcome = try phone.expire(retryFor: 1) ? .expired : .expiryChecked
        expiryOutcome = outcome
        try? await uploadReceipts(deadline: deadline)
        try await publishSnapshot(deadline: deadline)
        return outcome
      }
      if let pushToken {
        _ = try await request(
          "v1/device/push", body: JSONEncoder().encode(Push(token: pushToken)), deadline: deadline)
      }
      localReceipt = try phone.pendingReceipts(pairingID: pairing.deviceId).first {
        $0.id == commandID
      }
      // A failed old receipt upload must not prevent a newly queued unlock.
      try? await uploadReceipts(deadline: deadline)
      let data = try await request("v1/device/commands", deadline: deadline)
      let commands = try JSONDecoder().decode(Commands.self, from: data).commands
      for command in commands.prefix(32) {
        try check(deadline)
        let receipt = try phone.receive(command, pairingID: pairing.deviceId)
        if command.id == commandID { localReceipt = receipt }
      }
      try await uploadReceipts(deadline: deadline)
      try await publishSnapshot(deadline: deadline)
      if let commandID, localReceipt == nil {
        let allowed = CharacterSet(
          charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        guard !commandID.isEmpty, commandID.utf8.count <= 80,
          let id = commandID.addingPercentEncoding(withAllowedCharacters: allowed)
        else { return .pending }
        // The main app or another notification may already have processed this request.
        let result = try JSONDecoder().decode(
          Result.self,
          from: await request("v1/device/commands/" + id, deadline: deadline))
        guard result.command.id == commandID else { return .pending }
        localReceipt = FocusReceipt(id: commandID, status: result.status, reason: nil)
      }
      if commandID == nil { return .synced }
    } catch {
      // A local result stays durable even if its network acknowledgement must be retried.
    }
    if let expiryOutcome { return expiryOutcome }
    switch localReceipt?.status {
    case "applied": return .applied
    case "rejected": return .rejected
    default: return .pending
    }
  }

  private func publishSnapshot(deadline: ContinuousClock.Instant) async throws {
    if let status = try phone.status(pairingID: pairing.deviceId) {
      let snapshot = Snapshot(
        modeID: status.policy.modeID, sessionID: status.session?.id,
        endAt: status.session?.endAt, requiresRenewalApproval: status.requiresRenewalApproval,
        maximumMinutes: status.policy.maximumMinutes, startMinute: status.policy.startMinute,
        endMinute: status.policy.endMinute, timeZone: status.policy.timeZone,
        appGroups: status.appGroups, activeAppGroupID: status.activeAppGroupID)
      _ = try await request(
        "v1/device/snapshot", body: JSONEncoder().encode(snapshot), deadline: deadline)
    }
  }

  private func uploadReceipts(deadline: ContinuousClock.Instant) async throws {
    for receipt in try phone.pendingReceipts(pairingID: pairing.deviceId) {
      _ = try await request(
        "v1/device/receipts", body: JSONEncoder().encode(receipt), deadline: deadline)
      try phone.acknowledge(receipt.id, pairingID: pairing.deviceId)
    }
  }
  private func check(_ deadline: ContinuousClock.Instant) throws {
    try Task.checkCancellation()
    guard ContinuousClock.now < deadline else { throw Failure.budgetExpired }
  }
  private func validateRelay() throws {
    guard let parts = URLComponents(url: pairing.relay, resolvingAgainstBaseURL: false),
      parts.scheme == "https", parts.host != nil, parts.user == nil, parts.password == nil,
      parts.query == nil, parts.fragment == nil, parts.path.isEmpty || parts.path == "/"
    else { throw Failure.invalidRelay }
  }
  private func request(_ path: String, body: Data? = nil, deadline: ContinuousClock.Instant)
    async throws -> Data
  {
    try check(deadline)
    let remaining = ContinuousClock.now.duration(to: deadline).components
    let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
    let url = URL(string: path, relativeTo: pairing.relay.appendingPathComponent("/"))!.absoluteURL
    var request = URLRequest(url: url)
    request.httpMethod = body == nil ? "GET" : "POST"
    request.httpBody = body
    request.timeoutInterval = min(5, seconds)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("Bearer \(pairing.deviceToken)", forHTTPHeaderField: "Authorization")
    let (bytes, response) = try await transport.bytes(for: request)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode)
    else { throw Failure.unavailable }
    var data = Data()
    for try await byte in bytes {
      guard data.count < 65536 else { throw Failure.unavailable }
      data.append(byte)
    }
    try check(deadline)
    return data
  }
}
