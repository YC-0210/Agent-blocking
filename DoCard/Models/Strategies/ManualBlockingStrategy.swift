import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "ManualBlockingStrategy")

class ManualBlockingStrategy: BlockingStrategy {
  static var id: String = "ManualBlockingStrategy"

  var name: String = "Manual"
  var description: String =
    "Block and unblock profiles manually through the app"
  var iconType: String = "button.horizontal.top.press.fill"
  var color: Color = .blue

  var hidden: Bool = false

  var onSessionCreation: ((SessionStatus) -> Void)?
  var onErrorMessage: ((String) -> Void)?
  var onCardNameScanned: ((String?) -> Void)?

  private let appBlocker: AppBlockerUtil

  init(appBlocker: AppBlockerUtil = AppBlockerUtil()) {
    self.appBlocker = appBlocker
  }

  func getIdentifier() -> String {
    return ManualBlockingStrategy.id
  }

  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)? {
    self.appBlocker
      .activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

    let activeSession =
      BlockedProfileSession
      .createSession(
        in: context,
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
    session.endSessionFully(in: context, endReason: "") { error in
      self.onErrorMessage?("Failed to save session: \(error.localizedDescription)")
    }
    self.appBlocker.deactivateRestrictions()

    self.onSessionCreation?(.ended(session.blockedProfile))

    return nil
  }
}
