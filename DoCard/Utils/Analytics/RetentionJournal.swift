import Darwin
import Foundation

/// A schema-independent App Group journal. All readers and writers use the same file lock.
final class RetentionJournal {
  enum JournalError: Error { case unavailable, notActivated, invalidRecord, conflictingStart }

  struct Cohort: Codable, Equatable {
    let sessionID: String
    let startedAt: Date
    let timeZoneID: String
  }

  struct Session: Codable, Equatable {
    let id: String
    let startedAt: Date
    let trigger: String
    var endedAt: Date?
    var breakStartedAt: Date?
    var breakEndedAt: Date?
    var endReason: String?
    var revision: Int = 0
    var isExcluded: Bool = false
  }

  struct Contribution: Codable, Equatable {
    let sessionID: String
    let localDate: String
    let dayOffset: Int
    let periodIndex: Int
    let lockedSeconds: TimeInterval
    let revision: Int
  }

  struct State: Codable {
    let version: Int
    let installID: String
    let activatedAt: Date
    let classification: String
    var cohort: Cohort?
    var sessions: [String: Session] = [:]
    var contributions: [String: Contribution] = [:]
  }

  private let directory: URL
  init(directory: URL) { self.directory = directory }

  func activate(installID: String, at date: Date, classification: String) throws {
    guard !installID.isEmpty, date.timeIntervalSince1970.isFinite,
      ["new_install", "existing_install", "unknown"].contains(classification)
    else { throw JournalError.invalidRecord }
    try locked {
      let url = directory.appendingPathComponent("state.json")
      if FileManager.default.fileExists(atPath: url.path) {
        _ = try load()  // Never reset a damaged journal or silently create a new denominator.
        return
      }
      try save(
        State(version: 1, installID: installID, activatedAt: date, classification: classification))
    }
  }

  func read() throws -> State { try locked { try load() } }

  func recordStart(sessionID: String, at date: Date, timeZoneID: String, trigger: String) throws {
    _ = try RetentionTimeCalculator.Cohort(startedAt: date, timeZoneID: timeZoneID)
    guard !sessionID.isEmpty else { throw JournalError.invalidRecord }
    try locked {
      var state = try load()
      guard date >= state.activatedAt else { return }
      let session = Session(id: sessionID, startedAt: date, trigger: trigger)
      if let existing = state.sessions[sessionID] {
        guard existing.startedAt == date && existing.trigger == trigger else {
          throw JournalError.conflictingStart
        }
        return
      }
      state.sessions[sessionID] = session
      if state.cohort == nil {
        state.cohort = Cohort(sessionID: sessionID, startedAt: date, timeZoneID: timeZoneID)
      }
      try save(state)
    }
  }

  func recordCompletion(
    _ facts: RetentionTimeCalculator.Session, endReason: String?, asOf: Date
  ) throws {
    try locked {
      var state = try load()
      guard var session = state.sessions[facts.id], let cohort = state.cohort else { return }
      guard !session.isExcluded else { return }
      guard session.startedAt == facts.startTime else { throw JournalError.conflictingStart }
      if session.endReason == "emergency_unlock" && endReason != "emergency_unlock" { return }
      let facts = RetentionTimeCalculator.Session(
        id: facts.id, startTime: facts.startTime,
        endTime: facts.endTime, breakStartTime: facts.breakStartTime ?? session.breakStartedAt,
        breakEndTime: facts.breakEndTime ?? session.breakEndedAt)
      let anchor = try RetentionTimeCalculator.Cohort(
        startedAt: cohort.startedAt, timeZoneID: cohort.timeZoneID)
      let calculated = try RetentionTimeCalculator.contributions(
        for: facts, cohort: anchor, asOf: asOf)
      guard let end = facts.endTime, end <= asOf else { return }
      if session.endedAt == end && session.breakStartedAt == facts.breakStartTime
        && session.breakEndedAt == facts.breakEndTime && session.endReason == endReason
      {
        return
      }
      session.endedAt = end
      session.breakStartedAt = facts.breakStartTime
      session.breakEndedAt = facts.breakEndTime
      session.endReason = endReason
      session.revision += 1
      state.sessions[facts.id] = session
      storeContributions(calculated, session: session, state: &state)
      try save(state)
    }
  }

  func recordBreak(sessionID: String, start: Date?, end: Date?, asOf: Date) throws {
    try locked {
      var state = try load()
      guard var session = state.sessions[sessionID], !session.isExcluded, let cohort = state.cohort
      else { return }
      let facts = RetentionTimeCalculator.Session(
        id: sessionID, startTime: session.startedAt,
        endTime: session.endedAt, breakStartTime: start, breakEndTime: end)
      let anchor = try RetentionTimeCalculator.Cohort(
        startedAt: cohort.startedAt, timeZoneID: cohort.timeZoneID)
      let rows = try RetentionTimeCalculator.contributions(for: facts, cohort: anchor, asOf: asOf)
      guard session.breakStartedAt != start || session.breakEndedAt != end else { return }
      session.breakStartedAt = start
      session.breakEndedAt = end
      if let endedAt = session.endedAt, endedAt <= asOf {
        session.revision += 1
        storeContributions(rows, session: session, state: &state)
      }
      state.sessions[sessionID] = session
      try save(state)
    }
  }

