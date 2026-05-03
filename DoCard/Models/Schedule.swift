import Foundation

enum Weekday: Int, CaseIterable, Codable, Equatable {
  case sunday = 1
  case monday
  case tuesday
  case wednesday
  case thursday
  case friday
  case saturday

  var name: String {
    switch self {
    case .sunday: return "Sunday"
    case .monday: return "Monday"
    case .tuesday: return "Tuesday"
    case .wednesday: return "Wednesday"
    case .thursday: return "Thursday"
    case .friday: return "Friday"
    case .saturday: return "Saturday"
    }
  }

  var shortLabel: String {
    switch self {
    case .sunday: return "Su"
    case .monday: return "Mo"
    case .tuesday: return "Tu"
    case .wednesday: return "We"
    case .thursday: return "Th"
    case .friday: return "Fr"
    case .saturday: return "Sa"
    }
  }

  var chineseShortLabel: String {
    switch self {
    case .sunday: return String(localized: "日")
    case .monday: return String(localized: "一")
    case .tuesday: return String(localized: "二")
    case .wednesday: return String(localized: "三")
    case .thursday: return String(localized: "四")
    case .friday: return String(localized: "五")
    case .saturday: return String(localized: "六")
    }
  }
}

enum ScheduleEndType: String, Codable, Equatable {
  case cardTap = "cardTap"
  case specificTime = "specificTime"
}

struct BlockedProfileSchedule: Codable, Equatable, Identifiable {
  var id: UUID = UUID()
  var name: String = ""
  var days: [Weekday]

  var startHour: Int
  var startMinute: Int
  var endHour: Int
  var endMinute: Int

  var endType: ScheduleEndType = .specificTime
  var isNextDay: Bool = false

  var updatedAt: Date = Date()

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case days
    case startHour
    case startMinute
    case endHour
    case endMinute
    case endType
    case isNextDay
    case updatedAt
  }

  init(
    id: UUID = UUID(),
    name: String = "",
    days: [Weekday],
    startHour: Int,
    startMinute: Int,
    endHour: Int,
    endMinute: Int,
    endType: ScheduleEndType = .specificTime,
    isNextDay: Bool = false,
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.name = name
    self.days = days
    self.startHour = startHour
    self.startMinute = startMinute
    self.endHour = endHour
    self.endMinute = endMinute
    self.endType = endType
    self.isNextDay = isNextDay
    self.updatedAt = updatedAt
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
    days = try container.decode([Weekday].self, forKey: .days)
    startHour = try container.decode(Int.self, forKey: .startHour)
    startMinute = try container.decode(Int.self, forKey: .startMinute)
    endHour = try container.decode(Int.self, forKey: .endHour)
    endMinute = try container.decode(Int.self, forKey: .endMinute)
    endType =
      try container.decodeIfPresent(ScheduleEndType.self, forKey: .endType)
      ?? .specificTime
    isNextDay = try container.decodeIfPresent(Bool.self, forKey: .isNextDay) ?? false
    updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
  }

  var isActive: Bool {
    return !days.isEmpty
  }

  var totalDurationInSeconds: Int {
    if isNextDay {
      return (24 - startHour + endHour) * 3600 + (endMinute - startMinute) * 60
    } else {
      return (endHour - startHour) * 3600 + (endMinute - startMinute) * 60
    }
  }

  var summaryText: String {
    guard isActive else { return "No Schedule Set" }

    let daysSummary =
      days
      .sorted { $0.rawValue < $1.rawValue }
      .map { $0.shortLabel }
      .joined(separator: " ")

    let start = formattedTimeString(hour24: startHour, minute: startMinute)
    let end = formattedTimeString(hour24: endHour, minute: endMinute)

    return "\(daysSummary) · \(start) - \(end)"
  }

  func isTodayScheduled(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    guard isActive else { return false }
    let currentWeekdayRaw = calendar.component(.weekday, from: now)
    guard let today = Weekday(rawValue: currentWeekdayRaw) else { return false }
    return days.contains(today)
  }

  func isCurrentlyInWindow(now: Date = Date(), calendar: Calendar = .current) -> Bool {
    let currentComponents = calendar.dateComponents([.hour, .minute], from: now)
    let currentHour = currentComponents.hour ?? 0
    let currentMinute = currentComponents.minute ?? 0
    let currentTotalMinutes = currentHour * 60 + currentMinute
    let startTotalMinutes = startHour * 60 + startMinute
    let endTotalMinutes = endHour * 60 + endMinute

    if isNextDay {
      // Cross-midnight schedule: check two cases.
      // A) Today is the start day and current time >= startTime (e.g. Mon 22:00–23:59)
      // B) Yesterday was the start day and current time < endTime (e.g. Tue 00:00–06:00)
      let todayWeekday = calendar.component(.weekday, from: now)
      let yesterdayWeekday = todayWeekday == 1 ? 7 : todayWeekday - 1
      let todayIsStartDay = days.contains(where: { $0.rawValue == todayWeekday })
      let yesterdayWasStartDay = days.contains(where: { $0.rawValue == yesterdayWeekday })
      if todayIsStartDay && currentTotalMinutes >= startTotalMinutes {
        return true
      }
      if yesterdayWasStartDay && currentTotalMinutes < endTotalMinutes {
        return true
      }
      return false
    } else {
      guard isTodayScheduled(now: now, calendar: calendar) else { return false }
      return currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes
    }
  }

  func olderThan15Minutes(now: Date = Date()) -> Bool {
    return now.timeIntervalSince(updatedAt) > 15 * 60
  }

  private func formattedTimeString(hour24: Int, minute: Int) -> String {
    var hour = hour24 % 12
    if hour == 0 { hour = 12 }
    let isPM = hour24 >= 12
    return "\(hour):\(String(format: "%02d", minute)) \(isPM ? "PM" : "AM")"
  }
}
