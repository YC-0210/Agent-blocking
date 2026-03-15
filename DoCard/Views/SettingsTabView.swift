import SwiftData
import SwiftUI

struct SettingsTabView: View {
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var strategyManager: StrategyManager
  @EnvironmentObject var onboardingManager: OnboardingManager
  @Environment(\.modelContext) private var modelContext

  @AppStorage("globalEnableLiveActivity") private var enableLiveActivity: Bool = false
  @AppStorage("globalEnableReminder") private var enableReminder: Bool = false
  @AppStorage("globalEnableBreaks") private var enableBreaks: Bool = false

  @State private var isPairing = false
  @State private var pairSuccess = false

  private let nfcScanner = NFCScannerUtil()

  var onEmergencyTapped: () -> Void

  var body: some View {
    NavigationStack {
      Form {
        // MARK: - DO Card Section
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
            .padding(.vertical, 8)
          }
          .disabled(isPairing || !onboardingManager.canPairMoreCards)

          if let doCardURL = URL(string: "https://www.do-card.online/") {
            Link(destination: doCardURL) {
              HStack {
                Image(systemName: "creditcard.fill")
                  .foregroundStyle(themeManager.themeColor)
                  .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                  Text(String(localized: "購買 DO Card"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                  Text(String(localized: "取得您的實體 DO Card"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 8)
            }
          }
        } header: {
          Text(String(localized: "DO Card"))
        }

        // MARK: - Notifications Section
        Section {
          CustomToggle(
            title: String(localized: "即時動態"),
            description: String(
              localized: "在鎖定畫面顯示即時動態與勵志語錄"),
            isOn: $enableLiveActivity
          )

          CustomToggle(
            title: String(localized: "提醒"),
            description: String(
              localized: "專注結束後發送提醒通知"),
            isOn: $enableReminder
          )
        } header: {
          Text(String(localized: "通知"))
        }

        // MARK: - Focus Section
        Section {
          CustomToggle(
            title: String(localized: "休息功能"),
            description: String(
              localized: "專注期間允許短暫休息"),
            isOn: $enableBreaks
          )
        } header: {
          Text(String(localized: "專注"))
        }

        // MARK: - Emergency Section
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
                  Text(String(localized: "立即解除所有封鎖"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 8)
            }
          } header: {
            Text(String(localized: "緊急"))
          }
        }
      }
      .navigationTitle(String(localized: "設定"))
      .onChange(of: enableLiveActivity) { _, newValue in
        syncLiveActivityToAllProfiles(enabled: newValue)
      }
      .onChange(of: enableReminder) { _, newValue in
        syncReminderToAllProfiles(enabled: newValue)
      }
      .onChange(of: enableBreaks) { _, newValue in
        syncBreaksToAllProfiles(enabled: newValue)
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
      print("Failed to sync Live Activity setting: \(error.localizedDescription)")
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
      print("Failed to sync Reminder setting: \(error.localizedDescription)")
    }
  }

  private func syncBreaksToAllProfiles(enabled: Bool) {
    do {
      let profiles = try BlockedProfiles.fetchProfiles(in: modelContext)
      for profile in profiles {
        profile.enableBreaks = enabled
        BlockedProfiles.updateSnapshot(for: profile)
      }
      try modelContext.save()
    } catch {
      print("Failed to sync Breaks setting: \(error.localizedDescription)")
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
      print("Failed to update profiles with new DO Card: \(error.localizedDescription)")
    }
  }
}

#Preview {
  SettingsTabView(onEmergencyTapped: {})
    .environmentObject(ThemeManager.shared)
    .environmentObject(StrategyManager())
    .environmentObject(OnboardingManager.shared)
}
