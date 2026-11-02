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
  var onCardNameScanned: ((String?) -> Void)?

  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  private var emptySelectionMessage: String {
    !Entitlements.current.canBlockCategories
      ? String(localized: "免費版目前只支援封鎖 App。請先選擇要封鎖的 App，才能開始專注")
      : String(localized: "請先選擇要封鎖的 App，才能開始專注")
  }

  func getIdentifier() -> String {
    return ShortcutTimerBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    guard SharedData.effectiveSubscriptionTier == .premium else {
      onErrorMessage?(String(localized: "An active subscription is required."))
      return nil
    }

    guard profile.strategyData != nil else {
      self.onErrorMessage?("No timer duration specified for this profile")
      return nil
    }

    if profile.hasActiveSchedules {
      self.onErrorMessage?(String(localized: "此模式已有排程，無法使用計時模式"))
      return nil
    }

    let snapshot = BlockedProfiles.getSnapshot(for: profile)
    guard self.appBlocker.wouldShieldAnything(for: snapshot) else {
      self.onErrorMessage?(emptySelectionMessage)
      return nil
    }

    let timerData = StrategyTimerData.toStrategyTimerData(from: profile.strategyData!)

    // Activate restrictions before creating the session
    self.appBlocker.activateRestrictions(for: snapshot)

    let activeSession = BlockedProfileSession.createSession(
      in: context,
      withTag: profile.blockingStrategyId ?? "ManualBlockingStrategy",
      withProfile: profile,
      forceStart: forceStart ?? true,
      plannedDurationMinutes: timerData.durationInMinutes
    )

    guard DeviceActivityCenterUtil.startStrategyTimerActivity(for: profile) else {
      context.delete(activeSession)
      SharedData.flushActiveStrategySession()
      self.appBlocker.deactivateRestrictions()
      self.onErrorMessage?(
        String(localized: "無法啟動計時器，請確認 Screen Time 權限仍可使用後再試一次")
      )
      return nil
    }

    self.onSessionCreation?(.started(activeSession))

    return nil
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    session.endSessionFully(in: context, endReason: "") { error in
      self.onErrorMessage?("Failed to save session: \(error.localizedDescription)")
    }
    self.appBlocker.deactivateRestrictions()

    self.onSessionCreation?(.ended(session.blockedProfile))

    return nil
  }
}
