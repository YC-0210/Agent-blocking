import Darwin
import Foundation

/// The persisted phone interface. Every operation, including platform effects, shares one OS lock.
final class AgentFocusPhone<Selection: Codable>: @unchecked Sendable {
  struct Status {
    let policy: AgentFocusPolicy
    let session: AgentFocusSession?
    let requiresRenewalApproval: Bool
  }
  private struct Record: Codable {
    var pairingID: String?
    var policy: AgentFocusPolicy?
    var selection: Selection?
    var state = AgentFocusState()
    var receipts: [FocusReceipt] = []
    var pendingCommand: FocusCommand?
  }
  enum Failure: Error { case unavailable, pairingMismatch, activeSession }
  private let directory: URL
  private let now: () -> Double
  private let apply: (AgentFocusSession, Selection) throws -> Void
  private let release: () -> Void

  init(
    directory: URL, now: @escaping () -> Double,
    apply: @escaping (AgentFocusSession, Selection) throws -> Void,
    release: @escaping () -> Void
  ) {
    self.directory = directory
    self.now = now
    self.apply = apply
    self.release = release
  }

  func approve(policy: AgentFocusPolicy, selection: Selection, pairingID: String) throws {
    try locked {
      var record = try load()
      guard record.state.session == nil, record.pendingCommand == nil else {
        throw Failure.activeSession
      }
      if record.pairingID != pairingID {
        record = Record()
      }
      record.pairingID = pairingID
      record.policy = policy
      record.selection = selection
      record.state.lastReceipt = nil
      try save(record)
    }
  }

  func receive(_ command: FocusCommand, pairingID: String) throws -> FocusReceipt {
    try locked {
      var record = try load()
      guard record.pairingID == pairingID, let policy = record.policy,
        record.selection != nil
      else { throw Failure.pairingMismatch }
      if record.pendingCommand != nil { try finishPending(&record) }
      if let receipt = record.state.lastReceipt, receipt.id == command.id,
        command.sequence == record.state.lastSequence
      {
        return receipt
      }
      let controller = AgentFocusController(policy: policy, state: record.state)
      let receipt = controller.receive(command, now: now())
      record.state = controller.state
      if receipt.status != "applied" {
        if !record.receipts.contains(where: { $0.id == receipt.id }) {
          record.receipts.append(receipt)
        }
        try save(record)
        if record.state.session == nil { release() }
        return receipt
      }
      // Journal recoverable ownership before crossing the platform-effect seam.
      record.pendingCommand = command
      record.state.lastReceipt = FocusReceipt(id: command.id, status: "pending", reason: nil)
      try save(record)
      return try finishPending(&record)
    }
  }

  @discardableResult
  private func finishPending(_ record: inout Record) throws -> FocusReceipt {
    guard let command = record.pendingCommand, let selection = record.selection else {
      throw Failure.unavailable
    }
    var receipt = FocusReceipt(id: command.id, status: "applied", reason: nil)
    if command.action == .start {
      if let session = record.state.session, session.endAt > now() {
        do { try apply(session, selection) } catch {
          release()
          record.state.session = nil
          receipt = FocusReceipt(id: command.id, status: "rejected", reason: "execution_failed")
        }
      } else {
        release()
        record.state.session = nil
        record.state.requiresRenewalApproval = true
        receipt = FocusReceipt(
          id: command.id, status: "rejected", reason: "expired_before_application")
      }
    } else {
      release()
    }
    record.state.lastReceipt = receipt
    record.pendingCommand = nil
    if !record.receipts.contains(where: { $0.id == receipt.id }) { record.receipts.append(receipt) }
    try save(record)
    return receipt
  }

  func emergencyUnlock() throws {
    var enteredLock = false
    do {
      try locked {
        enteredLock = true
        // Even a corrupt record must not prevent the physical release.
        defer { release() }
        var record = try load()
        record.state.session = nil
        record.state.lastReceipt = nil
        record.state.lastEmergencyAt = now()
        record.pendingCommand = nil
        try save(record)
      }
    } catch {
      if !enteredLock { release() }
      throw error
    }
  }

  func pendingReceipts(pairingID: String) throws -> [FocusReceipt] {
    try locked {
      let record = try load()
      guard record.pairingID == pairingID else { throw Failure.pairingMismatch }
      return record.receipts
    }
  }

  func status(pairingID: String? = nil) throws -> Status? {
    try locked {
      let record = try load()
      if let pairingID, record.pairingID != pairingID { throw Failure.pairingMismatch }
      guard let policy = record.policy else { return nil }
      return Status(
        policy: policy, session: record.state.session,
        requiresRenewalApproval: record.state.requiresRenewalApproval)
    }
  }

  func acknowledge(_ id: String, pairingID: String) throws {
    try locked {
      var record = try load()
      guard record.pairingID == pairingID else { throw Failure.pairingMismatch }
      record.receipts.removeAll { $0.id == id }
      try save(record)
    }
  }

  func reconcile(authorized: Bool) throws {
    try locked {
      do {
        var record = try load()
        if !authorized {
          record.pendingCommand = nil
          record.state.session = nil
          record.state.lastReceipt = nil
          record.state.lastEmergencyAt = now()
          try save(record)
          release()
          return
        }
        if record.pendingCommand != nil { try finishPending(&record) }
        guard let policy = record.policy, let selection = record.selection else {
          release()
          return
        }
        let controller = AgentFocusController(
          policy: policy, state: record.state,
          start: { try self.apply($0, selection) }, stop: { self.release() })
        try controller.restore(now: now())
        record.state = controller.state
        try save(record)
        if record.state.session == nil { release() }
      } catch {
        // Corrupt/unavailable state is never a reason to leave orphaned agent shields behind.
        release()
        throw error
      }
    }
  }

  private func locked<T>(_ operation: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fd = open(
      directory.appendingPathComponent("agent-focus.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR
    )
    guard fd >= 0 else { throw Failure.unavailable }
    defer { close(fd) }
    guard flock(fd, LOCK_EX) == 0 else { throw Failure.unavailable }
    defer { flock(fd, LOCK_UN) }
    return try operation()
  }
  private func load() throws -> Record {
    let url = directory.appendingPathComponent("agent-focus-v1.json")
    guard FileManager.default.fileExists(atPath: url.path) else { return Record() }
    return try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
  }
  private func save(_ record: Record) throws {
    let data = try JSONEncoder().encode(record)
    let url = directory.appendingPathComponent("agent-focus-v1.json")
    #if os(iOS)
      try data.write(
        to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    #else
      try data.write(to: url, options: .atomic)
    #endif
  }
}
