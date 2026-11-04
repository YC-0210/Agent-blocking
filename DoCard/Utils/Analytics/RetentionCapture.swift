import Foundation
import OSLog

/// Shared local capture. Main-app delivery separately enforces the disclosure gate.
enum RetentionCapture {
  #if DEBUG
    static let environment = "development"
  #else
    static let environment = "production"
  #endif
  @TaskLocal static var journalOverride: RetentionJournal?
  private static let log = Logger(subsystem: "app.docard", category: "RetentionCapture")
  static var journal: RetentionJournal? {
    if let journalOverride { return journalOverride }
    guard
      let group = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.DO.version3")
    else { return nil }
    return RetentionJournal(
      directory: group.appendingPathComponent("retention-v1-\(environment)", isDirectory: true))
  }

  /// Called before any foreground session can start. Extensions never invent a baseline.
  static func prepare() {
    perform { journal in
      guard let defaults = UserDefaults(suiteName: "group.DO.version3") else {
        throw RetentionJournal.JournalError.unavailable
      }
      let existing =
        defaults.string(forKey: "analyticsInstallID") != nil
        || defaults.bool(forKey: "onboardingCompleted")
        || !(defaults.stringArray(forKey: "pairedDOCardTagIds") ?? []).isEmpty
      // Absence of old settings is not proof of a fresh installation.
      let id = defaults.string(forKey: "analyticsInstallID") ?? UUID().uuidString
      try journal.activate(
        installID: id, at: Date(), classification: existing ? "existing_install" : "unknown")
      defaults.set(try journal.read().installID, forKey: "analyticsInstallID")
    }
  }

  static func started(
    _ snapshot: SharedData.SessionSnapshot, eligible: Bool, diagnosticContext: String = ""
  ) {
    diagnose("start session=\(snapshot.id) eligible=\(eligible) \(diagnosticContext)")
    guard eligible, snapshot.endTime == nil else { return }
    perform { journal in
      try journal.recordStart(
        sessionID: snapshot.id, at: snapshot.startTime,
        timeZoneID: TimeZone.current.identifier, trigger: snapshot.triggerSource)
      diagnose("start saved=\(try journal.read().sessions[snapshot.id] != nil) session=\(snapshot.id)")
    }
  }

  static func completed(_ snapshot: SharedData.SessionSnapshot) {
    diagnose("completion session=\(snapshot.id)")
    perform { journal in
      try journal.recordCompletion(
        .init(
          id: snapshot.id, startTime: snapshot.startTime,
          endTime: snapshot.endTime, breakStartTime: snapshot.breakStartTime,
          breakEndTime: snapshot.breakEndTime),
        endReason: snapshot.endReason, asOf: Date())
    }
  }

  static func excludeSession(id: String) {
    perform { try $0.excludeSession(id: id) }
  }

  static func breakChanged(_ snapshot: SharedData.SessionSnapshot) {
    perform {
      try $0.recordBreak(
        sessionID: snapshot.id, start: snapshot.breakStartTime,
        end: snapshot.breakEndTime, asOf: Date())
    }
  }

  private static func diagnose(_ message: String) {
    #if DEBUG
      // Diagnostic only, never a source of session facts or upload acknowledgements.
      guard journalOverride == nil,
        let defaults = UserDefaults(suiteName: "group.DO.version3") else { return }
      let key = "retentionCaptureDiagnostics"
      var entries = defaults.stringArray(forKey: key) ?? []
      entries.append("\(Date().ISO8601Format()) [\(Bundle.main.bundleIdentifier ?? "unknown")] [\(environment)] \(message)")
      defaults.set(Array(entries.suffix(32)), forKey: key)
    #endif
  }

  private static func perform(_ action: (RetentionJournal) throws -> Void) {
    do {
      guard let journal else { throw RetentionJournal.JournalError.unavailable }
      try action(journal)
    } catch {
      // Capture failures must never prevent restricting or unlocking the device.
      log.error("Local retention capture failed: \(String(describing: error), privacy: .private)")
      diagnose("capture error=\(String(describing: error))")
    }
  }
}
