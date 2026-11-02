import DeviceActivity
import Foundation
import OSLog

/// Same expiry behavior is called by the foreground app and the monitor extension.
enum SubscriptionExpiry {
  static let activityName = DeviceActivityName("subscription-expiry")
  static let endReason = "subscription_access_ended"

  @discardableResult
  static func enforce(blocker: AppBlockerUtil) -> Bool {
    guard SharedData.effectiveSubscriptionTier != .premium else { return false }
    blocker.deactivateRestrictions()
    if var session = SharedData.activeStrategySharedSession,
      session.breakStartTime != nil && session.breakEndTime == nil
    {
      session.breakEndTime = SharedData.currentDate
      SharedData.activeStrategySharedSession = session
    }
    if var session = SharedData.activeScheduleSharedSession,
      session.breakStartTime != nil && session.breakEndTime == nil
    {
      session.breakEndTime = SharedData.currentDate
      SharedData.activeScheduleSharedSession = session
    }
    SharedData.endActiveStrategySharedSession(endReason: endReason)
    SharedData.endActiveScheduleSharedSession(endReason: endReason)
    return true
  }

  /// A repeating near-full-day interval stays within Apple's 15-minute/one-week
  /// limits and does not require use during a short window just before expiry.
  /// Both daily boundaries recheck the absolute verified date, so earlier days
  /// never end a valid subscription. Explicit timezone preserves the end instant.
  static func monitorSchedule(until end: Date, calendar: Calendar) -> DeviceActivitySchedule {
    var from = calendar.dateComponents([.hour, .minute, .second], from: end.addingTimeInterval(1))
    var to = calendar.dateComponents([.hour, .minute, .second], from: end)
    from.timeZone = calendar.timeZone
    to.timeZone = calendar.timeZone
    from.calendar = calendar
    to.calendar = calendar
    return DeviceActivitySchedule(intervalStart: from, intervalEnd: to, repeats: true)
  }

  static func schedule() {
    let center = DeviceActivityCenter()
    center.stopMonitoring([activityName])
    guard let end = SharedData.subscriptionAccessEnd else { return }
    do {
      try center.startMonitoring(
        activityName,
        during: monitorSchedule(until: end, calendar: SharedData.currentCalendar))
    } catch {
      Logger(subsystem: "app.docard", category: "Subscription").error(
        "Could not register subscription expiry monitor: \(error.localizedDescription)")
    }
  }
}
