import Foundation
import XCTest

@testable import DoCard

final class RetentionUploadTests: XCTestCase {
  private var directory: URL!
  private let date = Date(timeIntervalSince1970: 1_793_491_200)
  override func setUpWithError() throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  }
  override func tearDownWithError() throws {
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }
  private func fixture() throws -> RetentionJournal {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: date, classification: "existing_install")
    try journal.recordStart(
      sessionID: "session", at: date, timeZoneID: "Asia/Taipei", trigger: "manual")
    try journal.recordCompletion(
      .init(id: "session", startTime: date, endTime: date.addingTimeInterval(7200)),
      endReason: "emergency_unlock", asOf: date.addingTimeInterval(7200))
    return journal
  }
  func testPayloadContainsOnlyTwoRetentionEventsWithOriginalIdentityAndTimes() throws {
    let events = try RetentionEventBuilder.events(
      state: fixture().read(), environment: "development", appVersion: "test")
    XCTAssertEqual(
      events.map(\.name), ["retention_cohort_entered", "retention_locked_time_contributed"])
    XCTAssertEqual(events[0].body["distinct_id"] as? String, "install")
    let properties = try XCTUnwrap(events[1].body["properties"] as? [String: Any])
    XCTAssertEqual(properties["locked_seconds"] as? Double, 7200)
    XCTAssertEqual(properties["period_index"] as? Int, 1)
    XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
    XCTAssertEqual(properties["$geoip_disable"] as? Bool, true)
    XCTAssertEqual(properties["$ip"] as? String, "0.0.0.0")
    XCTAssertEqual(properties["cohort_timezone"] as? String, "Asia/Taipei")
    XCTAssertEqual(
      events[1].body["timestamp"] as? String,
      RetentionEventBuilder.timestamp(date.addingTimeInterval(7200)))
  }
  private var configuration: PostHogRetentionConfiguration {
    PostHogRetentionConfiguration(
      token: "phc_test_project", host: "https://ingest.example.com", environment: "development")!
  }
  func testDisclosureBlocksEveryNetworkRequest() async throws {
    let journal = try fixture()
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { _ in
        XCTFail("No request before disclosure")
        throw URLError(.badServerResponse)
      })
    let count = try await uploader.upload(disclosureShown: false, now: date)
    XCTAssertEqual(count, 0)
    XCTAssertTrue(
      try journal.deliveryState(destination: configuration.destination).acceptedRevisions.isEmpty)
  }
  func testAcceptedBatchIsCheckpointedAcrossReopeningWithoutDeletingFacts() async throws {
    let journal = try fixture()
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { request in
        XCTAssertEqual(request.url?.absoluteString, "https://ingest.example.com/batch/")
        XCTAssertEqual(request.httpMethod, "POST")
        let object = try XCTUnwrap(
          JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        XCTAssertEqual(object["api_key"] as? String, "phc_test_project")
        XCTAssertEqual((object["batch"] as? [[String: Any]])?.count, 2)
        return (
          Data("{\"status\":1}".utf8),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      })
    let count = try await uploader.upload(disclosureShown: true, now: date)
    XCTAssertEqual(count, 2)
    let reopened = PostHogRetentionUploader(
      journal: RetentionJournal(directory: directory), configuration: configuration,
      appVersion: "new-version",
      send: { _ in
        XCTFail("Accepted rows must stay checkpointed after restart")
        throw URLError(.badServerResponse)
      })
    let next = try await reopened.upload(disclosureShown: true, now: date.addingTimeInterval(3600))
    XCTAssertEqual(next, 0)
    XCTAssertEqual(try journal.read().contributions.count, 1)
  }

  func testOfflineRetryUsesSameUUIDsAndPersistentBackoff() async throws {
    let journal = try fixture()
    let log = UploadRequestLog()
    let first = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { request in
        await log.record(request)
        throw URLError(.notConnectedToInternet)
      })
    do {
      _ = try await first.upload(disclosureShown: true, now: date)
      XCTFail("Must report offline")
    } catch {}
    let delivery = try journal.deliveryState(destination: configuration.destination)
    XCTAssertTrue(delivery.acceptedRevisions.isEmpty)
    XCTAssertEqual(delivery.nextAttemptAt, date.addingTimeInterval(30))
    let restarted = PostHogRetentionUploader(
      journal: RetentionJournal(directory: directory), configuration: configuration,
      appVersion: "test",
      send: { request in
        await log.record(request)
        return Self.accepted(request)
      })
    let deferred = try await restarted.upload(
      disclosureShown: true, now: date.addingTimeInterval(29))
    XCTAssertEqual(deferred, 0)
    let retried = try await restarted.upload(
      disclosureShown: true, now: date.addingTimeInterval(30))
    XCTAssertEqual(retried, 2)
    let requests = await log.requests
    XCTAssertEqual(requests.count, 2)
    XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
    XCTAssertEqual(
      try journal.deliveryState(destination: configuration.destination).failedAttempts, 0)
  }
  func testRejectedHTTPAndInvalidReceiptsNeverAcknowledge() async throws {
    let journal = try fixture()
    for (index, scenario) in [
      (400, "{\"status\":1}"), (401, "{\"status\":1}"), (429, "{\"status\":1}"),
      (500, "{\"status\":1}"), (200, ""), (200, "<html>"), (200, "{\"status\":0}"),
      (200, "{\"status\":true}"),
    ].enumerated() {
      let uploader = PostHogRetentionUploader(
        journal: journal, configuration: configuration, appVersion: "test",
        send: { request in
          (
            Data(scenario.1.utf8),
            HTTPURLResponse(
              url: request.url!, statusCode: scenario.0, httpVersion: nil, headerFields: nil)!
          )
        })
      do {
        _ = try await uploader.upload(
          disclosureShown: true, now: date.addingTimeInterval(Double(index) * 90000))
        XCTFail("Must reject \(scenario)")
      } catch {}
      XCTAssertTrue(
        try journal.deliveryState(destination: configuration.destination).acceptedRevisions.isEmpty)
    }
    XCTAssertEqual(try journal.read().contributions.count, 1)
  }
  func testCurrentCloudOkReceiptAcknowledgesBatch() async throws {
    let journal = try fixture()
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { request in
        (
          Data("{\"status\":\"Ok\"}".utf8),
          HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
      })
    let count = try await uploader.upload(disclosureShown: true, now: date)
    XCTAssertEqual(count, 2)
    XCTAssertEqual(
      try journal.deliveryState(destination: configuration.destination).acceptedRevisions.count, 2)
  }

  func testRateLimitHonorsRetryAfter() async throws {
    let journal = try fixture()
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { request in
        (
          Data(),
          HTTPURLResponse(
            url: request.url!, statusCode: 429, httpVersion: nil,
            headerFields: ["Retry-After": "300"])!
        )
      })
    do {
      _ = try await uploader.upload(disclosureShown: true, now: date)
      XCTFail("Must defer")
    } catch {}
    XCTAssertEqual(
      try journal.deliveryState(destination: configuration.destination).nextAttemptAt,
      date.addingTimeInterval(300))
  }
  func testConcurrentCorrectionIsNotAcknowledgedByOlderInFlightBatch() async throws {
    let journal = try fixture()
    let date = date
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { request in
        try journal.recordCompletion(
          .init(id: "session", startTime: date, endTime: date.addingTimeInterval(9000)),
          endReason: "emergency_unlock", asOf: date.addingTimeInterval(9000))
        return Self.accepted(request)
      })
    _ = try await uploader.upload(disclosureShown: true, now: date)
    let checkpoint = try journal.deliveryState(destination: configuration.destination)
    XCTAssertEqual(checkpoint.acceptedRevisions.values.sorted(), [1, 1])
    let log = UploadRequestLog()
    let next = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { request in
        await log.record(request)
        return Self.accepted(request)
      })
    let count = try await next.upload(disclosureShown: true, now: date)
    XCTAssertEqual(count, 1)
    let captured = await log.requests
    let request = try XCTUnwrap(captured.first)
    let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
    let batch = body["batch"] as! [[String: Any]]
    let properties = batch[0]["properties"] as! [String: Any]
    XCTAssertEqual(properties["revision"] as? Int, 2)
    XCTAssertEqual(properties["locked_seconds"] as? Double, 9000)
  }
  func testDifferentProjectDestinationGetsItsOwnCheckpoint() async throws {
    let journal = try fixture()
    let first = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test", send: Self.accepted)
    _ = try await first.upload(disclosureShown: true, now: date)
    let other = PostHogRetentionConfiguration(
      token: "phc_other_project", host: "https://ingest.example.com", environment: "development")!
    let second = PostHogRetentionUploader(
      journal: journal, configuration: other, appVersion: "test", send: Self.accepted)
    let count = try await second.upload(disclosureShown: true, now: date)
    XCTAssertEqual(count, 2)
  }
  func testLargeBacklogUsesBoundedBatchesAndEventuallyDrains() async throws {
    let journal = try fixture()
    for i in 0..<65 {
      try journal.recordStart(
        sessionID: "extra-\(i)", at: date, timeZoneID: "UTC", trigger: "scheduled")
      try journal.recordCompletion(
        .init(id: "extra-\(i)", startTime: date, endTime: date.addingTimeInterval(60)),
        endReason: "timer_expired", asOf: date.addingTimeInterval(60))
    }
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test", send: Self.accepted)
    let first = try await uploader.upload(disclosureShown: true, now: date)
    let second = try await uploader.upload(disclosureShown: true, now: date)
    let third = try await uploader.upload(disclosureShown: true, now: date)
    XCTAssertEqual([first, second, third], [50, 17, 0])
  }
  func testUUIDIsStableAcrossReplayAndChangesForRevisionAndEnvironment() throws {
    let journal = try fixture()
    let first = try RetentionEventBuilder.events(
      state: journal.read(), environment: "development", appVersion: "1")
    let replay = try RetentionEventBuilder.events(
      state: journal.read(), environment: "development", appVersion: "2")
    let production = try RetentionEventBuilder.events(
      state: journal.read(), environment: "production", appVersion: "1")
    XCTAssertEqual(first[1].body["uuid"] as? String, replay[1].body["uuid"] as? String)
    XCTAssertNotEqual(first[1].body["uuid"] as? String, production[1].body["uuid"] as? String)
    try journal.recordCompletion(
      .init(id: "session", startTime: date, endTime: date.addingTimeInterval(60)),
      endReason: "emergency_unlock", asOf: date.addingTimeInterval(7200))
    let corrected = try RetentionEventBuilder.events(
      state: journal.read(), environment: "development", appVersion: "1")
    XCTAssertNotEqual(first[1].body["uuid"] as? String, corrected[1].body["uuid"] as? String)
  }
  func testRetractionIsSentAsZeroWithNewRevision() throws {
    let journal = try fixture()
    try journal.recordBreak(
      sessionID: "session", start: date, end: nil, asOf: date.addingTimeInterval(7200))
    let events = try RetentionEventBuilder.events(
      state: journal.read(), environment: "development", appVersion: "test")
    let properties = events[1].body["properties"] as! [String: Any]
    XCTAssertEqual(properties["locked_seconds"] as? Double, 0)
    XCTAssertEqual(properties["revision"] as? Int, 2)
  }
  func testRunningSessionSendsOnlyCohortAndEmptyInstallSendsNothing() throws {
    let journal = RetentionJournal(directory: directory)
    try journal.activate(installID: "install", at: date, classification: "unknown")
    XCTAssertTrue(
      try RetentionEventBuilder.events(
        state: journal.read(), environment: "development", appVersion: "test"
      ).isEmpty)
    try journal.recordStart(sessionID: "session", at: date, timeZoneID: "UTC", trigger: "manual")
    XCTAssertEqual(
      try RetentionEventBuilder.events(
        state: journal.read(), environment: "development", appVersion: "test"
      ).map(\.name), ["retention_cohort_entered"])
  }
  func testConfigurationRejectsPersonalKeysAndInvalidDestinations() {
    for (token, host, environment) in [
      ("phx_personal", "https://example.com", "production"),
      ("", "https://example.com", "development"),
      ("phc_project_token", "http://example.com", "production"),
      ("phc_project_token", "https://user:password@example.com", "production"),
      ("phc_project_token", "https://example.com/path", "production"),
      ("phc_project_token", "https://example.com?token=test", "production"),
      ("phc_project_token", "https://example.com", "$(ENVIRONMENT)"),
    ] {
      XCTAssertNil(
        PostHogRetentionConfiguration(token: token, host: host, environment: environment))
    }
  }
  func testBackoffIsCappedAndDoesNotErasePendingFacts() throws {
    let journal = try fixture()
    for _ in 0..<20 { try journal.failUpload(destination: configuration.destination, now: date) }
    XCTAssertEqual(
      try journal.deliveryState(destination: configuration.destination).nextAttemptAt,
      date.addingTimeInterval(3600))
    XCTAssertEqual(try journal.read().contributions.count, 1)
  }
  func testCancellationKeepsBatchPendingWithoutAddingBackoff() async throws {
    let journal = try fixture()
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: "test",
      send: { _ in
        throw CancellationError()
      })
    do {
      _ = try await uploader.upload(disclosureShown: true, now: date)
      XCTFail("Expected cancellation")
    } catch {}
    let delivery = try journal.deliveryState(destination: configuration.destination)
    XCTAssertTrue(delivery.acceptedRevisions.isEmpty)
    XCTAssertEqual(delivery.failedAttempts, 0)
    XCTAssertNil(delivery.nextAttemptAt)
  }

  private static func accepted(_ request: URLRequest) -> (Data, HTTPURLResponse) {
    (
      Data("{\"status\":1}".utf8),
      HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    )
  }

}

private actor UploadRequestLog {
  var requests: [URLRequest] = []
  func record(_ request: URLRequest) { requests.append(request) }
}
