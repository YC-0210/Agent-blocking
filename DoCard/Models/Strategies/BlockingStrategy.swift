import SwiftData
import SwiftUI

enum SessionStatus {
  case started(BlockedProfileSession)
  case ended(BlockedProfiles)
}

protocol BlockingStrategy {
  static var id: String { get }
  var name: String { get }
  var description: String { get }
  var iconType: String { get }
  var color: Color { get }

  var hidden: Bool { get }

  // Callback closures session creation
  var onSessionCreation: ((SessionStatus) -> Void)? {
    get set
  }

  var onErrorMessage: ((String) -> Void)? {
    get set
  }

  /// Called after a successful NFC tap with the card name from the NDEF payload.
  /// `nil` means the card uses the old plain-UUID format (no name written).
  var onCardNameScanned: ((String?) -> Void)? {
    get set
  }

  func getIdentifier() -> String
  func startBlocking(
    context: ModelContext,
    profile: BlockedProfiles,
    forceStart: Bool?
  ) -> (any View)?
  func stopBlocking(context: ModelContext, session: BlockedProfileSession)
    -> (any View)?
}
