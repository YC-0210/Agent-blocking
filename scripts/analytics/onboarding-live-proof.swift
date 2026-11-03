import Foundation

/// Compile with the onboarding journal/uploader and the retention journal/calculator/event builder.
/// Only synthetic DEVELOPMENT records are allowed. No personal/query API key is used.
@main
struct OnboardingLiveProof {
  @MainActor static func main() async throws {
    let env = ProcessInfo.processInfo.environment
    guard let token = env["DOCardPostHogToken"], let host = env["DOCardPostHogHost"],
      let config = OnboardingPostHogConfiguration(
        token: token, host: host, environment: "development"),
      let output = env["OnboardingProofDirectory"]
    else { fatalError("Public ingestion config and output directory required") }
    let directory = URL(fileURLWithPath: output)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let run = UUID().uuidString.lowercased().prefix(8)
    let prefix = "retention-upload-test-onboarding-\(run)-"
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(secondsFromGMT: 0)!
    let start = cal.date(byAdding: .day, value: -9, to: cal.startOfDay(for: Date()))!
      .addingTimeInterval(3600)
    var allBodies: [[String: Any]] = []
    var summaries: [[String: Any]] = []
    for name in ["study", "work", "missing"] {
      let id = prefix + name
      let journal = OnboardingJournal(
        directory: directory.appendingPathComponent(name), installID: id,
        environment: "development", isSynthetic: true)
      _ = try journal.begin(at: start.addingTimeInterval(-3600), appVersion: "onboarding-proof-1")
      if name != "missing" {
        var answers = OnboardingAnswers(
          purposes: name == "study" ? ["study", "major_exam", "other"] : ["work_tasks"],
          habits: ["boredom", "other"],
          purposeOtherText: name == "study" ? "Quiet project" : "",
          habitOtherText: "A synthetic custom answer", dailyPhoneTime: "4_5h")
        for (index, question) in ["purposes", "habits", "daily_phone_time"].enumerated() {
          try journal.confirm(
            question, answers: answers, at: start.addingTimeInterval(Double(-300 + index)),
            appVersion: "onboarding-proof-1")
        }
        try journal.complete(at: start.addingTimeInterval(-10), appVersion: "onboarding-proof-1")
        if name == "study" {
          answers.purposes = ["work_tasks"]
          try journal.confirm(
            "purposes", answers: answers, at: start.addingTimeInterval(86400),
            appVersion: "onboarding-proof-2")
          try journal.confirm(
            "daily_phone_time", answers: answers, at: start.addingTimeInterval(86401),
            appVersion: "onboarding-proof-2")
        }
      }
      // A failed connection leaves every event pending and records a persistent retry deadline.
      let offline = OnboardingPostHogUploader(journal: journal, configuration: config) { _ in
        throw URLError(.notConnectedToInternet)
      }
      do {
        try await offline.upload(disclosureShown: true, now: Date().addingTimeInterval(-60))
      } catch { /* Expected injected offline failure. */  }
      let reopened = OnboardingJournal(
        directory: directory.appendingPathComponent(name), installID: id,
        environment: "development", isSynthetic: true)
      let uploader = OnboardingPostHogUploader(journal: reopened, configuration: config)
      let delivered = try await uploader.upload(disclosureShown: true)
      let repeated = try await uploader.upload(disclosureShown: true)
      guard repeated == 0 else { fatalError("Accepted events were requeued") }
      let state = try reopened.read()
      allBodies += state.events.map { OnboardingPostHogUploader.body(for: $0, state: state) }

      // Retention's exact Swift calculator/event builder is read from the other worktree,
      // never edited or copied into this branch. This is synthetic source data, not a real lock.
      let retention = RetentionJournal(
        directory: directory.appendingPathComponent(name + "-retention"))
      try retention.activate(
        installID: id, at: start.addingTimeInterval(-7200), classification: "unknown")
      try retention.recordStart(
        sessionID: name + "-session", at: start, timeZoneID: "UTC", trigger: "manual")
      let seconds: TimeInterval = name == "work" ? 3600 : 7200
      try retention.recordCompletion(
        .init(
          id: name + "-session", startTime: start,
          endTime: start.addingTimeInterval(seconds), breakStartTime: nil, breakEndTime: nil),
        endReason: "card_tap", asOf: Date())
      let retentionEvents = try RetentionEventBuilder.events(
        state: retention.read(), environment: "development", appVersion: "onboarding-proof-1")
      let bodies = retentionEvents.map(\.body)
      var request = URLRequest(url: config.host.appendingPathComponent("batch/"))
      request.httpMethod = "POST"
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: [
        "api_key": token, "batch": bodies,
      ])
      let (_, response) = try await OnboardingBatchTransport.send(request)
      guard (200...299).contains(response.statusCode) else {
        fatalError("Synthetic retention fixture rejected")
      }
      allBodies += bodies
      summaries.append([
        "distinct_id": id, "case": name, "onboarding_events": delivered,
        "locked_seconds": seconds, "expected_retained_period_1": seconds >= 7200,
        "cohort_started_at": OnboardingPostHogUploader.timestamp(start),
      ])
    }
    let summary: [String: Any] = [
      "prefix": prefix, "environment": "development", "is_synthetic": true,
      "fixtures": summaries,
      "expected": ["study": "1/1", "major_exam": "1/1", "other": "1/1", "work_tasks": "0/1", "unknown": "1/1"],
    ]
    try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("manifest.json"))
    try JSONSerialization.data(withJSONObject: allBodies, options: [.prettyPrinted, .sortedKeys])
      .write(to: directory.appendingPathComponent("expected-events.json"))
    print("Sent synthetic development proof: \(prefix)")
    print("Expected groups: study 1/1, major_exam 1/1, work_tasks 0/1, unknown 1/1")
    print("No token is included in proof artifacts.")
  }
}