  private func storeContributions(
    _ calculated: [RetentionTimeCalculator.Contribution],
    session: Session, state: inout State
  ) {
    // Keep zero-valued revisions so later delivery can retract previously uploaded days.
    for (key, old) in state.contributions where old.sessionID == session.id {
      state.contributions[key] = Contribution(
        sessionID: old.sessionID, localDate: old.localDate,
        dayOffset: old.dayOffset, periodIndex: old.periodIndex, lockedSeconds: 0,
        revision: session.revision)
    }
    for row in calculated {
      state.contributions[row.key] = Contribution(
        sessionID: row.sessionID, localDate: row.localDate,
        dayOffset: row.dayOffset, periodIndex: row.periodIndex, lockedSeconds: row.lockedSeconds,
        revision: session.revision)
    }
  }

  func excludeSession(id: String) throws {
    try locked {
      var state = try load()
      guard var session = state.sessions[id], !session.isExcluded, session.endedAt == nil else {
        return
      }
      session.isExcluded = true
      session.revision += 1
      state.sessions[id] = session
      for (key, old) in state.contributions where old.sessionID == id {
        state.contributions[key] = Contribution(
          sessionID: old.sessionID, localDate: old.localDate,
          dayOffset: old.dayOffset, periodIndex: old.periodIndex, lockedSeconds: 0,
          revision: session.revision)
      }
      try save(state)
    }
  }

  struct DeliveryState: Codable {
    var acceptedRevisions: [String: Int] = [:]
    var failedAttempts: Int = 0
    var nextAttemptAt: Date?
  }

  func deliveryState(destination: String) throws -> DeliveryState {
    try locked { try loadDelivery(destination: destination) }
  }

  func acceptUpload(destination: String, revisions: [String: Int]) throws {
    try locked {
      var state = try loadDelivery(destination: destination)
      for (key, revision) in revisions {
        state.acceptedRevisions[key] = max(state.acceptedRevisions[key] ?? 0, revision)
      }
      state.failedAttempts = 0
      state.nextAttemptAt = nil
      try saveDelivery(state, destination: destination)
    }
  }

  func failUpload(destination: String, now: Date, retryAfter: TimeInterval? = nil) throws {
    try locked {
      var state = try loadDelivery(destination: destination)
      state.failedAttempts = min(state.failedAttempts, 10) + 1
      let delay = min(3600, 30 * pow(2, Double(state.failedAttempts - 1)))
      state.nextAttemptAt = now.addingTimeInterval(max(delay, min(86400, max(0, retryAfter ?? 0))))
      try saveDelivery(state, destination: destination)
    }
  }

  private func deliveryURL(_ destination: String) throws -> URL {
    guard destination.count == 64, destination.allSatisfy({ $0.isHexDigit }) else {
      throw JournalError.invalidRecord
    }
    return directory.appendingPathComponent("delivery-\(destination).json")
  }

  private func loadDelivery(destination: String) throws -> DeliveryState {
    let url = try deliveryURL(destination)
    guard FileManager.default.fileExists(atPath: url.path) else { return DeliveryState() }
    return try JSONDecoder().decode(DeliveryState.self, from: Data(contentsOf: url))
  }

  private func saveDelivery(_ state: DeliveryState, destination: String) throws {
    try write(JSONEncoder().encode(state), to: deliveryURL(destination))
  }

  private func load() throws -> State {
    let url = directory.appendingPathComponent("state.json")
    guard FileManager.default.fileExists(atPath: url.path) else { throw JournalError.notActivated }
    let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
    guard state.version == 1 else { throw JournalError.invalidRecord }
    return state
  }

  private func save(_ state: State) throws {
    try write(JSONEncoder().encode(state), to: directory.appendingPathComponent("state.json"))
  }

  private func write(_ data: Data, to url: URL) throws {
    var options: Data.WritingOptions = .atomic
    #if os(iOS)
      options.insert(.completeFileProtectionUntilFirstUserAuthentication)
    #endif
    try data.write(to: url, options: options)
  }

  private func locked<T>(_ action: () throws -> T) throws -> T {
    #if os(iOS)
      let attributes: [FileAttributeKey: Any] = [
        .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
      ]
    #else
      let attributes: [FileAttributeKey: Any] = [:]
    #endif
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: attributes)
    let descriptor = open(
      directory.appendingPathComponent("journal.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else { throw JournalError.unavailable }
    defer { close(descriptor) }
    guard flock(descriptor, LOCK_EX) == 0 else { throw JournalError.unavailable }
    defer { flock(descriptor, LOCK_UN) }
    return try action()
  }
}
