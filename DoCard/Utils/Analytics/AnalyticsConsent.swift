import Foundation

/// Stores the user's analytics preferences in App Group UserDefaults.
///
/// General usage analytics is opt-out (default ON). The sensitive distraction
/// tracking added in Phase 3 will use a separate, opt-in flag — never folded into
/// this one.
enum AnalyticsConsent {
  static var disclosureTitle: String { String(localized: "隱私說明") }

  static var disclosureMessage: String {
    String(localized: "為了改善 DO Card，我們會收集你的引導問卷答案與鎖定時段資料，並以隨機產生的 App 識別碼傳送至第三方網站進行使用分析。請勿在「其他」填寫姓名、電子郵件或其他個人資料。")
  }

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
    NotificationCenter.default.post(name: Notification.Name("DOCardAnalyticsDisclosureChanged"), object: nil)
  }
}
