import Foundation

/// Stores the user's analytics preferences in App Group UserDefaults.
///
/// General usage analytics is opt-out (default ON). The sensitive distraction
/// tracking added in Phase 3 will use a separate, opt-in flag — never folded into
/// this one.
enum AnalyticsConsent {
  private static let suite: UserDefaults =
    UserDefaults(suiteName: "group.DO.version3") ?? .standard

  private static let disclosureShownKey = "analyticsDisclosureShown"

  /// General usage analytics is always on by product decision (no user toggle);
  /// users are informed via onboarding and the privacy policy.
  static var isGeneralEnabled: Bool { true }

  /// Whether the analytics disclosure has been shown. No usage data is uploaded
  /// until the user has at least seen this notice (onboarding or the home alert).
  static var disclosureShown: Bool {
    suite.bool(forKey: disclosureShownKey)
  }

  static func markDisclosureShown() {
    suite.set(true, forKey: disclosureShownKey)
  }
}
