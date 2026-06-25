import OSLog
import SwiftData
import SwiftUI

private let settingsLog = Logger(subsystem: "online.do.card.app", category: "SettingsTab")

/// Shared at file scope so both `SettingsTabView` and `RenameCardSheet` can reference it
/// without crossing a `private` boundary.
fileprivate enum RenameState {
  case idle
  case writing
  case success
}

struct SettingsTabView: View {
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var strategyManager: StrategyManager
  @EnvironmentObject var onboardingManager: OnboardingManager
  @EnvironmentObject var subscriptionManager: SubscriptionManager
  @Environment(\.modelContext) private var modelContext

  @AppStorage("globalEnableLiveActivity") private var enableLiveActivity: Bool = false
  @AppStorage("globalEnableReminder") private var enableReminder: Bool = false
  @AppStorage("askToShareAfterSession") private var askToShareAfterSession: Bool = true
  @AppStorage("allowCardlessStart") private var allowCardlessStart = false

  @State private var isPairing = false
  @State private var pairSuccess = false
  @State private var showPaywall = false

  // Rename card sheet
  @State private var showRenameSheet = false
  @State private var renameNameInput = ""
  @State private var renameState: RenameState = .idle

  /// Programmatic-navigation flag for the Mac sync entry — tap goes through
  /// a paywall check first; only premium users flip this to true to open
  /// `MacPairingView`. Mirrors ScheduleTabView's premium-gated flow.
  @State private var navigateToMacPairing = false

  // TEMP test entry for the Motivation Gallery edit screen (Phase 2).
  // The real entry point is the pencil on the main screen, added in Phase 3.
  @State private var showGalleryEditor = false
  @AppStorage(HomeCenterpiece.storageKey) private var centerpiece: HomeCenterpiece = .gallery

  private let nfcScanner = NFCScannerUtil()
  private let nfcRenameScanner = NFCScannerUtil()

  var onEmergencyTapped: () -> Void

  /// Debug category ships only in debug builds — passed as a plain Bool so the
  /// pure `SettingsLayout` stays testable and release builds simply never set it.
  private var includeDebug: Bool {
    #if DEBUG
      return true
    #else
      return false
    #endif
  }

  // MARK: - Landing page

