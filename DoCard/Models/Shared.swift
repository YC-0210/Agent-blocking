import FamilyControls
import Foundation

enum SharedData {
  private static let suite: UserDefaults = {
    guard let defaults = UserDefaults(suiteName: "group.DO.version3") else {
      // Fallback to standard UserDefaults if App Group is unavailable
      print("⚠️ SharedData: App Group 'group.DO.version3' unavailable, falling back to standard UserDefaults")
      return UserDefaults.standard
    }
    return defaults
  }()

  // MARK: – Keys
  private enum Key: String {
    case profileSnapshots
    case activeScheduleSession
    case completedScheduleSessions
  }

  // MARK: – Serializable snapshot of a profile (no sessions)
  struct ProfileSnapshot: Codable, Equatable {
    var id: UUID
    var name: String
    var selectedActivity: FamilyActivitySelection
    var createdAt: Date
    var updatedAt: Date
    var blockingStrategyId: String?
    var strategyData: Data?
    var order: Int

    var enableLiveActivity: Bool
    var reminderTimeInSeconds: UInt32?
    var customReminderMessage: String?
    var enableBreaks: Bool
    var breakTimeInMinutes: Int = 15
    var enableStrictMode: Bool
    var enableAllowMode: Bool
    var enableAllowModeDomains: Bool
    var enableSafariBlocking: Bool

    var domains: [String]?
    var physicalUnblockNFCTagId: String?

    var schedule: BlockedProfileSchedule?

    var disableBackgroundStops: Bool?
  }

  // MARK: – Serializable snapshot of a session (no profile object)
  struct SessionSnapshot: Codable, Equatable {
    var id: String
    var tag: String
    var blockedProfileId: UUID

    var startTime: Date
    var endTime: Date?

    var breakStartTime: Date?
    var breakEndTime: Date?

    var forceStarted: Bool
  }

  // MARK: – Persisted snapshots keyed by profile ID (UUID string)
  static var profileSnapshots: [String: ProfileSnapshot] {
    get {
      guard let data = suite.data(forKey: Key.profileSnapshots.rawValue) else { return [:] }
      return (try? JSONDecoder().decode([String: ProfileSnapshot].self, from: data)) ?? [:]
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        suite.set(data, forKey: Key.profileSnapshots.rawValue)
      } else {
        print("⚠️ SharedData: Failed to encode profileSnapshots, preserving existing data")
      }
    }
  }

  static func snapshot(for profileID: String) -> ProfileSnapshot? {
    profileSnapshots[profileID]
  }

  static func setSnapshot(_ snapshot: ProfileSnapshot, for profileID: String) {
    var all = profileSnapshots
    all[profileID] = snapshot
    profileSnapshots = all
  }

  static func removeSnapshot(for profileID: String) {
    var all = profileSnapshots
    all.removeValue(forKey: profileID)
    profileSnapshots = all
  }

  // MARK: – Persisted array of scheduled sessions
  static var completedSessionsInSchedular: [SessionSnapshot] {
    get {
      guard let data = suite.data(forKey: Key.completedScheduleSessions.rawValue) else { return [] }
      return (try? JSONDecoder().decode([SessionSnapshot].self, from: data)) ?? []
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        suite.set(data, forKey: Key.completedScheduleSessions.rawValue)
      } else {
        print("⚠️ SharedData: Failed to encode completedScheduleSessions, preserving existing data")
      }
    }
  }

  // MARK: – Persisted array of scheduled sessions
  static var activeSharedSession: SessionSnapshot? {
    get {
      guard let data = suite.data(forKey: Key.activeScheduleSession.rawValue) else { return nil }
      return (try? JSONDecoder().decode(SessionSnapshot.self, from: data)) ?? nil
    }
    set {
      if let newValue {
        if let data = try? JSONEncoder().encode(newValue) {
          suite.set(data, forKey: Key.activeScheduleSession.rawValue)
        } else {
          print("⚠️ SharedData: Failed to encode activeSharedSession, preserving existing data")
        }
      } else {
        suite.removeObject(forKey: Key.activeScheduleSession.rawValue)
      }
    }
  }

  static func createSessionForSchedular(for profileID: UUID) {
    activeSharedSession = SessionSnapshot(
      id: UUID().uuidString,
      tag: profileID.uuidString,
      blockedProfileId: profileID,
      startTime: Date(),
      forceStarted: true)
  }

  static func createActiveSharedSession(for session: SessionSnapshot) {
    activeSharedSession = session
  }

  static func getActiveSharedSession() -> SessionSnapshot? {
    activeSharedSession
  }

  static func endActiveSharedSession() {
    guard var existingScheduledSession = activeSharedSession else { return }

    existingScheduledSession.endTime = Date()
    completedSessionsInSchedular.append(existingScheduledSession)

    activeSharedSession = nil
  }

  static func flushActiveSession() {
    activeSharedSession = nil
  }

  static func getCompletedSessionsForSchedular() -> [SessionSnapshot] {
    completedSessionsInSchedular
  }

  static func flushCompletedSessionsForSchedular() {
    completedSessionsInSchedular = []
  }

  static func setBreakStartTime(date: Date) {
    activeSharedSession?.breakStartTime = date
  }

  static func setBreakEndTime(date: Date) {
    activeSharedSession?.breakEndTime = date
  }

  static func setEndTime(date: Date) {
    activeSharedSession?.endTime = date
  }
}
