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

  private let nfcScanner: NFCScannerUtil = NFCScannerUtil()
  private let appBlocker: AppBlockerUtil = AppBlockerUtil()

  func getIdentifier() -> String {
    return NFCBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
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
        logger.error("Failed to save session after NFC unlock: \(error.localizedDescription)")
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
