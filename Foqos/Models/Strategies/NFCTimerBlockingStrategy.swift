import SwiftData
import SwiftUI

class NFCTimerBlockingStrategy: BlockingStrategy {
  static var id: String = "NFCTimerBlockingStrategy"

  var name: String = String(localized: "Timed Lock with Early Unlock")
  var description: String = String(localized: "Set a timer duration, unlock early by tapping DO Card or wait for timer to expire")
  var iconType: String = "alarm.waves.left.and.right"
  var color: Color = Color(red: 1.0, green: 0.42, blue: 0.21)

  var hidden: Bool = false

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return NFCTimerBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    return TimerDurationView(
      profileName: profile.name,
      onDurationSelected: { [weak self] duration in
        guard let self else { return }
        if let strategyTimerData = StrategyTimerData.toData(from: duration) {
          // Store the timer data so that its selected for the next time the profile is started
          // This is also useful if the profile is started from the background like a shortcut or intent
          profile.strategyData = strategyTimerData
          profile.updatedAt = Date()
          BlockedProfiles.updateSnapshot(for: profile)
          try? context.save()
        }

        // Activate restrictions to actually block the apps
        self.appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

        let activeSession = BlockedProfileSession.createSession(
          in: context,
          withTag: NFCTimerBlockingStrategy.id,
          withProfile: profile,
          forceStart: forceStart ?? false
        )

        DeviceActivityCenterUtil.startStrategyTimerActivity(for: profile)

        self.onSessionCreation?(.started(activeSession))
      }
    )
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    nfcScanner.onTagScanned = { [weak self] tag in
      guard let self else { return }
      let tag = tag.url ?? tag.id

      if let physicalUnblockNFCTagId = session.blockedProfile.physicalUnblockNFCTagId,
        physicalUnblockNFCTagId != tag
      {
        self.onErrorMessage?(
          String(localized: "This NFC tag is not allowed to unblock this profile. Physical unblock setting is on for this profile")
        )
        return
      }

      session.endSession()
      try? context.save()
      self.appBlocker.deactivateRestrictions()

      self.onSessionCreation?(.ended(session.blockedProfile))
    }

    nfcScanner.scan(profileName: session.blockedProfile.name)

    return nil
  }
}
