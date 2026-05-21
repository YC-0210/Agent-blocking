import Foundation

/// Anonymous, per-install identifier for usage analytics.
///
/// Stored in App Group UserDefaults (not Keychain) on purpose: Keychain items
/// survive app deletion on iOS, which would contradict the privacy policy promise
/// that all data is removed when the app is deleted. App Group storage is wiped on
/// deletion, giving clean per-install semantics — a reinstall counts as a new
/// install. Contains no personal information.
enum AnalyticsIdentity {
  private static let installIDKey = "analyticsInstallID"

  private static let suite: UserDefaults =
    UserDefaults(suiteName: "group.DO.version3") ?? .standard

  /// The stable anonymous install ID, generated on first access.
  static var installID: String {
    if let existing = suite.string(forKey: installIDKey) {
      return existing
    }
    let generated = UUID().uuidString
    suite.set(generated, forKey: installIDKey)
    return generated
  }
}
