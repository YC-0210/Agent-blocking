import DeviceActivity
import FamilyControls
import ManagedSettings
import OSLog
import SwiftUI

private let dacLog = Logger(subsystem: "app.docard", category: "DeviceActivityCenterUtil")

class DeviceActivityCenterUtil {

  /// Checks Family Controls authorization before starting monitoring.
  /// Returns false and logs an error if not authorized.
  private static func requireAuthorization(context: String) -> Bool {
    guard AuthorizationCenter.shared.authorizationStatus.grantsScreenTimeAccess else {
      dacLog.error("\(context): Family Controls authorization is NOT approved (status: \(String(describing: AuthorizationCenter.shared.authorizationStatus))) — startMonitoring will not be called")
      return false
    }
    return true
  }

  static func scheduleTimerActivities(for profile: BlockedProfiles) throws {
    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()

    // Remove all existing schedule activities for this profile first
    let existingActivities = scheduleTimerActivity.getAllScheduleTimerActivitiesForProfile(
      profileId: profile.id.uuidString, from: center.activities)
    stopActivities(for: existingActivities, with: center)

    let activeSchedules = profile.schedules.filter { $0.isActive }
    guard !activeSchedules.isEmpty else { return }

    guard requireAuthorization(context: "scheduleTimerActivities for '\(profile.id.uuidString)'") else {
      return
    }

    for schedule in activeSchedules {
      for weekday in schedule.days {
        let deviceActivityName = scheduleTimerActivity.getDeviceActivityName(
          from: profile.id.uuidString, scheduleId: schedule.id.uuidString, weekday: weekday)

        let (intervalStart, intervalEnd) = scheduleTimerActivity.getScheduleInterval(
          from: schedule, weekday: weekday)
        let deviceActivitySchedule = DeviceActivitySchedule(
          intervalStart: intervalStart,
          intervalEnd: intervalEnd,
          repeats: true
        )

        do {
          try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
          dacLog.info("Scheduled restrictions for '\(profile.id.uuidString)' schedule '\(schedule.id.uuidString)' weekday \(weekday.rawValue) — intervalStart: \(intervalStart.hour ?? -1):\(intervalStart.minute ?? -1), intervalEnd: \(intervalEnd.hour ?? -1):\(intervalEnd.minute ?? -1), repeats: true")
        } catch {
          dacLog.error("Failed to startMonitoring for schedule '\(schedule.id.uuidString)' weekday \(weekday.rawValue): \(error.localizedDescription)")
          throw error
        }
      }
    }
  }

  static func scheduleTimerActivity(for profile: BlockedProfiles, schedule: BlockedProfileSchedule) throws {
    guard schedule.isActive else { return }

    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()

    guard requireAuthorization(context: "scheduleTimerActivity for '\(profile.id.uuidString)' schedule '\(schedule.id.uuidString)'") else {
      return
    }

    // Cancel all existing per-day activities for this schedule, plus the legacy non-per-day name.
    var namesToStop: [DeviceActivityName] = Weekday.allCases.map {
      scheduleTimerActivity.getDeviceActivityName(
        from: profile.id.uuidString, scheduleId: schedule.id.uuidString, weekday: $0)
    }
    namesToStop.append(scheduleTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString, scheduleId: schedule.id.uuidString))
    stopActivities(for: namesToStop, with: center)

