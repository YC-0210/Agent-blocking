import Foundation
import OSLog
import UIKit

@MainActor
final class OnboardingTracking {
  static let shared = OnboardingTracking()
  #if DEBUG
    static let environment = "development"
  #else
    static let environment = "production"
  #endif
  private let log = Logger(subsystem: "online.do.card.app", category: "OnboardingTracking")
  private var journal: OnboardingJournal?
  private var uploader: OnboardingPostHogUploader?
  private var task: Task<Void, Never>?
  private var timer: Task<Void, Never>?
  private var observers: [NSObjectProtocol] = []
  private var started = false
  private var isActive = true
  private let version =
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"

  private var isPreview: Bool {
    #if DEBUG && targetEnvironment(simulator)
      ProcessInfo.processInfo.arguments.contains("--onboarding-ui-prototype")
        && !ProcessInfo.processInfo.arguments.contains("--onboarding-tracking-fixture")
    #else
      false
    #endif
  }

  func start() {
    guard !started else { return }
    started = true
    guard !isPreview,
      let group = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.DO.version3")
    else { return }
    #if DEBUG && targetEnvironment(simulator)
      let synthetic = ProcessInfo.processInfo.arguments.contains("--onboarding-tracking-fixture")
    #else
      let synthetic = false
    #endif
    let journal = OnboardingJournal(
      directory: group.appendingPathComponent(
        "onboarding-v1-\(Self.environment)\(synthetic ? "-fixture" : "")"),
      installID: AnalyticsIdentity.installID, environment: Self.environment, isSynthetic: synthetic)
    self.journal = journal
    func config(_ key: String) -> String? {
      #if DEBUG
        if let value = ProcessInfo.processInfo.environment[key] { return value }
      #endif
      return Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
    if let token = config("DOCardPostHogToken"), let host = config("DOCardPostHogHost"),
      let environment = config("DOCardPostHogEnvironment"),
      let configuration = OnboardingPostHogConfiguration(
        token: token, host: host, environment: environment),
      configuration.environment == Self.environment
    {
      uploader = OnboardingPostHogUploader(journal: journal, configuration: configuration)
    }
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(
        forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
      ) {
        [weak self] _ in
        Task { @MainActor in
          self?.isActive = true
          self?.flushSoon()
        }
      })
    observers.append(
      center.addObserver(
        forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
      ) {
        [weak self] _ in
        Task { @MainActor in
          self?.isActive = false
          self?.task?.cancel()
        }
      })
    // Same notification contract used by the other worktree, without importing its source.
    observers.append(
      center.addObserver(
        forName: Notification.Name("DOCardAnalyticsDisclosureChanged"), object: nil, queue: .main
      ) {
        [weak self] _ in Task { @MainActor in self?.flushSoon() }
      })
    timer = Task { [weak self] in
      while !Task.isCancelled {
        do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
        self?.flushSoon()
      }
    }
    flushSoon()
  }

  func restore() -> OnboardingAnswers? {
    start()
    do { return try journal?.begin(at: Date(), appVersion: version) } catch {
      report(error)
      return nil
    }
  }

  func saveDraft(_ answers: OnboardingAnswers) {
    do { try journal?.saveDraft(answers) } catch { report(error) }
  }

  func confirm(_ question: String, answers: OnboardingAnswers) {
    do { try journal?.confirm(question, answers: answers, at: Date(), appVersion: version) } catch {
      report(error)
    }
    flushSoon()
  }

  func completeStep(_ step: String) {
    do { try journal?.completeStep(step, at: Date(), appVersion: version) } catch { report(error) }
    flushSoon()
  }

  func complete() {
    do { try journal?.complete(at: Date(), appVersion: version) } catch { report(error) }
    flushSoon()
  }

  private func flushSoon() {
    guard task == nil, isActive, let uploader else { return }
    task = Task { [weak self] in
      defer { self?.task = nil }
      do {
        for _ in 0..<5 {
          try Task.checkCancellation()
          let count = try await uploader.upload(
            disclosureShown: AnalyticsConsent.disclosureShown && AnalyticsConsent.isGeneralEnabled)
          if count == 0 { break }
        }
      } catch { if !Task.isCancelled { self?.report(error) } }
    }
  }

  private func report(_ error: Error) {
    log.error(
      "Onboarding data deferred; no effect on app setup: \(String(describing: error), privacy: .private)"
    )
  }
}
