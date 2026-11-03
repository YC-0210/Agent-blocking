import Foundation

struct OnboardingAnswers: Codable, Equatable {
  var purposes: Set<String> = []
  var habits: Set<String> = []
  var purposeOtherText = ""
  var habitOtherText = ""
  var dailyPhoneTime: String?

  static let purposeIDs: Set<String> = [
    "study", "major_exam", "work_tasks", "bedtime_rest", "family_friends", "personal_projects",
    "other",
  ]
  static let habitIDs: Set<String> = [
    "automatic_checking", "boredom", "task_avoidance", "emotional_relief", "notification_cue",
    "lost_time_awareness", "other",
  ]
  static let phoneTimeIDs: Set<String> = ["under_1h", "2_3h", "4_5h", "6_7h", "8h_plus"]

  func isValid(for question: String) -> Bool {
    func valid(_ selected: Set<String>, allowed: Set<String>, other: String) -> Bool {
      !selected.isEmpty && selected.isSubset(of: allowed)
        && (!selected.contains("other")
          || !other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    switch question {
    case "purposes": return valid(purposes, allowed: Self.purposeIDs, other: purposeOtherText)
    case "habits": return valid(habits, allowed: Self.habitIDs, other: habitOtherText)
    case "daily_phone_time": return dailyPhoneTime.map(Self.phoneTimeIDs.contains) ?? false
    default: return false
    }
  }

  func response(for question: String) -> Self {
    let source = submitted
    var result = Self()
    switch question {
    case "purposes":
      result.purposes = source.purposes
      result.purposeOtherText = source.purposeOtherText
    case "habits":
      result.habits = source.habits
      result.habitOtherText = source.habitOtherText
    case "daily_phone_time": result.dailyPhoneTime = source.dailyPhoneTime
    default: break
    }
    return result
  }

  var isComplete: Bool { ["purposes", "habits", "daily_phone_time"].allSatisfy(isValid) }

  // Unselected custom drafts stay on the device; only confirmed selected text is sent.
  var submitted: Self {
    var result = self
    result.purposeOtherText =
      purposes.contains("other")
      ? purposeOtherText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    result.habitOtherText =
      habits.contains("other")
      ? habitOtherText.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    return result
  }
}

/// Main-app-only journal. Calls are serialized by OnboardingTracking on the main actor.
/// Answers and the outbox share one atomic write, so a crash cannot save only half a submission.
final class OnboardingJournal {
  struct Event: Codable, Equatable {
    let id: UUID
    let name: String
    let occurredAt: Date
    let revision: Int
    let questionID: String?
    let answers: OnboardingAnswers?
    let appVersion: String
  }
  struct Delivery: Codable {
    var accepted: Set<UUID> = []
    var failures = 0
    var nextAttemptAt: Date?
  }
  struct State: Codable {
    var version = 1
    let installID: String
    let environment: String
    let isSynthetic: Bool
    let attemptID: UUID
    var draft = OnboardingAnswers()
    var events: [Event] = []
    var deliveries: [String: Delivery] = [:]
  }
  enum JournalError: Error { case identityMismatch, invalidAnswers, invalidState }
  private let url: URL
  let installID: String
  let environment: String
  let isSynthetic: Bool

  init(directory: URL, installID: String, environment: String, isSynthetic: Bool = false) {
    self.url = directory.appendingPathComponent("onboarding.json")
    self.installID = installID
    self.environment = environment
    self.isSynthetic = isSynthetic
  }

  func read() throws -> State {
    guard FileManager.default.fileExists(atPath: url.path) else {
      return State(
        installID: installID, environment: environment, isSynthetic: isSynthetic, attemptID: UUID())
    }
    let state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url))
    guard state.version == 1 else { throw JournalError.invalidState }
    guard state.installID == installID, state.environment == environment,
      state.isSynthetic == isSynthetic
    else { throw JournalError.identityMismatch }
    return state
  }

