import DeviceActivity
import OSLog

private let log: Logger = Logger(subsystem: "app.docard.monitor", category: ScheduleTimerActivity.id)

class ScheduleTimerActivity: TimerActivity {
  static var id: String = "ScheduleTimerActivity"

  private let appBlocker = AppBlockerUtil()

  func getDeviceActivityName(from profileId: String) -> DeviceActivityName {
    // Legacy format for backward compatibility (satisfies TimerActivity protocol)
    return DeviceActivityName(rawValue: profileId)
  }

  func getDeviceActivityName(from profileId: String, scheduleId: String) -> DeviceActivityName {
    return DeviceActivityName(rawValue: "\(profileId).\(scheduleId)")
  }

  func getDeviceActivityName(from profileId: String, scheduleId: String, weekday: Weekday)
    -> DeviceActivityName
  {
    return DeviceActivityName(rawValue: "\(profileId).\(scheduleId)_\(weekday.rawValue)")
  }

  /// Extracts the profileId from a schedule activity name (handles both legacy and new formats).
  func extractProfileId(from activity: DeviceActivityName) -> String? {
    let rawValue = activity.rawValue
    // New format: "profileId.scheduleId"
    if let dotIndex = rawValue.firstIndex(of: ".") {
      let profilePart = String(rawValue[rawValue.startIndex..<dotIndex])
      return UUID(uuidString: profilePart) != nil ? profilePart : nil
    }
    // Legacy format: just "profileId"
    return UUID(uuidString: rawValue) != nil ? rawValue : nil
  }

  func getAllScheduleTimerActivities(from activities: [DeviceActivityName]) -> [DeviceActivityName]
  {
    // Schedule timer activities use:
    //   "profileUUID"                      (legacy)
    //   "profileUUID.scheduleUUID"          (pre-weekday)
    //   "profileUUID.scheduleUUID_weekday"  (per-day, current)
    // Other activities use prefixes like "BreakScheduleActivity:" or "StrategyTimerActivity:"
    return activities.filter { activity in
      let rawValue = activity.rawValue
      // If it contains ":", it's a prefixed activity (break or strategy timer), not a schedule
      guard !rawValue.contains(":") else { return false }
      if let dotIndex = rawValue.firstIndex(of: ".") {
        let profilePart = String(rawValue[rawValue.startIndex..<dotIndex])
        let remainder = String(rawValue[rawValue.index(after: dotIndex)...])
        guard UUID(uuidString: profilePart) != nil else { return false }
        // Per-day format: scheduleUUID_weekdayRaw
        if let underscoreIndex = remainder.lastIndex(of: "_") {
          let schedPart = String(remainder[remainder.startIndex..<underscoreIndex])
          let weekdayPart = String(remainder[remainder.index(after: underscoreIndex)...])
          if UUID(uuidString: schedPart) != nil,
            let weekdayRaw = Int(weekdayPart),
            (1...7).contains(weekdayRaw)
          {
            return true
          }
        }
        // Legacy per-schedule format: just scheduleUUID (no weekday)
        return UUID(uuidString: remainder) != nil
      }
      // Legacy format: just profileUUID
      return UUID(uuidString: rawValue) != nil
    }
  }

