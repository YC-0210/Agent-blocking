import Foundation

/// Which element occupies the middle of the DO page. Exactly one is shown at a
/// time, chosen by the user — a pick-one chooser, not a swipe deck.
/// See CONTEXT.md → "Home centerpiece".
enum HomeCenterpiece: String, CaseIterable, Identifiable {
  /// Motivation Gallery (動力相簿) — the default.
  case gallery
  /// The original DO Card.
  case card
  /// Today's Tasks (今日目標).
  case tasks

  var id: String { rawValue }

  /// `@AppStorage` key holding the user's choice.
  static let storageKey = "homeCenterpiece"

  /// Legacy Boolean key this selection replaced: `true` showed the gallery,
  /// `false` showed the DO Card.
  static let legacyGalleryKey = "showMotivationGalleryOnHome"

  /// Localized label for the chooser. "DO" stays in English per the brand
  /// naming rule.
  var label: String {
    switch self {
    case .gallery: return String(localized: "動力相簿")
    case .card: return String(localized: "DO 卡片")
    case .tasks: return String(localized: "今日目標")
    }
  }

  /// SF Symbol shown beside the label in the vertical chooser.
  var iconName: String {
    switch self {
    case .gallery: return "photo.on.rectangle.angled"
    case .card: return "creditcard.fill"
    case .tasks: return "checklist"
    }
  }

  /// One-line description shown under the label in the chooser, explaining what
  /// each centerpiece puts in the middle of the home screen.
  var subtitle: String {
    switch self {
    case .gallery: return String(localized: "滑動瀏覽你的動力照片")
    case .card: return String(localized: "顯示原本的 DO 卡片")
    case .tasks: return String(localized: "顯示今天要完成的任務")
    }
  }

  /// One-time migration from the legacy on/off gallery toggle to the three-way
  /// selection. Idempotent — only writes when the new key is absent, so it is
  /// safe to call on every launch.
  ///
  /// - `true` → `.gallery`
  /// - `false` → `.card`
  /// - legacy key absent (fresh install or never toggled) → `.gallery`,
  ///   matching the prior default.
  static func migrateLegacySettingIfNeeded(_ defaults: UserDefaults = .standard) {
    guard defaults.object(forKey: storageKey) == nil else { return }
    let showedGallery = (defaults.object(forKey: legacyGalleryKey) as? Bool) ?? true
    let migrated: HomeCenterpiece = showedGallery ? .gallery : .card
    defaults.set(migrated.rawValue, forKey: storageKey)
  }
}
