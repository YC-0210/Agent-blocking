import FamilyControls
import Foundation

/// Utility functions for working with FamilyActivitySelection
struct FamilyActivityUtil {

  /// Counts the total number of selected apps (individual apps + apps expanded from categories).
  /// Categories are expanded into individual applicationTokens when FamilyActivitySelection
  /// is initialized with includeEntireCategory: true.
  /// Web domains are NOT counted toward the app limit.
  /// - Parameters:
  ///   - selection: The FamilyActivitySelection to count
  ///   - allowMode: Whether this is for allow mode (unused, kept for API compatibility)
  /// - Returns: Total count of selected apps (applicationTokens only)
  static func countSelectedApps(_ selection: FamilyActivitySelection, allowMode: Bool = false)
    -> Int
  {
    return selection.applicationTokens.count
  }

  /// Legacy name kept for compatibility — calls countSelectedApps
  static func countSelectedActivities(_ selection: FamilyActivitySelection, allowMode: Bool = false)
    -> Int
  {
    return countSelectedApps(selection, allowMode: allowMode)
  }

  /// Gets display text for the app count
  /// - Parameters:
  ///   - selection: The FamilyActivitySelection to display
  ///   - allowMode: Whether this is for allow mode
  /// - Returns: Formatted display text, e.g. "3 個 App"
  static func getCountDisplayText(_ selection: FamilyActivitySelection, allowMode: Bool = false)
    -> String
  {
    let apps = selection.applicationTokens.count
    return String(localized: "\(apps) 個 App")
  }

  /// Returns a compact formatted string showing app count only
  /// - Parameter selection: The FamilyActivitySelection to format
  /// - Returns: e.g. "3 個 App" or "0 個 App"
  static func formatAppCount(_ selection: FamilyActivitySelection) -> String {
    let apps = selection.applicationTokens.count
    return String(localized: "\(apps) 個 App")
  }

  /// Determines if a warning should be shown for allow mode category selection
  /// - Parameters:
  ///   - selection: The FamilyActivitySelection to check
  ///   - allowMode: Whether this is for allow mode
  /// - Returns: True if warning should be shown
  static func shouldShowAllowModeWarning(
    _ selection: FamilyActivitySelection, allowMode: Bool = false
  ) -> Bool {
    return allowMode && selection.categories.count > 0
  }

  /// Gets a detailed breakdown of the selection for debugging/stats
  /// - Parameter selection: The FamilyActivitySelection to analyze
  /// - Returns: A breakdown of categories, apps, and domains
  static func getSelectionBreakdown(_ selection: FamilyActivitySelection) -> (
    categories: Int, applications: Int, webDomains: Int
  ) {
    return (
      categories: selection.categories.count,
      applications: selection.applicationTokens.count,
      webDomains: selection.webDomains.count
    )
  }
}
