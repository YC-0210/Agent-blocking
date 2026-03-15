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

struct BlockedProfileSchedule: Codable, Equatable {
  var name: String = ""
  var days: [Weekday]

  var startHour: Int
  var startMinute: Int
  var endHour: Int
  var endMinute: Int

  var endType: ScheduleEndType = .cardTap

  var updatedAt: Date = Date()

  var isActive: Bool {
    return !days.isEmpty
  }

  var totalDurationInSeconds: Int {
    return (endHour - startHour) * 3600 + (endMinute - startMinute) * 60
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
    guard isTodayScheduled(now: now, calendar: calendar) else { return false }

    let currentComponents = calendar.dateComponents([.hour, .minute], from: now)
    let currentHour = currentComponents.hour ?? 0
    let currentMinute = currentComponents.minute ?? 0

    let currentTotalMinutes = currentHour * 60 + currentMinute
    let startTotalMinutes = startHour * 60 + startMinute
    let endTotalMinutes = endHour * 60 + endMinute

    return currentTotalMinutes >= startTotalMinutes && currentTotalMinutes < endTotalMinutes
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