  func getAllScheduleTimerActivitiesForProfile(
    profileId: String, from activities: [DeviceActivityName]
  ) -> [DeviceActivityName] {
    return getAllScheduleTimerActivities(from: activities).filter { activity in
      extractProfileId(from: activity) == profileId
    }
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString

    guard SharedData.isScheduleCurrentlyActiveAndUnsuppressed(profile: profile) else {
      log.info(
        "Start schedule timer activity for \(profileId), no unsuppressed schedule currently in window"
      )
      return
    }

    log.info("Start schedule timer activity for \(profileId), profile: \(profileId)")

    if let activeStrategySession = SharedData.getActiveStrategySharedSession() {
      log.info(
        "Start schedule timer activity for \(profileId), strategy session '\(activeStrategySession.id, privacy: .private)' is active — preserving current timer/manual ownership"
      )
      return
    }

    if let existingSession = SharedData.getActiveScheduleSharedSession() {
      if existingSession.blockedProfileId == profile.id {
        log.info(
          "Start schedule timer activity for \(profileId), existing session profile matches device activity profile, continuing active session"
        )
        appBlocker.activateRestrictions(for: profile)
        return
      } else {
        log.info(
          "Start schedule timer activity for \(profileId), existing session profile does not match device activity profile, ending active session"
        )
        SharedData.endActiveScheduleSharedSession()
      }
    }

    // Create a new active scheduled session for the profile
    SharedData.createSessionForSchedular(for: profile.id)

    // Start restrictions
    let appCount = profile.selectedActivity.applicationTokens.count
    let catCount = profile.selectedActivity.categoryTokens.count
    log.info("Activating restrictions for scheduled profile '\(profileId)' — appTokens: \(appCount), categoryTokens: \(catCount), tier: \(SharedData.effectiveSubscriptionTier.rawValue)")
    appBlocker.activateRestrictions(for: profile)

    // Notify any paired Mac (Chrome Extension) — best-effort. Schedule firings
    // happen in the DeviceActivityMonitor extension, so we can't reach the
    // main app's MacSessionSyncService singleton from here. The writer reads
    // iphone_token from the App Group and POSTs synchronously within the
    // extension's runtime budget.
    MacExtensionSyncWriter.notifySessionStarted()
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString

    guard let activeSession = SharedData.getActiveScheduleSharedSession() else {
      log.info("Stop schedule timer activity for \(profileId), no active session found")
      return
    }

    // Check to make sure the active session is the same as the profile before disabling restrictions
    if activeSession.blockedProfileId != profile.id {
      log.info(
        "Stop schedule timer activity for \(profileId), active session profile does not match device activity profile"
      )
      return
    }

    // End restrictions
    appBlocker.deactivateRestrictions()
    DebugLogStore.log(
      "ScheduleTimerActivity.stop",
      "deactivated + endActiveScheduleSharedSession profile=\(profileId) sessionId=\(activeSession.id)",
      process: "ext")

    // End the active scheduled session
    SharedData.endActiveScheduleSharedSession()

    // Tell paired Mac the scheduled session ended. PATCH failures get queued
    // in the App Group retry queue so the main app's MacSessionSyncService
    // can resend on next foreground — without this, listening Chromes would
    // stay blocked indefinitely after a network blip at schedule end.
    MacExtensionSyncWriter.notifySessionEnded()
  }

  func getScheduleInterval(from schedule: BlockedProfileSchedule, weekday: Weekday) -> (
    intervalStart: DateComponents, intervalEnd: DateComponents
  ) {
    let isCrossMidnight = schedule.isNextDay
    // For cross-midnight windows (e.g. 22:00 Mon → 02:00 Tue), intervalEnd must land on the
    // following calendar day — otherwise the system sees end < start on the same weekday and
    // silently drops the schedule. Weekday wraps Saturday(7) → Sunday(1).
    let endWeekday = isCrossMidnight ? (weekday.rawValue % 7) + 1 : weekday.rawValue

    // .second is explicit to remove sub-minute ambiguity at the interval boundary —
    // without it, iOS sometimes fails to fire intervalDidEnd for same-day weekday
    // schedules with repeats: true. Same fix v2.0.4 applied to the strategy/break
    // timer path in DeviceActivityCenterUtil.getTimeIntervalStartAndEnd.
    var intervalStart = DateComponents(
      hour: schedule.startHour, minute: schedule.startMinute, second: 0)
    intervalStart.weekday = weekday.rawValue
    intervalStart.timeZone = .current
    var intervalEnd = DateComponents(
      hour: schedule.endHour, minute: schedule.endMinute, second: 0)
    intervalEnd.weekday = endWeekday
    intervalEnd.timeZone = .current
    return (intervalStart: intervalStart, intervalEnd: intervalEnd)
  }
}
