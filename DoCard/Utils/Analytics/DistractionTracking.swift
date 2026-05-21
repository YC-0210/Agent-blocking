import FamilyControls
import Foundation

/// Main-app consent + selection storage for distraction-usage tracking.
///
/// This is the sensitive, screen-time-derived metric, so it is **opt-in
/// (default OFF)** and kept entirely separate from the general analytics
/// opt-out switch. The user picks which apps to track via FamilyActivityPicker;
/// only the opaque token selection is stored (no app names ever leave the OS).
enum DistractionTracking {
  private static let suite: UserDefaults =
    UserDefaults(suiteName: "group.DO.version3") ?? .standard

  /// AppStorage-compatible key so a SwiftUI toggle can bind to the same value.
  static let enabledKey = "distractionTrackingEnabled"
  private static let selectionKey = "distractionSelection"

  /// Whether the user has opted in. Default OFF.
  static var isEnabled: Bool {
    suite.bool(forKey: enabledKey)
  }

  static func setEnabled(_ enabled: Bool) {
    suite.set(enabled, forKey: enabledKey)
  }

  /// The user's chosen "most distracting" apps as an opaque token selection.
  static var selection: FamilyActivitySelection {
    get {
      guard let data = suite.data(forKey: selectionKey),
            let decoded = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
      else { return FamilyActivitySelection() }
      return decoded
    }
    set {
      if let data = try? JSONEncoder().encode(newValue) {
        suite.set(data, forKey: selectionKey)
      }
    }
  }

  static var hasSelection: Bool {
    let sel = selection
    return !sel.applicationTokens.isEmpty
      || !sel.categoryTokens.isEmpty
      || !sel.webDomainTokens.isEmpty
  }

  /// Tracking is "configured" only when opted in AND at least one app is chosen.
  static var isConfigured: Bool {
    isEnabled && hasSelection
  }
}
