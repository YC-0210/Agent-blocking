import DeviceActivity
import OSLog

private let timerLog = Logger(subsystem: "app.docard.monitor", category: "TimerActivityUtil")

class TimerActivityUtil {
  static func startTimerActivity(for activity: DeviceActivityName) {
    let parts = getTimerParts(from: activity)

    guard let timerActivity = getTimerActivity(for: parts.deviceActivityId) else {
      timerLog.error("startTimerActivity: unknown deviceActivityId '\(parts.deviceActivityId)' from activity '\(activity.rawValue)' — no matching TimerActivity")
      return
    }

    guard let profile = getProfile(for: parts.profileId) else {
      timerLog.error("startTimerActivity: profile snapshot NOT FOUND for profileId '\(parts.profileId)' from activity '\(activity.rawValue)' — blocking will not activate")
      return
    }

    timerActivity.start(for: profile)
  }

  static func stopTimerActivity(for activity: DeviceActivityName) {
    let parts = getTimerParts(from: activity)

    guard let timerActivity = getTimerActivity(for: parts.deviceActivityId) else {
      timerLog.error("stopTimerActivity: unknown deviceActivityId '\(parts.deviceActivityId)' from activity '\(activity.rawValue)' — no matching TimerActivity")
      return
    }

    guard let profile = getProfile(for: parts.profileId) else {
      timerLog.error("stopTimerActivity: profile snapshot NOT FOUND for profileId '\(parts.profileId)' from activity '\(activity.rawValue)' — stop will not execute")
      DebugLogStore.log(
        "TimerActivityUtil.stopTimerActivity",
        "profileSnapshotMissing activity=\(activity.rawValue) → flush only, NO deactivate",
        process: "ext")
      if parts.deviceActivityId == ScheduleTimerActivity.id {
        SharedData.flushActiveScheduleSession()
      } else if parts.deviceActivityId == StrategyTimerActivity.id {
        SharedData.flushActiveStrategySession()
      }
      return
    }

    timerActivity.stop(for: profile)
  }

  private static func getTimerParts(from activity: DeviceActivityName) -> (
    deviceActivityId: String, profileId: String
  ) {
    let activityName = activity.rawValue
    let components = activityName.split(separator: ":")

    // For versions >= 1.24, the activity name format is "type:profileId"
    if components.count == 2 {
      return (deviceActivityId: String(components[0]), profileId: String(components[1]))
    }

    // Schedule timer activities use "profileUUID" (legacy) or "profileUUID.scheduleUUID" (new) format
    // Extract just the profileId portion for snapshot lookup
    if let dotIndex = activityName.firstIndex(of: ".") {
      let profileId = String(activityName[activityName.startIndex..<dotIndex])
      return (deviceActivityId: ScheduleTimerActivity.id, profileId: profileId)
    }

    // Legacy format: just "profileId"
    return (deviceActivityId: ScheduleTimerActivity.id, profileId: activityName)
  }

  private static func getTimerActivity(for deviceActivityId: String) -> TimerActivity? {
    switch deviceActivityId {
    case ScheduleTimerActivity.id:
      return ScheduleTimerActivity()
    case BreakTimerActivity.id:
      return BreakTimerActivity()
    case StrategyTimerActivity.id:
      return StrategyTimerActivity()
    default:
      return nil
    }
  }

  private static func getProfile(for profileId: String) -> SharedData.ProfileSnapshot? {
    return SharedData.snapshot(for: profileId)
  }
}
