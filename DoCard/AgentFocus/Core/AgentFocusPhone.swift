import Darwin
import Foundation

struct AgentEmergencyCancellation: Codable {
  let pairingID: String?
  let approvalID: String?
  let nextModeID: String
  let revision: Int
  let sequence: Int
  let at: Double
}

/// Independent system storage (shared Keychain on iOS), not the session record filesystem.
struct AgentEmergencyStorage {
  let read: () throws -> AgentEmergencyCancellation?
  let write: (AgentEmergencyCancellation) throws -> Void
}

/// The persisted phone interface. Every operation, including platform effects, shares one OS lock.
final class AgentFocusPhone<Selection: Codable>: @unchecked Sendable {
  struct Status {
    let policy: AgentFocusPolicy
    let session: AgentFocusSession?
    let requiresRenewalApproval: Bool
  }
  private struct CompletedCommand: Codable {
    let receipt: FocusReceipt
    let sequence: Int
    let retainUntil: Double
  }
  private struct Record: Codable {
    var pairingID: String?
    var approvalID: String?
    var cancellationRevision = 0
    var policy: AgentFocusPolicy?
    var selection: Selection?
    var state = AgentFocusState()
    var receipts: [FocusReceipt] = []
    var pendingCommand: FocusCommand?
    var completedCommands: [CompletedCommand]?
  }
  enum Failure: Error { case unavailable, pairingMismatch, activeSession }
  private let emergency: AgentEmergencyStorage
  private let directory: URL
  private let now: () -> Double
  private let apply: (AgentFocusSession, Selection) throws -> Void
  private let release: () -> Void
  private let lockTimeout: TimeInterval?

  init(
    directory: URL, emergency: AgentEmergencyStorage, now: @escaping () -> Double,
    apply: @escaping (AgentFocusSession, Selection) throws -> Void,
    release: @escaping () -> Void, lockTimeout: TimeInterval? = nil
  ) {
    self.directory = directory
    self.emergency = emergency
    self.now = now
    self.apply = apply
    self.release = release
    self.lockTimeout = lockTimeout
  }