    for weekday in schedule.days {
      let deviceActivityName = scheduleTimerActivity.getDeviceActivityName(
        from: profile.id.uuidString, scheduleId: schedule.id.uuidString, weekday: weekday)

      let (intervalStart, intervalEnd) = scheduleTimerActivity.getScheduleInterval(
        from: schedule, weekday: weekday)
      let deviceActivitySchedule = DeviceActivitySchedule(
        intervalStart: intervalStart,
        intervalEnd: intervalEnd,
        repeats: true
      )

      do {
        try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
        dacLog.info("Scheduled restrictions for '\(profile.id.uuidString)' schedule '\(schedule.id.uuidString)' weekday \(weekday.rawValue) — intervalStart: \(intervalStart.hour ?? -1):\(intervalStart.minute ?? -1), intervalEnd: \(intervalEnd.hour ?? -1):\(intervalEnd.minute ?? -1), repeats: true")
      } catch {
        dacLog.error("Failed to startMonitoring for schedule '\(schedule.id.uuidString)' weekday \(weekday.rawValue): \(error.localizedDescription)")
        throw error
      }
    }
  }

  static func startBreakTimerActivity(for profile: BlockedProfiles) {
    guard requireAuthorization(context: "startBreakTimerActivity for '\(profile.id.uuidString)'") else {
      return
    }

    let center = DeviceActivityCenter()
    let breakTimerActivity = BreakTimerActivity()
    let deviceActivityName = breakTimerActivity.getDeviceActivityName(from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(
      from: profile.breakTimeInMinutes)
    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    do {
      // Remove any existing schedule and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      dacLog.info("Scheduled break timer for '\(profile.id.uuidString)' — intervalStart: \(intervalStart.hour ?? -1):\(intervalStart.minute ?? -1), intervalEnd: \(intervalEnd.hour ?? -1):\(intervalEnd.minute ?? -1), repeats: false")
    } catch {
      dacLog.error("Failed to startMonitoring for break timer '\(profile.id.uuidString)': \(error.localizedDescription)")
    }
  }

  static func startStrategyTimerActivity(for profile: BlockedProfiles) -> Bool {
    guard let strategyData = profile.strategyData else {
      dacLog.warning("No strategy data found for profile: \(profile.id.uuidString)")
      return false
    }
    let timerData = StrategyTimerData.toStrategyTimerData(from: strategyData)

    guard requireAuthorization(context: "startStrategyTimerActivity for '\(profile.id.uuidString)'") else {
      return false
    }

    let center = DeviceActivityCenter()
    let strategyTimerActivity = StrategyTimerActivity()
    let deviceActivityName = strategyTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString)

    let (intervalStart, intervalEnd) = getTimeIntervalStartAndEnd(
      from: timerData.durationInMinutes)

    let deviceActivitySchedule = DeviceActivitySchedule(
      intervalStart: intervalStart,
      intervalEnd: intervalEnd,
      repeats: false,
    )

    do {
      // Remove any existing activity and create a new one
      stopActivities(for: [deviceActivityName], with: center)
      try center.startMonitoring(deviceActivityName, during: deviceActivitySchedule)
      dacLog.info("Scheduled strategy timer for '\(profile.id.uuidString)' — intervalStart: \(intervalStart.hour ?? -1):\(intervalStart.minute ?? -1), intervalEnd: \(intervalEnd.hour ?? -1):\(intervalEnd.minute ?? -1), repeats: false")
      return true
    } catch {
      dacLog.error("Failed to startMonitoring for strategy timer '\(profile.id.uuidString)': \(error.localizedDescription)")
      return false
    }
  }

  static func removeScheduleTimerActivities(for profile: BlockedProfiles) {
    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()
    let activities = scheduleTimerActivity.getAllScheduleTimerActivitiesForProfile(
      profileId: profile.id.uuidString, from: center.activities)
    stopActivities(for: activities, with: center)
  }

  static func removeScheduleTimerActivity(for profile: BlockedProfiles, scheduleId: UUID) {
    let scheduleTimerActivity = ScheduleTimerActivity()
    // Cancel per-day activities for every possible weekday, plus the legacy non-per-day name.
    var names: [DeviceActivityName] = Weekday.allCases.map {
      scheduleTimerActivity.getDeviceActivityName(
        from: profile.id.uuidString, scheduleId: scheduleId.uuidString, weekday: $0)
    }
    names.append(scheduleTimerActivity.getDeviceActivityName(
      from: profile.id.uuidString, scheduleId: scheduleId.uuidString))
    stopActivities(for: names)
  }

  static func removeScheduleTimerActivities(for activity: DeviceActivityName) {
    stopActivities(for: [activity])
  }

  static func removeAllBreakTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let breakTimerActivity = BreakTimerActivity()
    let breakTimerActivities = breakTimerActivity.getAllBreakTimerActivities(from: activities)
    stopActivities(for: breakTimerActivities, with: center)
  }

  static func removeBreakTimerActivity(for profile: BlockedProfiles) {
    let breakTimerActivity = BreakTimerActivity()
    let deviceActivityName = breakTimerActivity.getDeviceActivityName(from: profile.id.uuidString)
    stopActivities(for: [deviceActivityName])
  }

  static func removeAllStrategyTimerActivities() {
    let center = DeviceActivityCenter()
    let activities = center.activities
    let strategyTimerActivity = StrategyTimerActivity()
    let strategyTimerActivities = strategyTimerActivity.getAllStrategyTimerActivities(
      from: activities)
    stopActivities(for: strategyTimerActivities, with: center)
  }

  static func getActiveScheduleTimerActivities(for profile: BlockedProfiles) -> [DeviceActivityName] {
    let center = DeviceActivityCenter()
    let scheduleTimerActivity = ScheduleTimerActivity()
    return scheduleTimerActivity.getAllScheduleTimerActivitiesForProfile(
      profileId: profile.id.uuidString, from: center.activities)
  }

  static func getDeviceActivities() -> [DeviceActivityName] {
    let center = DeviceActivityCenter()
    return center.activities
  }

  private static func stopActivities(
    for activities: [DeviceActivityName], with center: DeviceActivityCenter? = nil
  ) {
    let center = center ?? DeviceActivityCenter()

    if activities.isEmpty {
      return
    }

    center.stopMonitoring(activities)
  }

  private static func getTimeIntervalStartAndEnd(from minutes: Int) -> (
    intervalStart: DateComponents, intervalEnd: DateComponents
  ) {
    let now = Date()
    let calendar = Calendar.current
    let endDate = calendar.date(byAdding: .minute, value: minutes, to: now) ?? now

    // Use absolute date components so non-repeating timers can cross midnight
    // without truncating to 23:59.
    var intervalStart = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: now
    )
    intervalStart.timeZone = .current

    var intervalEnd = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second],
      from: endDate
    )
    intervalEnd.timeZone = .current
    return (intervalStart: intervalStart, intervalEnd: intervalEnd)
  }
}
