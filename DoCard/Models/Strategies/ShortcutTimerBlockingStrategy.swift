import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "ShortcutTimerBlockingStrategy")

class ShortcutTimerBlockingStrategy: BlockingStrategy {
  static var id: String = "ShortcutTimerBlockingStrategy"

  var name: String = "Timer"
  var description: String = "Block for a specified duration"
  var iconType: String = "alarm.waves.left.and.right"
  var color: Color = .mint

  var hidden: Bool = true

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return ShortcutTimerBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    guard profile.strategyData != nil else {
      self.onErrorMessage?("No timer duration specified for this profile")
      return nil
    }

    // Activate restrictions before creating the session
    self.appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

    let activeSession = BlockedProfileSession.createSession(
      in: context,
      withTag: profile.blockingStrategyId ?? "ManualBlockingStrategy",
      withProfile: profile,
      forceStart: forceStart ?? true
    )

    DeviceActivityCenterUtil.startStrategyTimerActivity(for: profile)

    self.onSessionCreation?(.started(activeSession))

    return nil
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    session.endSession()
    do {
      try context.save()
    } catch {
      logger.error("Failed to save session after shortcut timer stop: \(error.localizedDescription)")
      self.onErrorMessage?("Failed to save session: \(error.localizedDescription)")
    }
    self.appBlocker.deactivateRestrictions()

    self.onSessionCreation?(.ended(session.blockedProfile))

    return nil
  }
}