  var body: some View {
    NavigationStack {
      Form {
        Section {
          ForEach(SettingsLayout.landingCategories(includeDebug: includeDebug)) { category in
            NavigationLink(value: category) {
              categoryRow(category)
            }
          }
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        // Emergency unlock — a landing-level safety row, only while blocking, so
        // it is reachable in one tap during a focus session (not buried in a
        // sub-page). Always free.
        if SettingsLayout.showsEmergencyRow(
          isBlocking: strategyManager.activeSessionStatus.isBlocking)
        {
          Section {
            emergencyRow
          }
          .listRowBackground(Color(.systemGray6).opacity(0.08))
        }
      }
      .scrollContentBackground(.hidden)
      .navigationTitle(String(localized: "設定"))
      .navigationDestination(for: SettingsCategory.self) { category in
        categoryPage(category)
      }
      .navigationDestination(isPresented: $navigateToMacPairing) {
        MacPairingView()
      }
      .sheet(isPresented: $showPaywall) {
        PremiumUpgradeView()
          .environmentObject(subscriptionManager)
      }
      .sheet(isPresented: $showGalleryEditor) {
        MotivationGalleryEditView()
          .environmentObject(themeManager)
      }
      .sheet(isPresented: $showRenameSheet, onDismiss: {
        renameNameInput = ""
        renameState = .idle
      }) {
        RenameCardSheet(
          nameInput: $renameNameInput,
          renameState: renameState,
          themeColor: themeManager.themeColor,
          onWrite: startRenameWrite
        )
      }
      .onChange(of: enableLiveActivity) { _, newValue in
        syncLiveActivityToAllProfiles(enabled: newValue)
      }
      .onChange(of: enableReminder) { _, newValue in
        syncReminderToAllProfiles(enabled: newValue)
      }
    }
  }

  /// A landing-page category row: colored icon badge + title. The chevron is
  /// supplied automatically by `NavigationLink`.
  private func categoryRow(_ category: SettingsCategory) -> some View {
    HStack(spacing: 12) {
      categoryBadge(category)
      Text(categoryTitle(category))
    }
  }

  /// iOS-Settings-style icon badge (Option C — soft tint): a colored glyph on a
  /// soft tint of the same hue. Functional categories tint with the user's theme
  /// color so they stay on-brand and follow theme changes; 帳號與訂閱 uses a
  /// premium gold; Debug stays neutral grey.
  private func categoryBadge(_ category: SettingsCategory) -> some View {
    let style = categoryBadgeStyle(category)
    return Image(systemName: style.symbol)
      .font(.system(size: 15, weight: .semibold))
      .foregroundStyle(style.glyph)
      .frame(width: 29, height: 29)
      .background(RoundedRectangle(cornerRadius: 7).fill(style.background))
  }

  private struct CategoryBadgeStyle {
    let symbol: String
    let glyph: Color
    let background: Color
  }

  private func categoryBadgeStyle(_ category: SettingsCategory) -> CategoryBadgeStyle {
    let brand = themeManager.themeColor
    switch category {
    case .account:
      return CategoryBadgeStyle(
        symbol: "crown.fill",
        glyph: ThemeManager.premiumGoldDeep,
        background: ThemeManager.premiumGold.opacity(0.18))
    case .card:
      return CategoryBadgeStyle(
        symbol: "creditcard.fill", glyph: brand, background: brand.opacity(0.16))
    case .notifications:
      return CategoryBadgeStyle(
        symbol: "bell.fill", glyph: brand, background: brand.opacity(0.16))
    case .personalization:
      return CategoryBadgeStyle(
        symbol: "photo.fill", glyph: brand, background: brand.opacity(0.16))
    case .devices:
      return CategoryBadgeStyle(
        symbol: "laptopcomputer.and.iphone", glyph: brand, background: brand.opacity(0.16))
    case .about:
      return CategoryBadgeStyle(
        symbol: "info.circle.fill", glyph: brand, background: brand.opacity(0.16))
    case .debug:
      return CategoryBadgeStyle(
        symbol: "hammer.fill", glyph: .gray, background: Color.gray.opacity(0.16))
    }
  }

  private func categoryTitle(_ category: SettingsCategory) -> String {
    switch category {
    case .account: return String(localized: "帳號與訂閱")
    case .card: return String(localized: "DO Card")
    case .notifications: return String(localized: "通知與提醒")
    case .personalization: return String(localized: "個人化")
    case .devices: return String(localized: "連動裝置")
    case .about: return String(localized: "關於")
    case .debug: return "🛠 Debug"  // verbatim — never enters the localization catalog
    }
  }

  // MARK: - Category sub-pages

  @ViewBuilder
  private func categoryPage(_ category: SettingsCategory) -> some View {
    Form {
      Section {
        ForEach(
          SettingsLayout.rows(
            in: category,
            cardPaired: onboardingManager.isDOCardPaired,
            centerpiece: centerpiece),
          id: \.self
        ) { row in
          rowView(for: row)
        }
      } footer: {
        if let footerText = subPageFooter(for: category) {
          Text(footerText)
        }
      }
      .listRowBackground(Color(.systemGray6).opacity(0.08))
    }
    .scrollContentBackground(.hidden)
    .navigationTitle(categoryTitle(category))
    .navigationBarTitleDisplayMode(.inline)
  }

  private func subPageFooter(for category: SettingsCategory) -> String? {
    switch category {
    case .debug:
      // verbatim: debug-only strings must not enter the localization catalog
      return "僅 Debug 版本顯示，永遠不會進到 App Store。模擬免費／付費體驗，不會更動你的真實訂閱。"
    default:
      return nil
    }
  }

  // MARK: - Rows

  /// A consistently sized leading icon so every sub-page row lines up in one
  /// column — matches `CustomToggle`'s icon column width.
  private func leadingIcon(_ name: String, color: Color) -> some View {
    Image(systemName: name)
      .font(.title3)
      .foregroundStyle(color)
      .frame(width: 28)
  }

  @ViewBuilder
  private func rowView(for row: SettingsRow) -> some View {
    switch row {
    case .subscriptionStatus: subscriptionStatusRow
    case .restorePurchases: restorePurchasesRow
    case .addCard: addCardRow
    case .renameCard: renameCardRow
    case .cardlessStart: cardlessStartRow
    case .liveActivity: liveActivityRow
    case .askToShare: askToShareRow
    case .reminder: reminderRow
    case .homeCenterpiece: centerpieceRow
    case .motivationGallery: galleryRow
    case .deviceSync: deviceSyncRow
    case .version: versionRow
    case .licenses: licensesRow
    case .debugTier: debugRow
    }
  }

  private var subscriptionStatusCaption: String {
    if subscriptionManager.isPremium {
      if let expiry = subscriptionManager.expirationDate {
        return String(localized: "有效期限至 \(expiry.formatted(date: .abbreviated, time: .omitted))")
      }
      return String(localized: "已啟用所有功能")
    }
    return String(localized: "守護最多 50 個 App 與排程自動化")
  }

  private var subscriptionStatusRow: some View {
    Button(action: { showPaywall = true }) {
      HStack(spacing: 12) {
        leadingIcon(subscriptionManager.isPremium ? "crown.fill" : "crown", color: .orange)

        VStack(alignment: .leading, spacing: 2) {
          Text(subscriptionManager.isPremium
            ? String(localized: "Premium 會員")
            : String(localized: "升級 Premium"))
            .font(.headline)
            .foregroundStyle(.primary)
          Text(subscriptionStatusCaption)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var restorePurchasesRow: some View {
    Button {
      Task { await subscriptionManager.restorePurchases() }
    } label: {
      HStack(spacing: 12) {
        leadingIcon("arrow.clockwise", color: themeManager.themeColor)
        Text(String(localized: "還原購買"))
          .foregroundStyle(.primary)
        Spacer()
      }
    }
  }

  private var addCardRow: some View {
    Button(action: startPairing) {
      HStack(spacing: 12) {
        leadingIcon(
          "wave.3.right.circle.fill",
          color: onboardingManager.canPairMoreCards ? themeManager.themeColor : .secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "新增 DO Card"))
            .font(.headline)
            .foregroundStyle(onboardingManager.canPairMoreCards ? .primary : .secondary)

          Text(String(localized: "已配對 \(onboardingManager.pairedDOCardCount)/\(OnboardingManager.maxPairedCards) 張卡片"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if pairSuccess {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          Image(systemName: "plus.circle")
            .foregroundStyle(onboardingManager.canPairMoreCards ? themeManager.themeColor : .secondary)
        }
      }
    }
    .disabled(isPairing || !onboardingManager.canPairMoreCards)
  }

  private var renameCardRow: some View {
    Button(action: { showRenameSheet = true }) {
      HStack(spacing: 12) {
        leadingIcon("pencil.circle.fill", color: themeManager.themeColor)

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "重新命名 DO Card"))
            .font(.headline)
            .foregroundStyle(.primary)
          if let name = onboardingManager.doCardName {
            Text(name)
              .font(.caption)
              .foregroundStyle(.secondary)
          } else {
            Text(String(localized: "命名你的DO Card"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var cardlessStartRow: some View {
    CustomToggle(
      systemImage: "bolt.circle",
      title: String(localized: "允許免卡開始"),
      description: String(localized: "在主畫面顯示「直接開始」按鈕，不靠卡也能開始專注"),
      isOn: $allowCardlessStart
    )
  }

  /// The home-centerpiece chooser. A vertical list of three selectable rows
  /// (icon + label + one-line description) instead of a cramped segmented
  /// control — bigger tap targets that match the rest of the settings rows. The
  /// selected option is tinted with the brand theme color and carries a check.
  /// Choosing 動力相簿 reveals the 我的動力 row below (see `SettingsLayout.rows`).
  private var centerpieceRow: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(String(localized: "主畫面中央顯示"))
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 2)

      ForEach(HomeCenterpiece.allCases) { option in
        centerpieceOptionRow(option)
      }
    }
    .padding(.vertical, 4)
  }

  private func centerpieceOptionRow(_ option: HomeCenterpiece) -> some View {
    let isSelected = centerpiece == option
    return Button {
      withAnimation(.easeInOut(duration: 0.2)) { centerpiece = option }
    } label: {
      HStack(spacing: 12) {
        leadingIcon(option.iconName, color: isSelected ? themeManager.themeColor : .secondary)

        VStack(alignment: .leading, spacing: 2) {
          Text(option.label)
            .font(.headline)
            .foregroundStyle(.primary)
          Text(option.subtitle)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isSelected ? themeManager.themeColor : Color.secondary.opacity(0.35))
      }
      .padding(.vertical, 8)
      .padding(.horizontal, 10)
      .background(
        RoundedRectangle(cornerRadius: 10)
          .fill(isSelected ? themeManager.themeColor.opacity(0.12) : Color.clear)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var galleryRow: some View {
    Button(action: { showGalleryEditor = true }) {
      HStack(spacing: 12) {
        leadingIcon("photo.on.rectangle.angled", color: themeManager.themeColor)

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "我的動力"))
            .font(.headline)
            .foregroundStyle(.primary)
          Text(String(localized: "管理主畫面的動力照片"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var liveActivityRow: some View {
    CustomToggle(
      systemImage: "bell.badge",
      title: String(localized: "動態島 / 鎖定畫面顯示"),
      description: String(localized: "專注時在動態島和鎖定畫面即時顯示計時與狀態"),
      isOn: $enableLiveActivity
    )
  }

  private var askToShareRow: some View {
    CustomToggle(
      systemImage: "square.and.arrow.up",
      title: String(localized: "完成後詢問是否分享"),
      description: String(localized: "專注時段滿 30 分鐘且正常結束時，跳出分享提示"),
      isOn: $askToShareAfterSession
    )
  }

  private var reminderRow: some View {
    CustomToggle(
      systemImage: "alarm",
      title: String(localized: "提醒"),
      description: String(localized: "專注結束後發送提醒通知"),
      isOn: $enableReminder
    )
  }

  private var deviceSyncRow: some View {
    // Mac sync is a Premium feature in v2.0.6+ — entry routes through a paywall
    // check. Premium users flip `navigateToMacPairing` to open `MacPairingView`
    // (destination declared on the landing Form); free users see PremiumUpgradeView
    // via the existing `showPaywall` sheet. UI is intentionally unchanged so the
    // row still looks tappable for free users (mirrors ScheduleTabView's pattern).
    Button {
      if subscriptionManager.entitlements.canSyncExternalDevices {
        navigateToMacPairing = true
      } else {
        showPaywall = true
      }
    } label: {
      HStack(spacing: 12) {
        leadingIcon("laptopcomputer.and.iphone", color: themeManager.themeColor)

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "Chrome / Safari 連動"))
            .font(.headline)
            .foregroundStyle(.primary)
          Text(String(localized: "刷卡時同步封鎖 Chrome / Safari 上的網站"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
          .font(.caption)
      }
    }
    .buttonStyle(.plain)
  }

  private var versionRow: some View {
    HStack(spacing: 12) {
      leadingIcon("info.circle", color: themeManager.themeColor)
      Text(String(localized: "版本"))
      Spacer()
      Text(AppVersion.current)
        .foregroundStyle(.secondary)
    }
  }

  private var licensesRow: some View {
    NavigationLink {
      LicensesView()
    } label: {
      HStack(spacing: 12) {
        leadingIcon("doc.text", color: themeManager.themeColor)
        Text(String(localized: "授權"))
      }
    }
  }

  private var emergencyRow: some View {
    Button(action: onEmergencyTapped) {
      HStack(spacing: 12) {
        leadingIcon("exclamationmark.triangle.fill", color: .red)

        VStack(alignment: .leading, spacing: 2) {
          Text(String(localized: "緊急解鎖"))
            .font(.headline)
            .foregroundStyle(.red)
          Text(String(localized: "立即解除所有阻擋"))
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Image(systemName: "chevron.right")
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var debugRow: some View {
    #if DEBUG
      Picker(selection: debugForcedTierBinding) {
        Text(verbatim: "真實訂閱").tag("real")
        Text(verbatim: "免費 Free").tag("free")
        Text(verbatim: "付費 Premium").tag("premium")
      } label: {
        Text(verbatim: "強制訂閱層級")
      }
    #else
      // Disambiguate from the app's own `Components/Common/EmptyView.swift`,
      // which shadows SwiftUI's and requires arguments — a bare `EmptyView()`
      // here only compiles in Release (Debug takes the #if branch), so it slips
      // past Debug builds and breaks archiving.
      SwiftUI.EmptyView()
    #endif
  }

  #if DEBUG
    /// Debug-only binding for the "force subscription tier" picker. Writes the
    /// override into the App Group (so the extensions honor it too) and nudges the
    /// subscription manager so the UI re-reads immediately. Compiled out of release.
    private var debugForcedTierBinding: Binding<String> {
      let mgr = subscriptionManager
      return Binding(
        get: {
          switch SharedData.debugForcedTier {
          case .free: return "free"
          case .premium: return "premium"
          case nil: return "real"
          }
        },
        set: { newValue in
          switch newValue {
          case "free": SharedData.debugForcedTier = .free
          case "premium": SharedData.debugForcedTier = .premium
          default: SharedData.debugForcedTier = nil
          }
          mgr.objectWillChange.send()
        }
      )
    }
  #endif

  // MARK: - Sync Global Settings to All Profiles

  private func syncLiveActivityToAllProfiles(enabled: Bool) {
    do {
      let profiles = try BlockedProfiles.fetchProfiles(in: modelContext)
      for profile in profiles {
        profile.enableLiveActivity = enabled
        BlockedProfiles.updateSnapshot(for: profile)
      }
      try modelContext.save()
    } catch {
      settingsLog.error("Failed to sync Live Activity setting: \(error.localizedDescription)")
    }
  }

  private func syncReminderToAllProfiles(enabled: Bool) {
    do {
      let profiles = try BlockedProfiles.fetchProfiles(in: modelContext)
      for profile in profiles {
        if enabled {
          // Set a default reminder time (5 minutes) if not already set
          if profile.reminderTimeInSeconds == nil {
            profile.reminderTimeInSeconds = 300
          }
        } else {
          profile.reminderTimeInSeconds = nil
        }
        BlockedProfiles.updateSnapshot(for: profile)
      }
      try modelContext.save()
    } catch {
      settingsLog.error("Failed to sync Reminder setting: \(error.localizedDescription)")
    }
  }


  // MARK: - DO Card Pairing

  private func startPairing() {
    guard onboardingManager.canPairMoreCards else { return }

    isPairing = true
    pairSuccess = false

    nfcScanner.onTagScanned = { result in
      guard result.payload != nil else {
        isPairing = false
        return
      }

      // Check if this card is already paired
      if onboardingManager.isTagIdPaired(result.id) {
        isPairing = false
        return
      }

      // Add the new card to global paired list
      onboardingManager.pairDOCard(tagId: result.id)

      // Add the new tag ID to all existing profiles
      addTagIdToAllProfiles(result.id)

      isPairing = false
      pairSuccess = true

      // Reset checkmark after a few seconds
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
        pairSuccess = false
      }
    }

    nfcScanner.onError = { _ in
      isPairing = false
    }

    nfcScanner.onCancel = {
      isPairing = false
    }

    nfcScanner.scan(profileName: "DO Card", isUnlocking: false)
  }

  private func addTagIdToAllProfiles(_ tagId: String) {
    do {
      let profiles = try BlockedProfiles.fetchProfiles(in: modelContext)
      for profile in profiles {
        var tagIds = profile.physicalUnblockNFCTagIds ?? []
        if !tagIds.contains(tagId) {
          tagIds.append(tagId)
          profile.physicalUnblockNFCTagIds = tagIds
          BlockedProfiles.updateSnapshot(for: profile)
        }
      }
      try modelContext.save()
    } catch {
      settingsLog.error("Failed to update profiles with new DO Card: \(error.localizedDescription)")
    }
  }

  // MARK: - DO Card Rename

  private func startRenameWrite() {
    let name = renameNameInput.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }

    renameState = .writing

    // Only allow writing to a card that is already paired
    nfcRenameScanner.expectedTagIds = onboardingManager.pairedDOCardTagIds

    nfcRenameScanner.onTagScanned = { result in
      // Update the stored card name from the write result
      onboardingManager.doCardName = result.cardName ?? name
      renameState = .success

      DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        showRenameSheet = false
      }
    }

    nfcRenameScanner.onError = { _ in
      renameState = .idle
    }

    nfcRenameScanner.onCancel = {
      renameState = .idle
    }

    // requirePaired: true — only allow renaming a card that is already paired.
    nfcRenameScanner.scanAndWrite(name: name, requirePaired: true)
  }
}

// MARK: - Rename Card Sheet

private struct RenameCardSheet: View {
  @Binding var nameInput: String
  let renameState: RenameState
  let themeColor: Color
  let onWrite: () -> Void

  private var isWriting: Bool {
    if case .writing = renameState { return true }
    return false
  }

  private var isSuccess: Bool {
    if case .success = renameState { return true }
    return false
  }

  var body: some View {
    VStack(spacing: 24) {
      Text(String(localized: "重新命名 DO Card"))
        .font(.system(size: 20, weight: .bold))
        .padding(.top, 8)

      TextField(String(localized: "例：彥丞的 DO Card"), text: $nameInput)
        .font(.system(size: 16))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
          RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray6))
        )
        .onChange(of: nameInput) { _, newValue in
          if newValue.count > 20 {
            nameInput = String(newValue.prefix(20))
          }
        }
        .disabled(isWriting || isSuccess)

      // Status feedback
      if isSuccess {
        HStack(spacing: 6) {
          Image(systemName: "checkmark.circle.fill")
            .foregroundColor(.green)
          Text(String(localized: "命名成功"))
            .foregroundColor(.green)
        }
        .font(.system(size: 15, weight: .semibold))
        .transition(.opacity)
      }

      Button(action: onWrite) {
        HStack(spacing: 8) {
          if isWriting {
            ProgressView()
              .progressViewStyle(.circular)
              .tint(.white)
              .scaleEffect(0.8)
          }
          Text(isWriting
            ? String(localized: "靠卡中...")
            : String(localized: "靠卡寫入"))
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(
          Capsule()
            .fill(
              nameInput.trimmingCharacters(in: .whitespaces).isEmpty || isWriting || isSuccess
                ? Color.gray.opacity(0.4)
                : themeColor
            )
        )
      }
      .disabled(nameInput.trimmingCharacters(in: .whitespaces).isEmpty || isWriting || isSuccess)

      Text(String(localized: "最多 20 個字"))
        .font(.caption)
        .foregroundColor(.secondary)
    }
    .padding(24)
    .presentationDetents([.height(300)])
    .animation(.easeOut(duration: 0.2), value: isSuccess)
  }
}

#Preview {
  SettingsTabView(onEmergencyTapped: {})
    .environmentObject(ThemeManager.shared)
    .environmentObject(StrategyManager())
    .environmentObject(OnboardingManager.shared)
    .environmentObject(SubscriptionManager.shared)
}
