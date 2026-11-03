import CryptoKit
import Foundation

struct OnboardingPostHogConfiguration {
  let token: String
  let host: URL
  let environment: String
  var destination: String {
    SHA256.hash(data: Data("\(host.absoluteString)|\(token)|\(environment)".utf8))
      .map { String(format: "%02x", $0) }.joined()
  }

  init?(token: String, host: String, environment: String) {
    guard token.hasPrefix("phc_"), token.count > 8, !token.contains("$("),
      let url = URL(string: host), url.scheme == "https", url.host != nil,
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      url.path.isEmpty || url.path == "/", ["development", "production"].contains(environment)
    else { return nil }
    self.token = token
    self.host = url
    self.environment = environment
  }
}

@MainActor
final class OnboardingPostHogUploader {
  typealias Send = (URLRequest) async throws -> (Data, HTTPURLResponse)
  enum UploadError: Error { case rejected, invalidResponse }
  private let journal: OnboardingJournal
  private let configuration: OnboardingPostHogConfiguration
  private let send: Send
  private var inFlight = false

  init(
    journal: OnboardingJournal, configuration: OnboardingPostHogConfiguration,
    send: @escaping Send = OnboardingBatchTransport.send
  ) {
    self.journal = journal
    self.configuration = configuration
    self.send = send
  }

  static func timestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
  }

  static func body(for event: OnboardingJournal.Event, state: OnboardingJournal.State) -> [String:
    Any]
  {
    var properties: [String: Any] = [
      "event_id": event.id.uuidString, "install_id": state.installID,
      "environment": state.environment, "is_synthetic": state.isSynthetic,
      "questionnaire_version": 1, "response_revision": event.revision,
      "onboarding_attempt_id": state.attemptID.uuidString, "app_version": event.appVersion,
      "$process_person_profile": false, "$geoip_disable": true, "$ip": "0.0.0.0",
    ]
    if let step = event.questionID {
      properties["step_id"] = step
      if ["purposes", "habits", "daily_phone_time"].contains(step) {
        properties["question_id"] = step
      }
    }
    if let answers = event.answers {
      properties["purposes"] = answers.purposes.sorted()
      properties["scrolling_habits"] = answers.habits.sorted()
      if let phoneTime = answers.dailyPhoneTime { properties["daily_phone_time"] = phoneTime }
      if !answers.purposeOtherText.isEmpty {
        properties["purpose_other_text"] = answers.purposeOtherText
      }
      if !answers.habitOtherText.isEmpty { properties["habit_other_text"] = answers.habitOtherText }
    }
    return [
      "event": event.name, "distinct_id": state.installID, "uuid": event.id.uuidString,
      "timestamp": timestamp(event.occurredAt), "properties": properties,
    ]
  }

  @discardableResult
  func upload(disclosureShown: Bool, now: Date = Date()) async throws -> Int {
    guard disclosureShown, !inFlight, configuration.environment == journal.environment else {
      return 0
    }
    inFlight = true
    defer { inFlight = false }
    let batch = try journal.pending(destination: configuration.destination, now: now)
    guard !batch.isEmpty else { return 0 }
    let state = try journal.read()
    var request = URLRequest(url: configuration.host.appendingPathComponent("batch/"))
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(
      withJSONObject: [
        "api_key": configuration.token, "historical_migration": false,
        "batch": batch.map { Self.body(for: $0, state: state) },
      ], options: [.sortedKeys])
    var retryAfter: TimeInterval?
    do {
      try Task.checkCancellation()
      let (data, response) = try await send(request)
      retryAfter = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
      guard (200...299).contains(response.statusCode) else { throw UploadError.rejected }
      struct NumericReceipt: Decodable { let status: Int }
      struct TextReceipt: Decodable { let status: String }
      guard
        (try? JSONDecoder().decode(NumericReceipt.self, from: data).status) == 1
          || (try? JSONDecoder().decode(TextReceipt.self, from: data).status) == "Ok"
      else {
        throw UploadError.invalidResponse
      }
      try journal.accepted(Set(batch.map(\.id)), destination: configuration.destination)
      return batch.count
    } catch {
      if !(error is CancellationError) && !Task.isCancelled {
        try journal.failed(destination: configuration.destination, at: now, retryAfter: retryAfter)
      }
      throw error
    }
  }
}

// Separate adapter while retention's private, uncommitted transport is owned by the other worktree.
// Both use the same documented batch/configuration contract; no second SDK or identity is created.
final class OnboardingBatchTransport: NSObject, URLSessionTaskDelegate {
  private static let delegate = OnboardingBatchTransport()
  private static let session: URLSession = {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.httpCookieStorage = nil
    configuration.urlCache = nil
    configuration.timeoutIntervalForRequest = 15
    configuration.timeoutIntervalForResource = 20
    return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
  }()
  static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw OnboardingPostHogUploader.UploadError.invalidResponse
    }
    return (data, http)
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
