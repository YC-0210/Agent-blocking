import Foundation

/// Pure retention arithmetic. The caller supplies a confirmed successful cohort start.
enum RetentionTimeCalculator {
  static let daysPerPeriod = 3
  static let qualifyingLockedSeconds: TimeInterval = 7200

  enum CalculationError: Error, Equatable {
    case invalidTimeZone
    case invalidDate
    case invalidSession(id: String)
    case invalidBreak(id: String)
    case conflictingSession(id: String)
  }

  struct Cohort: Equatable {
    let startedAt: Date
    let timeZoneID: String

    init(startedAt: Date, timeZoneID: String) throws {
      guard TimeZone(identifier: timeZoneID) != nil else {
        throw CalculationError.invalidTimeZone
      }
      guard startedAt.timeIntervalSince1970.isFinite else {
        throw CalculationError.invalidDate
      }
      self.startedAt = startedAt
      self.timeZoneID = timeZoneID
    }

    fileprivate var calendar: Calendar {
      var calendar = Calendar(identifier: .gregorian)
      calendar.timeZone = TimeZone(identifier: timeZoneID)!
      return calendar
    }
  }

  struct Session: Equatable {
    let id: String
    let startTime: Date
    let endTime: Date?
    var breakStartTime: Date? = nil
    var breakEndTime: Date? = nil
  }

  struct Contribution: Equatable {
    let sessionID: String
    let localDate: String
    let dayOffset: Int
    let periodIndex: Int
    let lockedSeconds: TimeInterval

    var key: String { "\(sessionID):\(localDate)" }
  }

  struct Period: Equatable {
    let index: Int
    let startTime: Date
    let endTime: Date
    let lockedSeconds: TimeInterval
    let isComplete: Bool

    /// Incomplete periods are pending even if they have already reached the threshold.
    var isActive: Bool? {
      isComplete ? lockedSeconds >= qualifyingLockedSeconds : nil
    }
  }

  static func periods(
    for sessions: [Session], cohort: Cohort, asOf: Date
  ) throws -> [Period] {
    guard asOf.timeIntervalSince1970.isFinite else { throw CalculationError.invalidDate }
    let calendar = cohort.calendar
    let anchor = calendar.startOfDay(for: cohort.startedAt)
    guard asOf >= cohort.startedAt else { return [] }
    guard
      let elapsedDays = calendar.dateComponents(
        [.day], from: anchor, to: calendar.startOfDay(for: asOf)
      ).day
    else { throw CalculationError.invalidDate }
    var totals: [Int: TimeInterval] = [:]
    var uniqueSessions: [String: Session] = [:]
    for session in sessions {
      if let existing = uniqueSessions[session.id], existing != session {
        throw CalculationError.conflictingSession(id: session.id)
      }
      uniqueSessions[session.id] = session
    }
    for id in uniqueSessions.keys.sorted() {
      guard let session = uniqueSessions[id] else { continue }
      for contribution in try contributions(for: session, cohort: cohort, asOf: asOf) {
        totals[contribution.periodIndex, default: 0] += contribution.lockedSeconds
      }
    }
    return try (1...(elapsedDays / daysPerPeriod + 1)).map { index in
      guard
        let start = calendar.date(byAdding: .day, value: (index - 1) * daysPerPeriod, to: anchor),
        let end = calendar.date(byAdding: .day, value: daysPerPeriod, to: start)
      else { throw CalculationError.invalidDate }
      return Period(
        index: index, startTime: start, endTime: end, lockedSeconds: totals[index, default: 0],
        isComplete: end <= asOf)
    }
  }

  static func contributions(
    for session: Session, cohort: Cohort, asOf: Date
  ) throws -> [Contribution] {
    guard asOf.timeIntervalSince1970.isFinite else { throw CalculationError.invalidDate }
    let dates = [session.startTime, session.endTime, session.breakStartTime, session.breakEndTime]
    guard !session.id.isEmpty,
      dates.compactMap({ $0 }).allSatisfy({ $0.timeIntervalSince1970.isFinite })
    else { throw CalculationError.invalidSession(id: session.id) }
    if let end = session.endTime, end < session.startTime {
      throw CalculationError.invalidSession(id: session.id)
    }
    if let breakEnd = session.breakEndTime {
      guard let breakStart = session.breakStartTime, breakEnd >= breakStart else {
        throw CalculationError.invalidBreak(id: session.id)
      }
    }
    guard let end = session.endTime, end <= asOf, session.startTime >= cohort.startedAt,
      end > session.startTime
    else { return [] }
    let calendar = cohort.calendar
    let anchor = calendar.startOfDay(for: cohort.startedAt)
    var cursor = session.startTime
    var result: [Contribution] = []
    while cursor < end {
      guard let day = calendar.dateInterval(of: .day, for: cursor), day.end > cursor,
        let offset = calendar.dateComponents([.day], from: anchor, to: day.start).day
      else { throw CalculationError.invalidDate }
      let segmentEnd = min(end, day.end)
      var lockedSeconds = segmentEnd.timeIntervalSince(cursor)
      if let breakStart = session.breakStartTime {
        let breakEnd = session.breakEndTime ?? end
        lockedSeconds -= max(
          0, min(segmentEnd, breakEnd).timeIntervalSince(max(cursor, breakStart)))
      }
      let parts = calendar.dateComponents([.year, .month, .day], from: cursor)
      let localDate = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
      if lockedSeconds > 0 {
        result.append(
          Contribution(
            sessionID: session.id, localDate: localDate, dayOffset: offset,
            periodIndex: offset / daysPerPeriod + 1, lockedSeconds: lockedSeconds))
      }
      cursor = segmentEnd
    }
    return result
  }
}
