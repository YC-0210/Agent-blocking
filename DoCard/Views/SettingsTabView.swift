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
  @AppStorage("analyticsEnabled", store: UserDefaults(suiteName: "group.DO.version3"))
  private var analyticsEnabled = true

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

  private let nfcScanner = NFCScannerUtil()
  private let nfcRenameScanner = NFCScannerUtil()

  var onEmergencyTapped: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        // MARK: - 訂閱 Section
        Section {
          Button(action: { showPaywall = true }) {
            HStack {
              Image(systemName: subscriptionManager.isPremium ? "crown.fill" : "crown")
                .foregroundStyle(.orange)
                .font(.title3)

              VStack(alignment: .leading, spacing: 2) {
                Text(subscriptionManager.isPremium
                  ? String(localized: "Premium 會員")
                  : String(localized: "升級 Premium"))
                  .font(.headline)
                  .foregroundStyle(.primary)
                Text(subscriptionManager.isPremium
                  ? String(localized: "已啟用所有功能")
                  : String(localized: "守護最多 50 個 App 與排程自動化"))
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }

              Spacer()

              if !subscriptionManager.isPremium {
                Image(systemName: "chevron.right")
                  .foregroundStyle(.secondary)
              }
            }
          }
        } header: {
          Text(String(localized: "訂閱"))
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        // MARK: - 封鎖設定 Section
        Section {
          Button(action: startPairing) {
            HStack {
              Image(systemName: "wave.3.right.circle.fill")
                .foregroundStyle(onboardingManager.canPairMoreCards ? themeManager.themeColor : .secondary)
                .font(.title3)

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

          // Rename card row — only shown when at least one card is paired
          if onboardingManager.isDOCardPaired {
            Button(action: { showRenameSheet = true }) {
              HStack {
                Image(systemName: "pencil.circle.fill")
                  .foregroundStyle(themeManager.themeColor)
                  .font(.title3)

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

          CustomToggle(
            title: String(localized: "允許免卡開始"),
            description: String(localized: "在主畫面顯示「直接開始」按鈕，不靠卡也能開始專注"),
            isOn: $allowCardlessStart
          )
        } header: {
          Text(String(localized: "DO Card 設定"))
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        // MARK: - 連動裝置 Section (Premium-gated)
        Section {
          // Mac sync is a Premium feature in v2.0.6+ — entry routes through
          // a paywall check. Premium users flip `navigateToMacPairing` to
          // open `MacPairingView` via `.navigationDestination`; free users
          // see PremiumUpgradeView via the existing `showPaywall` sheet.
          // UI is intentionally unchanged so the row still looks tappable
          // for free users (mirrors ScheduleTabView's pattern: tap a free
          // card → paywall sheet).
          Button {
            if subscriptionManager.isPremium {
              navigateToMacPairing = true
            } else {
              showPaywall = true
            }
          } label: {
            HStack {
              Image(systemName: "laptopcomputer.and.iphone")
                .foregroundStyle(themeManager.themeColor)
                .font(.title3)

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
          .navigationDestination(isPresented: $navigateToMacPairing) {
            MacPairingView()
          }
        } header: {
          Text(String(localized: "連動裝置"))
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        // MARK: - 動力相簿 Section
        Section {
          Button(action: { showGalleryEditor = true }) {
            HStack {
              Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(themeManager.themeColor)
                .font(.title3)

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
        } header: {
          Text(String(localized: "動力相簿"))
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        // MARK: - 通知與提醒 Section
        Section {
          CustomToggle(
            title: String(localized: "動態島 / 鎖定畫面顯示"),
            description: String(
              localized: "專注時在動態島和鎖定畫面即時顯示計時與狀態"),
            isOn: $enableLiveActivity
          )

          CustomToggle(
            title: String(localized: "完成後詢問是否分享"),
            description: String(
              localized: "專注時段滿 30 分鐘且正常結束時，跳出分享提示"),
            isOn: $askToShareAfterSession
          )

          CustomToggle(
            title: String(localized: "提醒"),
            description: String(
              localized: "專注結束後發送提醒通知"),
            isOn: $enableReminder
          )

        } header: {
          Text(String(localized: "通知與提醒"))
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        // MARK: - 資料與隱私 Section
        Section {
          CustomToggle(
            title: String(localized: "匿名使用統計"),
            description: String(
              localized: "傳送匿名的使用統計，協助我們改善 App。不含任何個人資料，可隨時關閉。"),
            isOn: $analyticsEnabled
          )
        } header: {
          Text(String(localized: "資料與隱私"))
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        // MARK: - Emergency Section (untouched — always-free safety feature)
        if strategyManager.isBlocking {
          Section {
            Button(action: onEmergencyTapped) {
              HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                  .foregroundStyle(.red)
                  .font(.title3)

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
          } header: {
            Text(String(localized: "緊急"))
          }
          .listRowBackground(Color(.systemGray6).opacity(0.08))
        }

      }
      .scrollContentBackground(.hidden)
      .navigationTitle(String(localized: "設定"))
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
