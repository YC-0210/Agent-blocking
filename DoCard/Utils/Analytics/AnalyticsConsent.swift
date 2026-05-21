import Foundation

/// Stores the user's analytics preferences in App Group UserDefaults.
///
/// General usage analytics is opt-out (default ON). The sensitive distraction
/// tracking added in Phase 3 will use a separate, opt-in flag — never folded into
/// this one.
enum AnalyticsConsent {
  private static let suite: UserDefaults =
    UserDefaults(suiteName: "group.DO.version3") ?? .standard

  /// AppStorage-compatible key so the SwiftUI toggle binds to the same value.
  static let generalEnabledKey = "analyticsEnabled"
  private static let disclosureShownKey = "analyticsDisclosureShown"

  /// General usage analytics. Defaults to ON when the user has never set it.
  static var isGeneralEnabled: Bool {
    if suite.object(forKey: generalEnabledKey) == nil { return true }
    return suite.bool(forKey: generalEnabledKey)
  }

  static func setGeneralEnabled(_ enabled: Bool) {
    suite.set(enabled, forKey: generalEnabledKey)
  }

  /// Whether the first-run analytics disclosure has been shown. No usage data is
  /// uploaded until the user has at least seen this notice.
  static var disclosureShown: Bool {
    suite.bool(forKey: disclosureShownKey)
  }

  static func markDisclosureShown() {
    suite.set(true, forKey: disclosureShownKey)
  }
}
