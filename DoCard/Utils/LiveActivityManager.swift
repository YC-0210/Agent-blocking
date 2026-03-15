import ActivityKit
import Foundation
import OSLog
import SwiftUI

private let laLogger = Logger(subsystem: "app.docard", category: "LiveActivity")

@MainActor
class LiveActivityManager: ObservableObject {
  // Published property for live activity reference
  @Published var currentActivity: Activity<DoCardWidgetAttributes>?

  // Use AppStorage for persisting the activity ID across app launches
  @AppStorage("com.docard.currentActivityId") private var storedActivityId: String = ""

  static let shared = LiveActivityManager()

  private init() {
    // Try to restore existing activity on initialization
    restoreExistingActivity()
  }

  private var isSupported: Bool {
    if #available(iOS 16.1, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    return false
  }

  // Save activity ID using AppStorage
  private func saveActivityId(_ id: String) {
    storedActivityId = id
  }

  // Remove activity ID from AppStorage
  private func removeActivityId() {
    storedActivityId = ""
  }

  // Restore existing activity from system if available
  private func restoreExistingActivity() {
    guard isSupported else { return }

    // Check if we have a saved activity ID
    if !storedActivityId.isEmpty {
      if let existingActivity = Activity<DoCardWidgetAttributes>.activities.first(where: {
        $0.id == storedActivityId
      }) {
        // Found the existing activity
        self.currentActivity = existingActivity
        laLogger.debug("Restored existing Live Activity with ID: \(existingActivity.id, privacy: .private)")
      } else {
        // The activity no longer exists, clean up the stored ID
        laLogger.debug("No existing activity found with saved ID, removing reference")
        removeActivityId()
      }
    }
  }

  func startSessionActivity(session: BlockedProfileSession) {
    // Check if Live Activities are supported
    guard isSupported else {
      laLogger.debug("Live Activities are not supported on this device")
      return
    }

    // Check if we can restore an existing activity first
    if currentActivity == nil {
      restoreExistingActivity()
    }

    // Check if we already have an activity running
    if currentActivity != nil {
      laLogger.debug("Live Activity is already running, will update instead")
      updateSessionActivity(session: session)
      return
    }

    if session.blockedProfile.enableLiveActivity == false {
      laLogger.debug("Activity is disabled for profile")
      return
    }

    // Create and start the activity
    let profileName = session.blockedProfile.name
    let message = FocusMessages.getRandomMessage()
    let attributes = DoCardWidgetAttributes(name: profileName, message: message)
    let contentState = DoCardWidgetAttributes.ContentState(
      startTime: session.startTime,
      isBreakActive: session.isBreakActive,
      breakStartTime: session.breakStartTime,
      breakEndTime: session.breakEndTime
    )

    do {
      let activity = try Activity.request(
        attributes: attributes,
        content: .init(state: contentState, staleDate: nil)
      )
      currentActivity = activity

      saveActivityId(activity.id)
      laLogger.debug("Started Live Activity with ID: \(activity.id, privacy: .private) for profile: \(profileName, privacy: .private)")
      return
    } catch {
      laLogger.error("Error starting Live Activity: \(error.localizedDescription, privacy: .private)")
      return
    }
  }

  func updateSessionActivity(session: BlockedProfileSession) {
    guard let activity = currentActivity else {
      laLogger.debug("No Live Activity to update")
      return
    }

    let updatedState = DoCardWidgetAttributes.ContentState(
      startTime: session.startTime,
      isBreakActive: session.isBreakActive,
      breakStartTime: session.breakStartTime,
      breakEndTime: session.breakEndTime
    )

    Task {
      await activity.update(.init(state: updatedState, staleDate: nil))
      laLogger.debug("Updated Live Activity with ID: \(activity.id, privacy: .private)")
    }
  }

  func updateBreakState(session: BlockedProfileSession) {
    guard let activity = currentActivity else {
      laLogger.debug("No Live Activity to update for break state")
      return
    }

    let updatedState = DoCardWidgetAttributes.ContentState(
      startTime: session.startTime,
      isBreakActive: session.isBreakActive,
      breakStartTime: session.breakStartTime,
      breakEndTime: session.breakEndTime
    )

    Task {
      await activity.update(.init(state: updatedState, staleDate: nil))
      laLogger.debug("Updated Live Activity break state: \(session.isBreakActive, privacy: .private)")
    }
  }

  func endSessionActivity() {
    guard let activity = currentActivity else {
      laLogger.debug("No Live Activity to end")
      return
    }

    // End the activity
    let completedState = DoCardWidgetAttributes.ContentState(
      startTime: Date.now
    )

    Task {
      await activity.end(.init(state: completedState, staleDate: nil), dismissalPolicy: .immediate)
      laLogger.debug("Ended Live Activity")
    }

    // Remove the stored activity ID when ending the activity
    removeActivityId()
    currentActivity = nil
  }
}
