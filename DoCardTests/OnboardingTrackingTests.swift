import XCTest

@testable import DoCard

@MainActor
final class OnboardingTrackingTests: XCTestCase {
  private let date = Date(timeIntervalSince1970: 1_780_000_000)

  private func fixture() throws -> (URL, OnboardingJournal) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let journal = OnboardingJournal(
      directory: directory, installID: "onboarding-tracking-test-user",
      environment: "development", isSynthetic: true)
    _ = try journal.begin(at: date, appVersion: "1.0")
    addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
    return (directory, journal)
  }

  private var answers: OnboardingAnswers {
    .init(purposes: ["study", "major_exam"], habits: ["boredom"], dailyPhoneTime: "4_5h")
  }

  private func configuration(_ token: String = "phc_test_project") -> OnboardingPostHogConfiguration
  {
    OnboardingPostHogConfiguration(
      token: token, host: "https://us.i.posthog.com", environment: "development")!
  }

  private func response(
    _ request: URLRequest, status: Int = 200, body: String = "{\"status\":\"Ok\"}",
    headers: [String: String]? = nil
  ) -> (Data, HTTPURLResponse) {
    (
      Data(body.utf8),
      HTTPURLResponse(
        url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
    )
  }

  func testDraftAndEventIdentitySurviveRestart() throws {
    let (directory, journal) = try fixture()
    var draft = answers
    draft.purposes.insert("other")
    draft.purposeOtherText = "My project"
    try journal.saveDraft(draft)
    let first = try journal.read()
    let reopened = OnboardingJournal(
      directory: directory, installID: first.installID,
      environment: "development", isSynthetic: true)
    XCTAssertEqual(try reopened.begin(at: date.addingTimeInterval(10), appVersion: "2.0"), draft)
    XCTAssertEqual(try reopened.read().events, first.events)
  }

  func testSubmissionHistoryPreservesEntryAnswersAndIgnoresRepeatedTaps() throws {
    let (_, journal) = try fixture()
    for q in ["purposes", "habits", "daily_phone_time"] {
      try journal.confirm(q, answers: answers, at: date, appVersion: "1")
    }
    try journal.confirm("purposes", answers: answers, at: date, appVersion: "1")
    try journal.confirm("daily_phone_time", answers: answers, at: date, appVersion: "1")
    XCTAssertEqual(try journal.read().events.count, 5)
    var changed = answers
    changed.purposes = ["work_tasks"]
    try journal.confirm(
      "purposes", answers: changed, at: date.addingTimeInterval(100), appVersion: "1")
    try journal.confirm(
      "daily_phone_time", answers: changed, at: date.addingTimeInterval(101), appVersion: "1")
    let submitted = try journal.read().events.filter { $0.name == "onboarding_answers_submitted" }
    XCTAssertEqual(submitted.count, 2)
    XCTAssertEqual(submitted.first?.answers?.purposes, ["study", "major_exam"])
    XCTAssertEqual(submitted.last?.answers?.purposes, ["work_tasks"])
  }

  func testInvalidAnswersAndBlankOtherDoNotConfirm() throws {
    let (_, journal) = try fixture()
    var invalid = answers
    invalid.purposes = ["other"]
    invalid.purposeOtherText = " \n "
    XCTAssertThrowsError(
      try journal.confirm("purposes", answers: invalid, at: date, appVersion: "1"))
    invalid.purposes = ["invented"]
    XCTAssertThrowsError(
      try journal.confirm("purposes", answers: invalid, at: date, appVersion: "1"))
    XCTAssertThrowsError(try journal.complete(at: date, appVersion: "1"))
    XCTAssertEqual(try journal.read().events.count, 1)
  }

  func testUnselectedOtherDraftIsNotSentAndSelectedTextIsTrimmed() throws {
    let (_, journal) = try fixture()
    var draft = answers
    draft.purposeOtherText = "private unused draft"
    draft.habits.insert("other")
    draft.habitOtherText = "  My habit  "
    try journal.confirm("daily_phone_time", answers: draft, at: date, appVersion: "1")
    let state = try journal.read()
    let body = OnboardingPostHogUploader.body(for: state.events.last!, state: state)
    let properties = body["properties"] as! [String: Any]
    XCTAssertNil(properties["purpose_other_text"])
    XCTAssertEqual(properties["habit_other_text"] as? String, "My habit")
    XCTAssertEqual(state.draft.purposeOtherText, "private unused draft")
  }

  func testCompletionIsSeparateAndIdempotent() throws {
    let (_, journal) = try fixture()
    try journal.confirm("daily_phone_time", answers: answers, at: date, appVersion: "1")
    XCTAssertFalse(try journal.read().events.contains { $0.name == "onboarding_completed" })
    try journal.complete(at: date, appVersion: "1")
    try journal.complete(at: date.addingTimeInterval(1), appVersion: "1")
    XCTAssertEqual(try journal.read().events.filter { $0.name == "onboarding_completed" }.count, 1)
  }

  func testCorruptJournalIsNotSilentlyReplaced() throws {
    let (directory, journal) = try fixture()
    let url = directory.appendingPathComponent("onboarding.json")
    try Data("broken".utf8).write(to: url)
    XCTAssertThrowsError(try journal.begin(at: date, appVersion: "1"))
    XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "broken")
    let wrong = OnboardingJournal(
      directory: directory, installID: "other", environment: "development")
    XCTAssertThrowsError(try wrong.read())
  }

  func testDisclosureAndEnvironmentGateTransport() async throws {
    let (_, journal) = try fixture()
    var calls = 0
    let uploader = OnboardingPostHogUploader(journal: journal, configuration: configuration()) {
      request in
      calls += 1
      return self.response(request)
    }
    let hidden = try await uploader.upload(disclosureShown: false)
    XCTAssertEqual(hidden, 0)
    XCTAssertEqual(calls, 0)
    let prod = OnboardingPostHogConfiguration(
      token: "phc_test_project", host: "https://us.i.posthog.com", environment: "production")!
    let other = OnboardingPostHogUploader(journal: journal, configuration: prod) { request in
      calls += 1
      return self.response(request)
    }
    let mismatch = try await other.upload(disclosureShown: true)
    XCTAssertEqual(mismatch, 0)
    XCTAssertEqual(calls, 0)
  }

  func testOfflineRetryRetainsUUIDTimestampAndBackoffAcrossRestart() async throws {
    let (directory, journal) = try fixture()
    let config = configuration()
    var first: Data?
    let offline = OnboardingPostHogUploader(journal: journal, configuration: config) { request in
      first = request.httpBody
      throw URLError(.notConnectedToInternet)
    }
    do {
      try await offline.upload(disclosureShown: true, now: date)
      XCTFail()
    } catch {}
    let reopened = OnboardingJournal(
      directory: directory, installID: journal.installID,
      environment: "development", isSynthetic: true)
    XCTAssertTrue(
      try reopened.pending(destination: config.destination, now: date.addingTimeInterval(29))
        .isEmpty)
    let retry = OnboardingPostHogUploader(journal: reopened, configuration: config) { request in
      XCTAssertEqual(first, request.httpBody)
      return self.response(request)
    }
    let count = try await retry.upload(disclosureShown: true, now: date.addingTimeInterval(30))
    XCTAssertEqual(count, 1)
  }

  func testReceiptMustBeRecognizedAndRateLimitPersists() async throws {
    for receipt in ["", "{}", "{\"status\":true}", "{\"status\":\"bad\"}"] {
      let (_, journal) = try fixture()
      let config = configuration()
      let uploader = OnboardingPostHogUploader(journal: journal, configuration: config) { request in
        self.response(request, body: receipt)
      }
      do {
        try await uploader.upload(disclosureShown: true, now: date)
        XCTFail(receipt)
      } catch {}
      XCTAssertEqual(
        try journal.pending(destination: config.destination, now: date.addingTimeInterval(31))
          .count, 1)
    }
    let (_, journal) = try fixture()
    let config = configuration()
    let limited = OnboardingPostHogUploader(journal: journal, configuration: config) { request in
      self.response(request, status: 429, headers: ["Retry-After": "120"])
    }
    do {
      try await limited.upload(disclosureShown: true, now: date)
      XCTFail()
    } catch {}
    XCTAssertTrue(
      try journal.pending(destination: config.destination, now: date.addingTimeInterval(119))
        .isEmpty)
    XCTAssertEqual(
      try journal.pending(destination: config.destination, now: date.addingTimeInterval(120)).count,
      1)
  }

  func testAcceptedEventsAreNotResentAndDestinationsAreIsolated() async throws {
    let (_, journal) = try fixture()
    let config = configuration()
    var calls = 0
    let uploader = OnboardingPostHogUploader(journal: journal, configuration: config) { request in
      calls += 1
      return self.response(request, body: "{\"status\":1}")
    }
    _ = try await uploader.upload(disclosureShown: true)
    _ = try await uploader.upload(disclosureShown: true)
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(
      try journal.pending(destination: configuration("phc_other_project").destination, now: date)
        .count, 1)
  }

  func testEventAddedDuringUploadRemainsPending() async throws {
    let (_, journal) = try fixture()
    let config = configuration()
    let uploader = OnboardingPostHogUploader(journal: journal, configuration: config) { request in
      try journal.confirm("purposes", answers: self.answers, at: self.date, appVersion: "1")
      return self.response(request)
    }
    _ = try await uploader.upload(disclosureShown: true)
    let pending = try journal.pending(destination: config.destination, now: date)
    XCTAssertEqual(pending.count, 1)
    XCTAssertEqual(pending.first?.questionID, "purposes")
  }

  func testPayloadHasSameInstallIDAndOriginalVersionWithoutWaitingForCohort() async throws {
    let (_, journal) = try fixture()
    let uploader = OnboardingPostHogUploader(journal: journal, configuration: configuration()) {
      request in
      let json = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      let event = (json["batch"] as! [[String: Any]]).first!
      XCTAssertEqual(event["distinct_id"] as? String, journal.installID)
      XCTAssertEqual(event["event"] as? String, "onboarding_started")
      XCTAssertEqual(event["timestamp"] as? String, OnboardingPostHogUploader.timestamp(self.date))
      let properties = event["properties"] as! [String: Any]
      XCTAssertEqual(properties["install_id"] as? String, journal.installID)
      XCTAssertEqual(properties["app_version"] as? String, "1.0")
      XCTAssertEqual(properties["$process_person_profile"] as? Bool, false)
      XCTAssertEqual(properties["is_synthetic"] as? Bool, true)
      return self.response(request)
    }
    let count = try await uploader.upload(disclosureShown: true)
    XCTAssertEqual(count, 1)
  }

  func testBatchIsBoundedAndRemainingEventsAreNotLost() async throws {
    let (_, journal) = try fixture()
    for index in 0..<54 {
      var draft = answers
      draft.purposes = index.isMultiple(of: 2) ? ["study"] : ["work_tasks"]
      try journal.confirm("purposes", answers: draft, at: date, appVersion: "1")
    }
    var sizes: [Int] = []
    let uploader = OnboardingPostHogUploader(journal: journal, configuration: configuration()) {
      request in
      let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
      sizes.append((body["batch"] as! [[String: Any]]).count)
      return self.response(request)
    }
    _ = try await uploader.upload(disclosureShown: true)
    _ = try await uploader.upload(disclosureShown: true)
    _ = try await uploader.upload(disclosureShown: true)
    XCTAssertEqual(sizes, [50, 5])
  }

  func testCancellationDoesNotAddRetryDelay() async throws {
    let (_, journal) = try fixture()
    let config = configuration()
    let uploader = OnboardingPostHogUploader(journal: journal, configuration: config) { _ in
      throw CancellationError()
    }
    do {
      try await uploader.upload(disclosureShown: true, now: date)
      XCTFail()
    } catch {}
    XCTAssertEqual(try journal.pending(destination: config.destination, now: date).count, 1)
  }

  func testConcurrentDrainDoesNotSendSameBatchTwice() async throws {
    let (_, journal) = try fixture()
    let started = expectation(description: "First request is in flight")
    var continuation: CheckedContinuation<Void, Never>?
    var calls = 0
    let uploader = OnboardingPostHogUploader(journal: journal, configuration: configuration()) {
      request in
      calls += 1
      await withCheckedContinuation {
        continuation = $0
        started.fulfill()
      }
      return self.response(request)
    }
    let first = Task { try await uploader.upload(disclosureShown: true) }
    await fulfillment(of: [started], timeout: 2)
    let concurrent = try await uploader.upload(disclosureShown: true)
    XCTAssertEqual(concurrent, 0)
    continuation?.resume()
    _ = try await first.value
    XCTAssertEqual(calls, 1)
  }

  func testSetupStepCompletionIsRecordedOnceAndUsesStepID() throws {
    let (_, journal) = try fixture()
    try journal.completeStep("permissions", at: date, appVersion: "1")
    try journal.completeStep("permissions", at: date.addingTimeInterval(1), appVersion: "1")
    XCTAssertEqual(try journal.read().events.count, 2)
    let state = try journal.read()
    let body = OnboardingPostHogUploader.body(for: state.events.last!, state: state)
    let properties = body["properties"] as! [String: Any]
    XCTAssertEqual(properties["step_id"] as? String, "permissions")
    XCTAssertNil(properties["question_id"])
    XCTAssertThrowsError(try journal.completeStep("invented", at: date, appVersion: "1"))
  }

  func testConfigurationRejectsAdminKeysAndInvalidHosts() {
    XCTAssertNil(
      OnboardingPostHogConfiguration(
        token: "phx_admin_secret", host: "https://us.i.posthog.com", environment: "development"))
    XCTAssertNil(
      OnboardingPostHogConfiguration(
        token: "phc_test_project", host: "http://us.i.posthog.com", environment: "development"))
    XCTAssertNil(
      OnboardingPostHogConfiguration(
        token: "phc_test_project", host: "https://x.test/path", environment: "development"))
  }
}