  private func save(_ state: State) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try JSONEncoder().encode(state).write(to: url, options: .atomic)
    var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
    #if os(iOS)
      attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
    #endif
    try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
  }

  @discardableResult
  func begin(at date: Date, appVersion: String) throws -> OnboardingAnswers {
    var state = try read()
    if state.events.isEmpty {
      append("onboarding_started", to: &state, at: date, appVersion: appVersion)
      try save(state)
    }
    return state.draft
  }

  func saveDraft(_ answers: OnboardingAnswers) throws {
    var state = try read()
    guard state.draft != answers else { return }
    state.draft = answers
    try save(state)
  }

  func confirm(_ question: String, answers: OnboardingAnswers, at date: Date, appVersion: String)
    throws
  {
    guard answers.isValid(for: question) else { throw JournalError.invalidAnswers }
    var state = try read()
    guard !state.events.isEmpty else { throw JournalError.invalidState }
    state.draft = answers
    let confirmed = answers.submitted
    // A repeated tap or revisiting an unchanged question is not a new confirmation.
    if state.events.last(where: { $0.questionID == question })?.answers
      != confirmed.response(for: question)
    {
      append(
        "onboarding_step_completed", to: &state, at: date, appVersion: appVersion,
        question: question, answers: confirmed.response(for: question))
    }
    if question == "daily_phone_time", confirmed.isComplete,
      state.events.last(where: { $0.name == "onboarding_answers_submitted" })?.answers != confirmed
    {
      append(
        "onboarding_answers_submitted", to: &state, at: date, appVersion: appVersion,
        answers: confirmed)
    }
    try save(state)
  }

  func completeStep(_ step: String, at date: Date, appVersion: String) throws {
    guard
      [
        "welcome", "intro_feeling", "intro_context", "card_introduction", "permissions",
        "app_selection", "card_pairing", "gallery", "offer",
      ].contains(step)
    else {
      throw JournalError.invalidAnswers
    }
    var state = try read()
    guard !state.events.isEmpty else { throw JournalError.invalidState }
    guard !state.events.contains(where: { $0.questionID == step }) else { return }
    append(
      "onboarding_step_completed", to: &state, at: date, appVersion: appVersion, question: step)
    try save(state)
  }

  func complete(at date: Date, appVersion: String) throws {
    var state = try read()
    guard state.draft.isComplete else { throw JournalError.invalidAnswers }
    if !state.events.contains(where: { $0.name == "onboarding_completed" }) {
      append(
        "onboarding_completed", to: &state, at: date, appVersion: appVersion,
        answers: state.draft.submitted)
      try save(state)
    }
  }

  private func append(
    _ name: String, to state: inout State, at date: Date, appVersion: String,
    question: String? = nil, answers: OnboardingAnswers? = nil
  ) {
    state.events.append(
      Event(
        id: UUID(), name: name, occurredAt: date,
        revision: state.events.count + 1, questionID: question,
        answers: answers, appVersion: appVersion))
  }

  func pending(destination: String, now: Date) throws -> [Event] {
    let state = try read()
    let delivery = state.deliveries[destination] ?? Delivery()
    guard delivery.nextAttemptAt.map({ $0 <= now }) ?? true else { return [] }
    return Array(state.events.filter { !delivery.accepted.contains($0.id) }.prefix(50))
  }

  func accepted(_ ids: Set<UUID>, destination: String) throws {
    var state = try read()
    var delivery = state.deliveries[destination] ?? Delivery()
    delivery.accepted.formUnion(ids)
    delivery.failures = 0
    delivery.nextAttemptAt = nil
    state.deliveries[destination] = delivery
    try save(state)
  }

  func failed(destination: String, at now: Date, retryAfter: TimeInterval? = nil) throws {
    var state = try read()
    var delivery = state.deliveries[destination] ?? Delivery()
    delivery.failures = min(delivery.failures + 1, 12)
    let delay = min(3600, 30 * pow(2, Double(delivery.failures - 1)))
    let requested = retryAfter.flatMap { $0.isFinite ? min(86400, max(0, $0)) : nil } ?? 0
    delivery.nextAttemptAt = now.addingTimeInterval(max(delay, requested))
    state.deliveries[destination] = delivery
    try save(state)
  }
}
