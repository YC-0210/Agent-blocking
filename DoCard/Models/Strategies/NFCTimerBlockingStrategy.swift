import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "NFCTimerBlockingStrategy")

class NFCTimerBlockingStrategy: BlockingStrategy {
  static var id: String = "NFCTimerBlockingStrategy"

  var name: String = String(localized: "Timed Lock with Early Unlock")
  var description: String = String(localized: "Set a timer duration, tap your DO Card to unlock early or wait for timer to expire")
  var iconType: String = "alarm.waves.left.and.right"
  var color: Color = Color(red: 1.0, green: 0.42, blue: 0.21)

  var hidden: Bool = false

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?
  var onCardNameScanned: ((String?) -> Void)?

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  private var emptySelectionMessage: String {
    SharedData.effectiveSubscriptionTier == .free
      ? String(localized: "免費版目前只支援封鎖 App。請先選擇要封鎖的 App，才能開始專注")
      : String(localized: "請先選擇要封鎖的 App，才能開始專注")
  }

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

        if profile.hasActiveSchedules {
          self.onErrorMessage?(
            String(localized: "此模式已有排程，無法使用計時模式")
          )
          return
        }

        if let strategyTimerData = StrategyTimerData.toData(from: duration) {
          // Store the timer data so that its selected for the next time the profile is started
          // This is also useful if the profile is started from the background like a shortcut or intent
          profile.strategyData = strategyTimerData
          profile.updatedAt = Date()
          BlockedProfiles.updateSnapshot(for: profile)
          do {
            try context.save()
          } catch {
            logger.error("Failed to save strategy timer data: \(error.localizedDescription)")
            self.onErrorMessage?("Failed to save session: \(error.localizedDescription)")
          }
        }

        let snapshot = BlockedProfiles.getSnapshot(for: profile)
        guard self.appBlocker.wouldShieldAnything(for: snapshot) else {
          self.onErrorMessage?(self.emptySelectionMessage)
          return
        }

        // Start blocking directly without requiring NFC tap
        self.appBlocker.activateRestrictions(for: snapshot)

        let activeSession = BlockedProfileSession.createSession(
          in: context,
          withTag: NFCTimerBlockingStrategy.id,
          withProfile: profile,
          forceStart: forceStart ?? false,
          plannedDurationMinutes: duration.durationInMinutes
        )

        guard DeviceActivityCenterUtil.startStrategyTimerActivity(for: profile) else {
          context.delete(activeSession)
          SharedData.flushActiveStrategySession()
          self.appBlocker.deactivateRestrictions()
          self.onErrorMessage?(
            String(localized: "無法啟動計時器，請確認 Screen Time 權限仍可使用後再試一次")
          )
          return
        }

        context.insert(NFCTapEvent(
          action: NFCTapEvent.actionStartBlock,
          profileId: profile.id,
          profileName: profile.name
        ))

        self.onSessionCreation?(.started(activeSession))
      }
    )
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    nfcScanner.onTagScanned = { [weak self] scannedTag in
      guard let self else { return }

      self.onCardNameScanned?(scannedTag.cardName)

      // Bug #6 (Co-Focus over Schedule): when a co-focus pairing is awaiting
      // this user's tap, divert this NFC tap to record a co-focus tap rather
      // than ending the active session. Schedule continues, apps remain
      // blocked. The user's tap is interpreted as "start co-focus", not
      // "end the current session". `NFCScannerUtil` always invokes this
      // callback via `DispatchQueue.main.async`, so MainActor.assumeIsolated
      // is safe here and lets us keep the dispatch decision synchronous.
      let diverted: Bool = MainActor.assumeIsolated {
        let manager = CoFocusManager.shared
        guard manager.shouldDivertNFCTapToCoFocus else { return false }
        manager.recordCoFocusTapFromNFC()
        return true
      }
      if diverted { return }

      context.insert(NFCTapEvent(
        action: NFCTapEvent.actionEndBlock,
        profileId: session.blockedProfile.id,
        profileName: session.blockedProfile.name
      ))

      session.endSessionFully(in: context, endReason: "card_tap") { error in
        self.onErrorMessage?("Failed to save session: \(error.localizedDescription)")
      }
      self.appBlocker.deactivateRestrictions()

      self.onSessionCreation?(.ended(session.blockedProfile))
    }

    nfcScanner.onError = { [weak self] message in
      self?.onErrorMessage?(message)
    }

    nfcScanner.onCancel = { [weak self] in
      self?.onErrorMessage?("")
    }

    // Set expected tag IDs so the scanner validates at the NFC dialog level
    nfcScanner.expectedTagIds = session.blockedProfile.physicalUnblockNFCTagIds
    nfcScanner.scan(profileName: session.blockedProfile.name, isUnlocking: true)

    return nil
  }
}
