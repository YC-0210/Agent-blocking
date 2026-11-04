import Foundation

struct PostHogRetentionConfiguration {
  let token: String
  let host: URL
  let environment: String
  var destination: String {
    RetentionEventBuilder.digest("\(host.absoluteString)|\(token)|\(environment)")
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

actor PostHogRetentionUploader {
  enum UploadError: Error {
    case rejected(Int)
    case invalidResponse
  }
  typealias Send = (URLRequest) async throws -> (Data, HTTPURLResponse)
  private let journal: RetentionJournal
  private let configuration: PostHogRetentionConfiguration
  private let appVersion: String
  private let send: Send
  private var isUploading = false

  init(
    journal: RetentionJournal, configuration: PostHogRetentionConfiguration, appVersion: String,
    send: @escaping Send = PostHogBatchTransport.send
  ) {
    self.journal = journal
    self.configuration = configuration
    self.appVersion = appVersion
    self.send = send
  }

  /// HTTP acceptance is a checkpoint, not proof that downstream ingestion has completed.
  /// Facts remain in the journal. A lost response safely retries the same key/revision/UUID.
  func upload(disclosureShown: Bool, now: Date = Date()) async throws -> Int {
    guard disclosureShown, !isUploading else { return 0 }
    isUploading = true
    defer { isUploading = false }
    let delivery = try journal.deliveryState(destination: configuration.destination)
    guard delivery.nextAttemptAt.map({ $0 <= now }) ?? true else { return 0 }
    let state = try journal.read()
    let events = try RetentionEventBuilder.events(
      state: state, environment: configuration.environment, appVersion: appVersion)
    let batch = Array(
      events.filter { (delivery.acceptedRevisions[$0.key] ?? 0) < $0.revision }.prefix(50))
    guard !batch.isEmpty else { return 0 }
    var request = URLRequest(url: configuration.host.appendingPathComponent("batch/"))
    request.httpMethod = "POST"
    request.timeoutInterval = 15
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("DOCardRetention/1", forHTTPHeaderField: "User-Agent")
    request.httpBody = try JSONSerialization.data(
      withJSONObject: [
        "api_key": configuration.token,
        "historical_migration": false, "batch": batch.map(\.body),
      ], options: [.sortedKeys])
    var retryAfter: TimeInterval?
    do {
      try Task.checkCancellation()
      let (data, response) = try await send(request)
      if let seconds = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init),
        seconds.isFinite
      {
        retryAfter = seconds
      }
      guard (200...299).contains(response.statusCode) else {
        throw UploadError.rejected(response.statusCode)
      }
      struct Receipt: Decodable { let status: Int }
      struct TextReceipt: Decodable { let status: String }
      let accepted =
        (try? JSONDecoder().decode(Receipt.self, from: data).status) == 1
        || (try? JSONDecoder().decode(TextReceipt.self, from: data).status) == "Ok"
      guard accepted else {
        throw UploadError.invalidResponse
      }
      try journal.acceptUpload(
        destination: configuration.destination,
        revisions: Dictionary(uniqueKeysWithValues: batch.map { ($0.key, $0.revision) }))
      return batch.count
    } catch {
      // Cancellation keeps the batch pending; do not punish the next foreground launch.
      if !(error is CancellationError) && !Task.isCancelled {
        try journal.failUpload(
          destination: configuration.destination, now: now, retryAfter: retryAfter)
      }
      throw error
    }
  }
}

/// Ephemeral transport: no cookie persistence, cache or SDK enrichment. Redirects fail closed.
private final class PostHogBatchTransport: NSObject, URLSessionTaskDelegate {
  private static let delegate = PostHogBatchTransport()
  private static let session: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.httpCookieStorage = nil
    config.urlCache = nil
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 20
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }()
  static func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else {
      throw PostHogRetentionUploader.UploadError.invalidResponse
    }
    return (data, http)
  }
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse,
    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }
}
