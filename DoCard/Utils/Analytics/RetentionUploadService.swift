import Foundation
import OSLog

/// Main-app foreground delivery only; extension callbacks only append local facts.
@MainActor
enum RetentionUploadService {
  static let disclosureChanged = Notification.Name("DOCardAnalyticsDisclosureChanged")
  private static let log = Logger(subsystem: "app.docard", category: "RetentionUpload")
  private static var task: Task<Void, Never>?

  static func setActive(_ isActive: Bool) {
    task?.cancel()
    task = nil
    guard isActive,
      let token = Bundle.main.object(forInfoDictionaryKey: "DOCardPostHogToken") as? String,
      let host = Bundle.main.object(forInfoDictionaryKey: "DOCardPostHogHost") as? String,
      let environment = Bundle.main.object(forInfoDictionaryKey: "DOCardPostHogEnvironment")
        as? String,
      let configuration = PostHogRetentionConfiguration(
        token: token, host: host, environment: environment),
      configuration.environment == RetentionCapture.environment,
      let journal = RetentionCapture.journal
    else { return }
    let version =
      Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    let uploader = PostHogRetentionUploader(
      journal: journal, configuration: configuration, appVersion: version)
    task = Task {
      while !Task.isCancelled {
        do {
          // Bound each drain; later foreground ticks continue large offline backlogs.
          for _ in 0..<5 {
            try Task.checkCancellation()
            let count = try await uploader.upload(disclosureShown: AnalyticsConsent.disclosureShown)
            if count == 0 { break }
          }
        } catch {
          if !Task.isCancelled {
            log.error(
              "Retention upload deferred; journal retained: \(String(describing: error), privacy: .private)"
            )
          }
        }
        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
      }
    }
  }
}
