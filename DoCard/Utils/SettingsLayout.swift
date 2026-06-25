import Foundation

/// A single, pure description of the Settings screen's structure: which sections
/// appear, in what order, and which rows each contains — for a given app state.
///
/// `SettingsTabView` renders the output of `resolve(...)` instead of re-deriving
/// ordering and visibility inline, so the load-bearing rules of the redesign live
/// in one place and are unit-tested with no live SwiftUI — mirroring
/// `ActiveSessionStatus.resolve(manual:scheduled:)`.
///
/// Tier is intentionally NOT an input: it changes a row's label/handler (e.g. the
/// Premium card's text, or the 連動裝置 tap opening the paywall), not which rows
/// exist or their order. The Premium card always sits on top and 連動裝置 always
/// shows.
enum SettingsRow: Hashable {
  case premium

  case addCard
  case renameCard
  case cardlessStart

  case homeCenterpiece
  case motivationGallery

  case liveActivity
  case askToShare
  case reminder

  case deviceSync

  case version
  case licenses

  case emergency

  case debugTier
}

/// Stable identity for each Settings group (drives `ForEach` and section headers).
enum SettingsSectionID: Hashable {
  case subscription
  case card
  case personalization
  case notifications
  case devices
  case emergency
  case about
  case debug
}

struct SettingsSection: Equatable, Identifiable {
  let id: SettingsSectionID
  let rows: [SettingsRow]
}

enum SettingsLayout {
  /// Resolve the ordered sections from plain facts.
  ///
  /// - `cardPaired`: at least one DO Card is paired → show 重新命名.
  /// - `isBlocking`: a focus session is active → show 緊急解鎖 (after 連動裝置,
  ///   before 關於).
  /// - `includeDebug`: debug build → append the Debug section last. Callers pass
  ///   the compile-time flag, e.g. `#if DEBUG true #else false #endif`, so this
  ///   stays a pure value that release builds simply never set.
  static func resolve(
    cardPaired: Bool,
    isBlocking: Bool,
    includeDebug: Bool
  ) -> [SettingsSection] {
    var sections: [SettingsSection] = []

    // 1. 訂閱
    sections.append(SettingsSection(id: .subscription, rows: [.premium]))

    // 2. DO 卡片
    var cardRows: [SettingsRow] = [.addCard]
    if cardPaired { cardRows.append(.renameCard) }
    cardRows.append(.cardlessStart)
    sections.append(SettingsSection(id: .card, rows: cardRows))

    // 3. 個人化 (merged 主畫面中央 + 動力相簿)
    sections.append(
      SettingsSection(id: .personalization, rows: [.homeCenterpiece, .motivationGallery]))

    // 4. 通知與提醒
    sections.append(
      SettingsSection(id: .notifications, rows: [.liveActivity, .askToShare, .reminder]))

    // 5. 連動裝置 (always present — free taps open the paywall)
    sections.append(SettingsSection(id: .devices, rows: [.deviceSync]))

    // 6. 緊急 (only while a focus session is active)
    if isBlocking {
      sections.append(SettingsSection(id: .emergency, rows: [.emergency]))
    }

    // 7. 關於 (always present)
    sections.append(SettingsSection(id: .about, rows: [.version, .licenses]))

    // 8. Debug (debug builds only — always last)
    if includeDebug {
      sections.append(SettingsSection(id: .debug, rows: [.debugTier]))
    }

    return sections
  }
}
