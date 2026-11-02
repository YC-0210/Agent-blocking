import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "NFCBlockingStrategy")

class NFCBlockingStrategy: BlockingStrategy {
  static var id: String = "NFCBlockingStrategy"

  var name: String = String(localized: "Classic Mode")
  var description: String = String(localized: "Tap to lock apps, tap your DO Card to unlock")
  var iconType: String = "wave.3.right.circle.fill"
  var color: Color = Color(red: 1.0, green: 0.42, blue: 0.21)

  var hidden: Bool = false

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?
  var onCardNameScanned: ((String?) -> Void)?

  private let nfcScanner: NFCScannerUtil
  private let appBlocker: AppBlockerUtil

  init(
    nfcScanner: NFCScannerUtil = NFCScannerUtil(),
    appBlocker: AppBlockerUtil = AppBlockerUtil()
  ) {
    self.nfcScanner = nfcScanner
    self.appBlocker = appBlocker
  }

  func getIdentifier() -> String {
    return NFCBlockingStrategy.id
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

    // Start blocking directly without requiring NFC tap
    self.appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

    let activeSession =
      BlockedProfileSession
      .createSession(
        in: context,
        withTag: NFCBlockingStrategy.id,
        withProfile: profile,
        forceStart: forceStart ?? false
      )

    context.insert(NFCTapEvent(
      action: NFCTapEvent.actionStartBlock,
      profileId: profile.id,
      profileName: profile.name
    ))

    self.onSessionCreation?(.started(activeSession))

    return nil
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    nfcScanner.onTagScanned = { [weak self] scannedTag in
      guard let self else { return }
      guard session.isActive else { return }

      self.onCardNameScanned?(scannedTag.cardName)

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
      // User dismissed the NFC dialog — notify as empty error
      // so the strategy manager can reset its processing guard.
      self?.onErrorMessage?("")
    }

    // Set expected tag IDs so the scanner validates at the NFC dialog level
    nfcScanner.expectedTagIds = session.blockedProfile.physicalUnblockNFCTagIds
    nfcScanner.scan(profileName: session.blockedProfile.name, isUnlocking: true)

    return nil
  }
}
