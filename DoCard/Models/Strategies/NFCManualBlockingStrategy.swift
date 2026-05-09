import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "NFCManualBlockingStrategy")

class NFCManualBlockingStrategy: BlockingStrategy {
  static var id: String = "NFCManualBlockingStrategy"

  var name: String = "DO Card + Manual"
  var description: String = "Block manually, but unblock by tapping your DO Card"
  var iconType: String = "badge.plus.radiowaves.forward"
  var color: Color = .yellow

  var hidden: Bool = false

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?
  var onCardNameScanned: ((String?) -> Void)?

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return NFCManualBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    self.appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

    let activeSession =
      BlockedProfileSession
      .createSession(
        in: context,
        // Manually starting sessions, since nothing was scanned to start there is no tag to store for each session
        withTag: ManualBlockingStrategy.id,
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
