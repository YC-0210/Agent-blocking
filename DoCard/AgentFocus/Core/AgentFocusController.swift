import Foundation

struct AgentFocusPolicy: Codable, Equatable, Sendable {
  let modeID: String
  let maximumMinutes: Int
  let startMinute: Int
  let endMinute: Int
  let timeZone: String
}

struct FocusCommand: Codable, Equatable, Sendable {
  enum Action: String, Codable, Sendable { case start, stop }
  let id: String
  let sequence: Int
  let action: Action
  let modeID: String
  let durationMinutes: Int?
  let sessionID: String
  let issuedAt: Double
  let expiresAt: Double
  var renewalConfirmed: Bool? = nil
}

struct AgentFocusSession: Codable, Equatable, Sendable {
  let id: String
  let endAt: Double
}

struct AgentFocusState: Codable, Equatable, Sendable {
  var session: AgentFocusSession?
  var lastSequence = 0
  var requiresRenewalApproval = false
  var lastReceipt: FocusReceipt?
  var lastEmergencyAt: Double?
}

struct FocusReceipt: Codable, Equatable, Sendable {
  let id: String
  let status: String
  let reason: String?
}

final class AgentFocusController {
  let policy: AgentFocusPolicy
  private(set) var state = AgentFocusState()

  private let start: (AgentFocusSession) throws -> Void
  private let stop: () throws -> Void

  init(
    policy: AgentFocusPolicy, state: AgentFocusState = .init(),
    start: @escaping (AgentFocusSession) throws -> Void = { _ in },
    stop: @escaping () throws -> Void = {}
  ) {
    self.policy = policy
    self.state = state
    self.start = start
    self.stop = stop
  }

  func emergencyUnlock(now: Double = 0) throws {
    state.lastEmergencyAt = now
    try stop()
    state.session = nil
    state.lastReceipt = nil
  }

  func restore(now: Double) throws {
    try reconcile(now: now)
    guard let session = state.session else { return }
    do { try start(session) } catch {
      try stop()
      state.session = nil
      state.lastReceipt = nil
      state.requiresRenewalApproval = true
    }
  }

  func reconcile(now: Double) throws {
    if let session = state.session, now >= session.endAt {
      try stop()
      state.session = nil
      state.requiresRenewalApproval = true
    }
  }

  func receive(_ command: FocusCommand, now: Double) -> FocusReceipt {
    if let receipt = state.lastReceipt, receipt.id == command.id,
      command.sequence == state.lastSequence
    {
      return receipt
    }
    let receipt = execute(command, now: now)
    if command.sequence == state.lastSequence { state.lastReceipt = receipt }
    return receipt
  }

  private func execute(_ command: FocusCommand, now: Double) -> FocusReceipt {
    do { try reconcile(now: now) } catch {
      return FocusReceipt(id: command.id, status: "rejected", reason: "execution_failed")
    }
    guard command.sequence > state.lastSequence else {
      return FocusReceipt(id: command.id, status: "rejected", reason: "stale_command")
    }
    state.lastSequence = command.sequence
    guard command.issuedAt.isFinite, command.expiresAt.isFinite, now.isFinite,
      command.issuedAt <= now, command.expiresAt > now,
      command.expiresAt > command.issuedAt, command.expiresAt - command.issuedAt <= 120000
    else {
      return FocusReceipt(id: command.id, status: "rejected", reason: "expired_or_future_command")
    }
    if command.action == .start, let cutoff = state.lastEmergencyAt, command.issuedAt <= cutoff {
      return FocusReceipt(id: command.id, status: "rejected", reason: "issued_before_emergency")
    }
    guard command.modeID == policy.modeID else {
      return FocusReceipt(id: command.id, status: "rejected", reason: "mode_not_approved")
    }
    if command.action == .stop {
      guard state.session?.id == command.sessionID else {
        return FocusReceipt(id: command.id, status: "rejected", reason: "session_mismatch")
      }
      do { try stop() } catch {
        return FocusReceipt(id: command.id, status: "rejected", reason: "execution_failed")
      }
      state.session = nil
      return FocusReceipt(id: command.id, status: "applied", reason: nil)
    }
    if state.requiresRenewalApproval && command.renewalConfirmed != true {
      return FocusReceipt(id: command.id, status: "rejected", reason: "renewal_approval_required")
    }
    if state.session != nil {
      return FocusReceipt(id: command.id, status: "rejected", reason: "session_already_active")
    }
    if command.action == .start {
      guard let minutes = command.durationMinutes, minutes >= 15 else {
        return FocusReceipt(id: command.id, status: "rejected", reason: "invalid_duration")
      }
    }
    if command.action == .start, let minutes = command.durationMinutes,
      minutes > policy.maximumMinutes
    {
      return FocusReceipt(id: command.id, status: "rejected", reason: "duration_exceeds_approval")
    }
    var calendar = Calendar(identifier: .gregorian)
    guard let zone = TimeZone(identifier: policy.timeZone),
      (15...1440).contains(policy.maximumMinutes),
      policy.startMinute >= 0, policy.endMinute <= 1440,
      policy.startMinute < policy.endMinute
    else { return FocusReceipt(id: command.id, status: "rejected", reason: "invalid_policy") }
    calendar.timeZone = zone
    let date = Date(timeIntervalSince1970: now / 1000)
    let dayStart = calendar.startOfDay(for: date)
    let windowStart = calendar.date(byAdding: .minute, value: policy.startMinute, to: dayStart)!
    let windowEnd = calendar.date(byAdding: .minute, value: policy.endMinute, to: dayStart)!
    let endAt = command.issuedAt + Double(command.durationMinutes ?? 0) * 60000
    guard date >= windowStart, endAt <= windowEnd.timeIntervalSince1970 * 1000 else {
      return FocusReceipt(id: command.id, status: "rejected", reason: "outside_approved_hours")
    }
    let session = AgentFocusSession(id: command.sessionID, endAt: endAt)
    do { try start(session) } catch {
      return FocusReceipt(id: command.id, status: "rejected", reason: "execution_failed")
    }
    state.requiresRenewalApproval = false
    state.session = session
    return FocusReceipt(id: command.id, status: "applied", reason: nil)
  }
}
