//
//  DeviceActivityMonitorExtension.swift
//  DoCardDeviceMonitor
//
//  Created by Ali Waseem on 2025-05-27.
//

import DeviceActivity
import Foundation
import ManagedSettings
import OSLog

private let log = Logger(
  subsystem: "app.docard.monitor",
  category: "DeviceActivity"
)

// Optionally override any of the functions below.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class DeviceActivityMonitorExtension: DeviceActivityMonitor {
  private let appBlocker = AppBlockerUtil()

  override init() {
    super.init()
  }

  override func intervalDidStart(for activity: DeviceActivityName) {
    super.intervalDidStart(for: activity)
    if activity.rawValue.hasPrefix(AgentFocusDevice.activityPrefix) { return }
    // Subscription expiry has no effect in this standalone agent experiment.
    if activity == SubscriptionExpiry.activityName { return }

    // Distraction-usage tracking is NOT a blocking activity. Initialize today's
    // bucket and return immediately so no blocking logic ever runs for it.
    if activity.rawValue == DistractionTrackingShared.activityName {
      DistractionTrackingShared.ensureDayTracked()
      return
    }

    log.info("=== DO Card intervalDidStart FIRED — build: \(#file) ===")
    DebugLogStore.log(
      "intervalDidStart", "activity=\(activity.rawValue)", process: "ext")

    // EMERGENCY_UNLOCK_AUDIT: respect app-written suppression for the current
    // scheduled activity window so intervalDidStart cannot immediately re-block.
    if SuppressionRegistry.isSuppressed(activityId: activity.rawValue) {
      log.info("intervalDidStart suppressed for activity: \(activity.rawValue, privacy: .public)")
      return
    }

    let snapshotCount = SharedData.profileSnapshots.count
    log.info(
      "intervalDidStart for activity: \(activity.rawValue), profileSnapshots count: \(snapshotCount)"
    )

    if snapshotCount == 0 {
      log.error(
        "intervalDidStart: profileSnapshots is EMPTY — blocking will silently no-op for activity: \(activity.rawValue)"
      )
    }

    TimerActivityUtil.startTimerActivity(for: activity)
  }

  override func intervalDidEnd(for activity: DeviceActivityName) {
    super.intervalDidEnd(for: activity)
    if activity.rawValue.hasPrefix(AgentFocusDevice.activityPrefix) {
      AgentFocusDevice.intervalEnded(activity)
      return
    }
    // Subscription expiry has no effect in this standalone agent experiment.
    if activity == SubscriptionExpiry.activityName { return }

    // Distraction-usage tracking activity: no blocking teardown to do.
    if activity.rawValue == DistractionTrackingShared.activityName {
      return
    }

    let snapshotCount = SharedData.profileSnapshots.count
    log.info(
      "intervalDidEnd for activity: \(activity.rawValue), profileSnapshots count: \(snapshotCount)")
    DebugLogStore.log(
      "intervalDidEnd",
      "activity=\(activity.rawValue) snapshotCount=\(snapshotCount)",
      process: "ext")

    if snapshotCount == 0 {
      log.error(
        "intervalDidEnd: profileSnapshots is EMPTY — stop will silently no-op for activity: \(activity.rawValue)"
      )
    }

    TimerActivityUtil.stopTimerActivity(for: activity)
  }

  override func eventDidReachThreshold(
    _ event: DeviceActivityEvent.Name,
    activity: DeviceActivityName
  ) {
    super.eventDidReachThreshold(event, activity: activity)

    // Only the distraction-usage activity registers threshold events. Record the
    // day's bucket; never touch blocking state here.
    guard activity.rawValue == DistractionTrackingShared.activityName else { return }
    if let bucket = DistractionTrackingShared.bucket(forEventName: event.rawValue) {
      DistractionTrackingShared.recordBucketReached(bucket)
    }
  }
}