  func approve(policy: AgentFocusPolicy, selection: Selection, pairingID: String) throws {
    try locked {
      var record = try load()
      guard record.state.session == nil, record.pendingCommand == nil else {
        throw Failure.activeSession
      }
      let revision = max(record.cancellationRevision, (try emergency.read())?.revision ?? 0) + 1
      if record.pairingID != pairingID {
        record = Record()
      }
      record.pairingID = pairingID
      record.approvalID = UUID().uuidString
      record.cancellationRevision = revision
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
      if let result = record.completedCommands?.first(where: {
        $0.receipt.id == command.id && $0.sequence == command.sequence
      }) {
        return result.receipt
      }
      if let receipt = record.state.lastReceipt, receipt.id == command.id,
        command.sequence == record.state.lastSequence
      {
        return receipt
      }
      var validationState = record.state
      // The persisted phone uses mode generation as a causal boundary, independent of relay clocks.
      validationState.lastEmergencyAt = nil
      let controller = AgentFocusController(policy: policy, state: validationState)
      let receipt = controller.receive(command, now: now())
      record.state = controller.state
      if receipt.status != "applied" {
        remember(receipt, command: command, record: &record)
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
    remember(receipt, command: command, record: &record)
    record.state.lastReceipt = receipt
    record.pendingCommand = nil
    if !record.receipts.contains(where: { $0.id == receipt.id }) { record.receipts.append(receipt) }
    try save(record)
    return receipt
  }

  private func remember(_ receipt: FocusReceipt, command: FocusCommand, record: inout Record) {
    // Retain results past the command TTL and a notification-extension execution window.
    // Overlapping processes may hold an old queue even after its outbox is acknowledged.
    var completed = (record.completedCommands ?? []).filter { $0.retainUntil > now() }
    if !completed.contains(where: { $0.receipt.id == receipt.id }) {
      completed.append(
        CompletedCommand(
          receipt: receipt, sequence: command.sequence,
          retainUntil: command.expiresAt.isFinite ? command.expiresAt + 60000 : now() + 60000))
    }
    record.completedCommands = completed
  }

  func emergencyUnlock() throws {
    var enteredLock = false
    do {
      try locked {
        enteredLock = true
        // Even a corrupt record must not prevent the physical release.
        defer { release() }
        let previous = (try? load()) ?? (try? loadRaw())
        let cancellation = AgentEmergencyCancellation(
          pairingID: previous?.pairingID, approvalID: previous?.approvalID,
          nextModeID: UUID().uuidString, revision: (previous?.cancellationRevision ?? 0) + 1,
          sequence: previous?.state.lastSequence ?? Int.max, at: now())
        // Try the independent ledger first. A failed primary write cannot resurrect this owner.
        let ledger = Result { try emergency.write(cancellation) }
        guard var record = previous else {
          try ledger.get()
          throw Failure.unavailable
        }
        record.state.session = nil
        record.state.lastReceipt = nil
        record.state.lastEmergencyAt = cancellation.at
        record.cancellationRevision = cancellation.revision
        record.policy = record.policy.map { mode($0, id: cancellation.nextModeID) }
        record.pendingCommand = nil
        // If the ledger is unavailable, this primary cancellation still provides durability.
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
        guard record.policy != nil else {
          release()
          return
        }
        if !authorized {
          let cancellation = AgentEmergencyCancellation(
            pairingID: record.pairingID,
            approvalID: record.approvalID, nextModeID: UUID().uuidString,
            revision: record.cancellationRevision + 1, sequence: record.state.lastSequence,
            at: now())
          _ = Result { try emergency.write(cancellation) }
          record.cancellationRevision = cancellation.revision
          record.policy = record.policy.map { mode($0, id: cancellation.nextModeID) }
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

  private func mode(_ policy: AgentFocusPolicy, id: String) -> AgentFocusPolicy {
    AgentFocusPolicy(
      modeID: id, maximumMinutes: policy.maximumMinutes,
      startMinute: policy.startMinute, endMinute: policy.endMinute, timeZone: policy.timeZone)
  }

  private func locked<T>(_ operation: () throws -> T) throws -> T {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fd = open(
      directory.appendingPathComponent("agent-focus.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR
    )
    guard fd >= 0 else { throw Failure.unavailable }
    defer { close(fd) }
    if let lockTimeout {
      let deadline = ContinuousClock.now.advanced(by: .seconds(lockTimeout))
      while flock(fd, LOCK_EX | LOCK_NB) != 0 {
        guard errno == EWOULDBLOCK || errno == EAGAIN, ContinuousClock.now < deadline else {
          throw Failure.unavailable
        }
        Thread.sleep(forTimeInterval: 0.01)
      }
    } else {
      guard flock(fd, LOCK_EX) == 0 else { throw Failure.unavailable }
    }
    defer { flock(fd, LOCK_UN) }
    return try operation()
  }
  private func load() throws -> Record {
    var record = try loadRaw()
    if let cancellation = try emergency.read(),
      cancellation.pairingID == nil || cancellation.pairingID == record.pairingID,
      cancellation.approvalID == nil || cancellation.approvalID == record.approvalID,
      cancellation.revision > record.cancellationRevision
    {
      record.cancellationRevision = cancellation.revision
      record.policy = record.policy.map { mode($0, id: cancellation.nextModeID) }
      record.state.lastEmergencyAt = max(record.state.lastEmergencyAt ?? 0, cancellation.at)
      if record.state.lastSequence <= cancellation.sequence {
        record.state.session = nil
        record.state.lastReceipt = nil
        record.pendingCommand = nil
      }
    }
    return record
  }
  private func loadRaw() throws -> Record {
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
