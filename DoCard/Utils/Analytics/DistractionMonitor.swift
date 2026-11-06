import DeviceActivity
import FamilyControls
import Foundation
import OSLog

private let dmLog = Logger(subsystem: "online.do.card.app", category: "DistractionMonitor")

/// Starts/stops the daily DeviceActivity threshold monitoring used to estimate
/// how long the user spends on their self-selected distracting apps.
///
/// Uses a single daily-repeating activity with a ladder of usage-threshold
/// events. When a threshold is crossed, the DeviceActivityMonitor extension's
/// `eventDidReachThreshold` records the day's bucket. No raw minutes are ever
/// read by the app — only the coarse bucket leaves the extension.
enum DistractionMonitor {

  private static var activityName: DeviceActivityName {
    DeviceActivityName(DistractionTrackingShared.activityName)
  }

  /// Brings monitoring in sync with the current configuration. Safe to call on
  /// every launch and after the user changes the setting.
  static func reconcile() {
    if DistractionTracking.isConfigured {
      // Already monitoring → do nothing. Restarting (stop+start) would reset the
      // day's accumulated threshold progress, undercounting the usage bucket.
      // Monitoring persists across launches/reboots, so re-asserting it here is
      // only needed when it isn't already running. A genuine selection change
      // calls start() directly, which does the intended stop+restart.
      if DeviceActivityCenter().activities.contains(activityName) { return }
      start()
    } else {
      stop()
    }
  }

  static func start() {
    guard DistractionTracking.isConfigured else {
      stop()
      return
    }
    guard AuthorizationCenter.shared.authorizationStatus.grantsScreenTimeAccess else {
      dmLog.error("DistractionMonitor.start: Family Controls not approved — skipping")
      return
    }

    let selection = DistractionTracking.selection
    let schedule = DeviceActivitySchedule(
      intervalStart: DateComponents(hour: 0, minute: 0),
      intervalEnd: DateComponents(hour: 23, minute: 59),
      repeats: true
    )

    var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
    for threshold in DistractionTrackingShared.thresholds {
      events[DeviceActivityEvent.Name(threshold.eventName)] = DeviceActivityEvent(
        applications: selection.applicationTokens,
        categories: selection.categoryTokens,
        webDomains: selection.webDomainTokens,
        threshold: DateComponents(minute: threshold.minutes)
      )
    }

    let center = DeviceActivityCenter()
    center.stopMonitoring([activityName])
    do {
      try center.startMonitoring(activityName, during: schedule, events: events)
      DistractionTrackingShared.pruneOldDays()
      dmLog.info("DistractionMonitor started with \(events.count) threshold events")
    } catch {
      dmLog.error("DistractionMonitor.start failed: \(error.localizedDescription)")
    }
  }

  static func stop() {
    DeviceActivityCenter().stopMonitoring([activityName])
  }
}
