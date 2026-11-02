import Foundation

struct Upgrade1301Spec: Decodable {
  struct Schedule: Decodable {
    let name: String
    let days: [Int]
    let startHour: Int
    let startMinute: Int
    let endHour: Int
    let endMinute: Int
    let endType: String
    let updatedAt: String
  }

  struct Profile: Decodable {
    let id: UUID
    let name: String
    let order: Int
    let createdAt: String
    let updatedAt: String
    let strategy: String
    let timerJSON: String?
    let enableLiveActivity: Bool
    let reminderTimeInSeconds: UInt32?
    let enableBreaks: Bool
    let breakTimeInMinutes: Int
    let enableAllowMode: Bool
    let enableAllowModeDomains: Bool
    let enableSafariBlocking: Bool
    let cardIds: [String]?
    let domains: [String]?
    let customReminderMessage: String?
    let schedule: Schedule
  }

  struct Session: Decodable {
    let id: String
    let profileId: UUID
    let tag: String
    let startTime: String
    let endTime: String
    let breakStartTime: String?
    let breakEndTime: String?
    let forceStarted: Bool
  }

  let sourceVersion: String
  let sourceBuild: String
  let profiles: [Profile]
  let sessions: [Session]

  static func date(_ text: String) throws -> Date {
    guard let date = ISO8601DateFormatter().date(from: text) else {
      throw CocoaError(
        .coderReadCorrupt, userInfo: [NSLocalizedDescriptionKey: "Invalid fixture date: \(text)"])
    }
    return date
  }
}
