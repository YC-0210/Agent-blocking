import Foundation

/// Tracks whether the user has seen the What's New modal for each app version.
/// Uses a version-specific key so future releases can show their own modal independently.
final class WhatsNewManager: ObservableObject {
  static let shared = WhatsNewManager()

  private static let store = UserDefaults(suiteName: "group.DO.version3")!
  private static let seenKey = "whatsNewSeenVersion_2_1_0"

  /// `true` until the user dismisses or acts on the modal for this version.
  @Published var shouldShowWhatsNew: Bool

  private init() {
    shouldShowWhatsNew = !Self.store.bool(forKey: Self.seenKey)
  }

  func markAsSeen() {
    guard shouldShowWhatsNew else { return }
    Self.store.set(true, forKey: Self.seenKey)
    shouldShowWhatsNew = false
  }

  /// Debug only — clears the seen flag so the modal will re-appear.
  func reset() {
    Self.store.removeObject(forKey: Self.seenKey)
    shouldShowWhatsNew = true
  }
}
