import DeviceActivity
import OSLog

private let log: Logger = Logger(subsystem: "app.docard.monitor", category: StrategyTimerActivity.id)

class StrategyTimerActivity: TimerActivity {
  static var id: String = "StrategyTimerActivity"

  private let appBlocker = AppBlockerUtil()

  func getDeviceActivityName(from profileId: String) -> DeviceActivityName {
    return DeviceActivityName(rawValue: "\(StrategyTimerActivity.id):\(profileId)")
  }

  func getAllStrategyTimerActivities(from activities: [DeviceActivityName]) -> [DeviceActivityName]
  {
    return activities.filter { $0.rawValue.starts(with: StrategyTimerActivity.id) }
  }

  func start(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString

    log.info("Start strategy timer activity for \(profileId), profile: \(profileId)")

    if let activeSession = SharedData.getActiveStrategySharedSession(),
      activeSession.blockedProfileId != profile.id
    {
      log.info(
        "Start strategy timer activity for \(profileId), active session profile does not match device activity profile, not continuing"
      )
      return
    }

    // No need to create a new active session since this is started in the app itself and session already exists
    // Start restrictions
    appBlocker.activateRestrictions(for: profile)
  }

  func stop(for profile: SharedData.ProfileSnapshot) {
    let profileId = profile.id.uuidString

    guard let activeSession = SharedData.getActiveStrategySharedSession() else {
      log.info("Stop strategy timer activity for \(profileId), no active session found")
      return
    }

    // Check to make sure the active session is the same as the profile before disabling restrictions
    if activeSession.blockedProfileId != profile.id {
      log.info(
        "Stop strategy timer activity for \(profileId), active session profile does not match device activity profile"
      )
      return
    }

    // End restrictions
    appBlocker.deactivateRestrictions()

    // End the active strategy session
    SharedData.endActiveStrategySharedSession()

    // Per-session timer expired in the background. The main app's
    // MacSessionSyncService.endSession() never fires for this path because we
    // don't go through onSessionCreation(.ended). Tell paired Mac directly so
    // it doesn't stay blocked forever. PATCH failure is queued for retry by
    // the main app on next foreground.
    MacExtensionSyncWriter.notifySessionEnded()

    if let scheduledProfile = SharedData.currentScheduledProfileSnapshot() {
      log.info(
        "Stop strategy timer activity for \(profileId), restoring active schedule for \(scheduledProfile.id.uuidString)"
      )
      SharedData.createSessionForSchedular(for: scheduledProfile.id)
      appBlocker.activateRestrictions(for: scheduledProfile)

      // Schedule resumed (e.g., card-tap window's timer expired and the
      // underlying schedule is back in effect). Mac should re-block.
      MacExtensionSyncWriter.notifySessionStarted()
    }
  }
}
