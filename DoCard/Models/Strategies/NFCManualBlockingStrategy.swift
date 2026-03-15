import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "NFCManualBlockingStrategy")

class NFCManualBlockingStrategy: BlockingStrategy {
  static var id: String = "NFCManualBlockingStrategy"

  var name: String = "NFC + Manual"
  var description: String = "Block manually, but unblock by using any NFC tag"
  var iconType: String = "badge.plus.radiowaves.forward"
  var color: Color = .yellow

  var hidden: Bool = false

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?

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

    self.onSessionCreation?(.started(activeSession))

    return nil
  }

  func stopBlocking(
    context: ModelContext,
    session: BlockedProfileSession
  ) -> (any View)? {
    nfcScanner.onTagScanned = { [weak self] scannedTag in
      guard let self else { return }

      session.endSession()
      do {
        try context.save()
      } catch {
        logger.error("Failed to save session after NFC manual unlock: \(error.localizedDescription)")
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
