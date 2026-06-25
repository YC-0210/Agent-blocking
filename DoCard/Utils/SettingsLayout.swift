import Foundation

/// A category in the Settings hub. Each one is a row on the landing page that
/// drills into its own sub-page. `Identifiable`/`Hashable` so it drives both
/// `ForEach` and value-based `navigationDestination`.
enum SettingsCategory: Hashable, Identifiable {
  case account
  case card
  case notifications
  case personalization
  case devices
  case about
  case debug

  var id: Self { self }
}

/// A single row inside a category's sub-page.
enum SettingsRow: Hashable {
  case subscriptionStatus
  case restorePurchases

  case addCard
  case renameCard
  case cardlessStart

  case liveActivity
  case askToShare
  case reminder

  case homeCenterpiece
  case motivationGallery

  case deviceSync

  case version
  case licenses

  case debugTier
}

/// A pure, two-level description of the Settings hub: the ordered category rows
/// on the landing page, the rows inside each category's sub-page, and whether the
/// emergency-unlock row shows on the landing. `SettingsTabView` renders this
/// instead of re-deriving ordering and visibility inline, so the load-bearing
/// structure lives in one place and is unit-tested with no live SwiftUI —
/// mirroring `ActiveSessionStatus.resolve(manual:scheduled:)`.
///
/// Tier is intentionally NOT an input: it changes a row's label/handler (the
/// 帳號與訂閱 status text, the 連動裝置 tap opening the paywall), not which
/// categories or rows exist.
enum SettingsLayout {
  /// Ordered category rows on the landing page. Debug is appended last and only
  /// in debug builds — the caller passes the compile-time flag, so release builds
  /// simply never include it.
  static func landingCategories(includeDebug: Bool) -> [SettingsCategory] {
    var categories: [SettingsCategory] = [
      .account, .card, .notifications, .personalization, .devices, .about,
    ]
    if includeDebug { categories.append(.debug) }
    return categories
  }

  /// Whether the emergency-unlock row shows on the landing page — only while a
  /// focus session is active. It is a landing-level row, not a category.
  static func showsEmergencyRow(isBlocking: Bool) -> Bool { isBlocking }

  /// The rows inside a category's sub-page.
  ///
  /// - `cardPaired` adds 重新命名 to the DO Card page; it affects no other category.
  /// - `centerpiece` gates 我的動力 on the 個人化 page: the photo-management row
  ///   only makes sense while the gallery is the chosen home centerpiece, so it is
  ///   shown for `.gallery` and hidden for `.card` / `.tasks`. It affects no other
  ///   category. Defaults to `.gallery` (the app's default centerpiece) so callers
  ///   that don't care about this gating read the same rows as before.
  static func rows(
    in category: SettingsCategory,
    cardPaired: Bool,
    centerpiece: HomeCenterpiece = .gallery
  ) -> [SettingsRow] {
    switch category {
    case .account:
      return [.subscriptionStatus, .restorePurchases]

    case .card:
      var rows: [SettingsRow] = [.addCard]
      if cardPaired { rows.append(.renameCard) }
      rows.append(.cardlessStart)
      return rows

    case .notifications:
      return [.liveActivity, .askToShare, .reminder]

    case .personalization:
      var rows: [SettingsRow] = [.homeCenterpiece]
      if centerpiece == .gallery { rows.append(.motivationGallery) }
      return rows

    case .devices:
      return [.deviceSync]

    case .about:
      return [.version, .licenses]

    case .debug:
      return [.debugTier]
    }
  }
}
