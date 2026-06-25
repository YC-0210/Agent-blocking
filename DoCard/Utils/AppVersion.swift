import Foundation

/// The user-facing app version string for the 關於 (About) row. The formatting is
/// a pure function of the two Info.plist values, so it is unit-tested without a
/// live bundle; `current` reads the real values at the call site.
enum AppVersion {
  /// Compose "x.y.z (build)" from the marketing version and build number.
  /// Falls back to "—" when the marketing version is missing/empty, and omits
  /// the parenthetical when there is no build number.
  static func displayString(short: String?, build: String?) -> String {
    guard let short, !short.isEmpty else { return "—" }
    if let build, !build.isEmpty {
      return "\(short) (\(build))"
    }
    return short
  }

  /// The running app's version, read from the main bundle's Info.plist.
  static var current: String {
    displayString(
      short: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
      build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String)
  }
}
