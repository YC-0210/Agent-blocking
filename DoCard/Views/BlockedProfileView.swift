import FamilyControls
import Foundation
import SwiftData
import SwiftUI

// Alert identifier for managing multiple alerts
struct AlertIdentifier: Identifiable {
  enum AlertType {
    case error
    case deleteProfile
    case overwriteNFCWarning
  }

  let id: AlertType
  var errorMessage: String?
}

struct BlockedProfileView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss

  @EnvironmentObject private var themeManager: ThemeManager
  @EnvironmentObject private var nfcWriter: NFCWriter
  @EnvironmentObject private var strategyManager: StrategyManager
  @EnvironmentObject private var onboardingManager: OnboardingManager

  // If profile is nil, we're creating a new profile
  var profile: BlockedProfiles?

  @AppStorage("globalEnableLiveActivity") private var enableLiveActivity: Bool = false
  @AppStorage("globalEnableReminder") private var enableReminder: Bool = false

  @State private var name: String = ""
  @State private var enableBreaks: Bool = false
  @State private var breakTimeInMinutes: Int = 15
  @State private var reminderTimeInMinutes: Int = 15
  @State private var customReminderMessage: String
  @State private var enableAllowMode: Bool = false
  @State private var enableAllowModeDomain: Bool = false
  @State private var enableSafariBlocking: Bool = true
  @State private var domains: [String] = []

  @State private var physicalUnblockNFCTagIds: [String]?

  // Sheet for activity picker
  @State private var showingActivityPicker = false

  // Sheet for app advanced settings
  @State private var showingAppAdvancedSettings = false

  // Sheet for strategy advanced settings
  @State private var showingStrategyAdvancedSettings = false

  // Sheet for domain picker
  @State private var showingDomainPicker = false

  // Alert management
  @State private var alertIdentifier: AlertIdentifier?

  // NFC write URL storage for overwrite warning
  @State private var pendingNFCWriteURL: String?

  // Alert for timer ↔ schedule conflict
  @State private var showTimerScheduleConflictAlert = false

  // Alert for cloning
  @State private var showingClonePrompt = false
  @State private var cloneName: String = ""

  // Sheet for insights modal
  @State private var showingInsights = false

  // Sheet for sessions modal
  @State private var showingSessions = false


  @State private var selectedActivity = FamilyActivitySelection(includeEntireCategory: true)
  @State private var selectedStrategy: BlockingStrategy? = nil

  // Tutorial steps 3 & 4
  @State private var strategyTapCount: Int = 0
  @State private var step3PillTapped: Bool = false
  @State private var step4Interacted: Bool = false
  @State private var step4Completed: Bool = false
  @State private var strategyTopSectionHeight: CGFloat = 0
  @State private var strategyBottomSectionHeight: CGFloat = 0

  private var isEditing: Bool {
    profile != nil
  }

  private var isBlocking: Bool {
    strategyManager.activeSessionStatus.isBlocking
  }

  init(profile: BlockedProfiles? = nil, initialName: String = "") {
    self.profile = profile
    _name = State(initialValue: profile?.name ?? initialName)
    _selectedActivity = State(
      initialValue: profile?.selectedActivity ?? FamilyActivitySelection(includeEntireCategory: true)
    )
    _enableBreaks = State(
      initialValue: profile?.enableBreaks ?? false
    )
    _breakTimeInMinutes = State(
      initialValue: profile?.breakTimeInMinutes ?? 15
    )
    _enableAllowMode = State(
      initialValue: profile?.enableAllowMode ?? false
    )
    _enableAllowModeDomain = State(
      initialValue: profile?.enableAllowModeDomains ?? false
    )
    _enableSafariBlocking = State(
      initialValue: profile?.enableSafariBlocking ?? true
    )
    _reminderTimeInMinutes = State(
      initialValue: Int(profile?.reminderTimeInSeconds ?? 900) / 60
    )
    _customReminderMessage = State(
      initialValue: profile?.customReminderMessage ?? ""
    )
    _domains = State(
      initialValue: profile?.domains ?? []
    )
    let globalTagIds = OnboardingManager.shared.pairedDOCardTagIds
    _physicalUnblockNFCTagIds = State(
      initialValue: profile?.physicalUnblockNFCTagIds ?? (globalTagIds.isEmpty ? nil : globalTagIds)
    )

    if let profileStrategyId = profile?.blockingStrategyId {
      _selectedStrategy = State(
        initialValue:
          StrategyManager
          .getStrategyFromId(id: profileStrategyId)
      )
    } else {
      _selectedStrategy = State(initialValue: NFCBlockingStrategy())
    }
  }

  private var isClassicMode: Bool {
    selectedStrategy?.getIdentifier() == NFCBlockingStrategy.id
  }

  private var strategyDescription: String {
    if isClassicMode {
      return String(localized: "直接開啟專注模式，需要靠卡才能停止")
    } else {
      return String(localized: "設定計時時間，輕觸 DO Card 提前解鎖或等待計時結束")
    }
  }

  private var appCountText: String {
    FamilyActivityUtil.formatAppCount(selectedActivity)
  }

  private var hasAppsSelected: Bool {
    FamilyActivityUtil.countSelectedActivities(selectedActivity, allowMode: enableAllowMode) > 0
  }

  private var websiteCount: Int {
    domains.count
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 16) {
          nameRow
          strategyCard
          Spacer(minLength: 40)
          saveButton
          deleteButton
        }
        .padding(.top, 16)
      }
      .background(Color(.systemGroupedBackground))
      .overlay {
        if onboardingManager.tutorialStep == 2 {
          TutorialStep2Overlay()
        }
      }
      .overlay {
        if onboardingManager.tutorialStep == 3 {
          TutorialStep3Overlay(
            topSectionHeight: strategyTopSectionHeight,
            pillTapped: step3PillTapped,
            onDimmedTap: {
              if step3PillTapped {
                step3PillTapped = false
                onboardingManager.advanceTutorial()
              }
            }
          )
          .allowsHitTesting(true)
        }
      }
      .overlay {
        if onboardingManager.tutorialStep == 4, !step4Completed {
          TutorialStep4Overlay(
            topSectionHeight: strategyTopSectionHeight,
            bottomSectionHeight: strategyBottomSectionHeight,
            interacted: step4Interacted,
            onDimmedTap: {
              if step4Interacted {
                step4Interacted = false
                // Don't advance to step 5 here — keep step at 4 but dismiss overlay.
                // HomeView's onDismiss will advance to step 5 after sheet closes.
                step4Completed = true
              }
            }
          )
          .allowsHitTesting(true)
        }
      }
      .onChange(of: strategyTapCount) { _, _ in
        if onboardingManager.tutorialStep == 3 {
          withAnimation(.easeInOut(duration: 0.3)) {
            step3PillTapped = true
          }
        }
      }
      .onChange(of: showingActivityPicker) { _, newValue in
        if onboardingManager.tutorialStep == 4, !newValue, !step4Interacted {
          withAnimation(.easeInOut(duration: 0.3)) {
            step4Interacted = true
          }
        }
      }
      .onChange(of: showingDomainPicker) { _, newValue in
        if onboardingManager.tutorialStep == 4, !newValue, !step4Interacted {
          withAnimation(.easeInOut(duration: 0.3)) {
            step4Interacted = true
          }
        }
      }
      .onChange(of: enableAllowMode) {
        _,
        newValue in
        selectedActivity = FamilyActivitySelection(
          includeEntireCategory: true
        )
      }
      .navigationTitle(isEditing ? String(localized: "編輯模式") : String(localized: "新增模式"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "chevron.left")
          }
          .accessibilityLabel(String(localized: "返回"))
        }
      }
      .sheet(isPresented: $showingActivityPicker) {
        AppPicker(
          selection: $selectedActivity,
          isPresented: $showingActivityPicker,
          allowMode: enableAllowMode
        )
      }
      .sheet(isPresented: $showingAppAdvancedSettings) {
        AppAdvancedSettingsView(
          enableAllowMode: $enableAllowMode,
          enableSafariBlocking: $enableSafariBlocking,
          isDisabled: isBlocking
        )
      }
      .sheet(isPresented: $showingStrategyAdvancedSettings) {
        StrategyAdvancedSettingsView(
          isDisabled: isBlocking
        )
      }
      .sheet(isPresented: $showingDomainPicker) {
        DomainPicker(
          domains: $domains,
          isPresented: $showingDomainPicker
        )
      }
      .sheet(isPresented: $showingInsights) {
        if let validProfile = profile {
          ProfileInsightsView(profile: validProfile)
        }
      }
      .sheet(isPresented: $showingSessions) {
        if let validProfile = profile {
          BlockedProfileSessionsView(profile: validProfile)
        }
      }
      .background(
        TextFieldAlert(
          isPresented: $showingClonePrompt,
          title: String(localized: "複製模式"),
          message: nil,
          text: $cloneName,
          placeholder: String(localized: "模式名稱"),
          confirmTitle: String(localized: "建立"),
          cancelTitle: String(localized: "取消"),
          onConfirm: { enteredName in
            let trimmed = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            do {
              if let source = profile {
                _ = try BlockedProfiles.cloneProfile(
                  source, in: modelContext, newName: trimmed)
              }
            } catch {
              showError(message: error.localizedDescription)
            }
          }
        )
      )
      .alert(item: $alertIdentifier) { alert in
        switch alert.id {
        case .error:
          return Alert(
            title: Text(String(localized: "錯誤")),
            message: Text(alert.errorMessage ?? String(localized: "發生未知錯誤")),
            dismissButton: .default(Text(String(localized: "好")))
          )
        case .deleteProfile:
          return Alert(
            title: Text(String(localized: "刪除模式")),
            message: Text(String(localized: "確定要刪除此模式嗎？此操作無法復原。")),
            primaryButton: .cancel(),
            secondaryButton: .destructive(Text(String(localized: "刪除"))) {
              dismiss()
              if let profileToDelete = profile {
                do {
                  strategyManager.handleProfileDeletion(profileToDelete, context: modelContext)
                  try BlockedProfiles.deleteProfile(profileToDelete, in: modelContext)
                } catch {
                  showError(message: error.localizedDescription)
                }
              }
            }
          )
        case .overwriteNFCWarning:
          return Alert(
            title: Text(String(localized: "警告：卡片標籤已設定")),
            message: Text(String(localized: "寫入此標籤將覆蓋其現有資料。如果這是你之前設定用於解鎖的標籤，將無法再使用它解鎖模式。是否繼續？")),
            primaryButton: .cancel(),
            secondaryButton: .default(Text(String(localized: "繼續"))) {
              if let url = pendingNFCWriteURL {
                nfcWriter.writeURL(url)
              }
              pendingNFCWriteURL = nil
            }
          )
        }
      }
      .alert(String(localized: "無法切換"), isPresented: $showTimerScheduleConflictAlert) {
        Button(String(localized: "好"), role: .cancel) {}
      } message: {
        Text(String(localized: "計時模式無法與排程同時使用，請先至排程頁面刪除排程"))
      }
    }
  }

  // MARK: - Name Row
  private var nameRow: some View {
    HStack {
      Text(String(localized: "名稱"))
        .foregroundColor(.secondary)
      Spacer()
      TextField(String(localized: "模式名稱"), text: $name)
        .textContentType(.none)
        .multilineTextAlignment(.trailing)
        .onSubmit {
          if onboardingManager.tutorialStep == 2, !name.isEmpty {
            onboardingManager.advanceTutorial()
          }
        }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 16)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .padding(.horizontal, 16)
  }

  // MARK: - Strategy Card
  private var strategyCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      strategyTopSection
      strategyBottomSection
    }
    .padding(20)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(Color(.secondarySystemGroupedBackground))
    )
    .padding(.horizontal, 16)
  }

  private var strategyBottomSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      appsRow
      appIcons
      strategyDivider
      websitesRow
    }
    .background(
      GeometryReader { geo in
        Color.clear
          .onAppear { strategyBottomSectionHeight = geo.size.height }
          .onChange(of: geo.size.height) { _, h in strategyBottomSectionHeight = h }
      }
    )
  }

  private var strategyTopSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      strategyHeader
      strategyToggle
      strategyDivider
      Text(strategyDescription)
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
    .background(
      GeometryReader { geo in
        Color.clear
          .onAppear { strategyTopSectionHeight = geo.size.height }
          .onChange(of: geo.size.height) { _, h in strategyTopSectionHeight = h }
      }
    )
  }

  private var strategyHeader: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(String(localized: "選擇專注策略"))
        .font(.headline)
        .fontWeight(.bold)
      Text(String(localized: "選擇在這個模式下，你的專注方式"))
        .font(.subheadline)
        .foregroundColor(.secondary)
    }
  }

  private var strategyToggle: some View {
    HStack(spacing: 0) {
      strategyPill(
        title: String(localized: "經典模式"),
        isSelected: isClassicMode
      ) {
        if !isBlocking {
          selectedStrategy = NFCBlockingStrategy()
          strategyTapCount += 1
        }
      }
      strategyPill(
        title: String(localized: "計時模式"),
        isSelected: !isClassicMode
      ) {
        if !isBlocking {
          // Prevent switching to timer mode if profile has any active schedule
          if profile?.hasActiveSchedules == true {
            showTimerScheduleConflictAlert = true
            return
          }
          selectedStrategy = NFCTimerBlockingStrategy()
          strategyTapCount += 1
        }
      }
    }
    .background(
      RoundedRectangle(cornerRadius: 12)
        .fill(Color(.systemGroupedBackground))
    )
    .opacity(isBlocking ? 0.5 : 1)
  }

  private var strategyDivider: some View {
    Rectangle()
      .fill(Color(.separator))
      .frame(height: 0.5)
      .padding(.vertical, 4)
  }

  private var appsRow: some View {
    Button(action: { showingActivityPicker = true }) {
      HStack(spacing: 12) {
        Image(systemName: "square.on.square")
          .font(.body)
          .foregroundColor(.primary)
          .frame(width: 24, height: 24)
        Text(String(localized: "App"))
          .foregroundColor(.primary)
        Spacer()
        Text(appCountText)
          .foregroundColor(.secondary)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .disabled(isBlocking)
  }

  @ViewBuilder
  private var appIcons: some View {
    if !selectedActivity.applicationTokens.isEmpty {
      HStack(spacing: 4) {
        ForEach(Array(selectedActivity.applicationTokens.prefix(6)), id: \.self) { token in
          Label(token)
            .labelStyle(.iconOnly)
            .scaleEffect(1.4)
            .frame(width: 26, height: 26)
        }
      }
      .padding(.leading, 36)
    }
  }

  private var websitesRow: some View {
    Button(action: { showingDomainPicker = true }) {
      HStack(spacing: 12) {
        Image(systemName: "globe")
          .font(.body)
          .foregroundColor(.primary)
          .frame(width: 24, height: 24)
        Text(String(localized: "網站"))
          .foregroundColor(.primary)
        Spacer()
        let countText: String = websiteCount > 0 ? "\(websiteCount)" : String(localized: "無")
        Text(countText)
          .foregroundColor(.secondary)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .disabled(isBlocking)
  }

  // MARK: - Save Button
  private var saveButton: some View {
    Button(action: { saveProfile() }) {
      Text(String(localized: "儲存模式"))
        .font(.headline)
        .fontWeight(.semibold)
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(name.isEmpty || isBlocking ? Color.gray.opacity(0.5) : themeManager.themeColor)
        )
    }
    .disabled(name.isEmpty || isBlocking)
    .padding(.horizontal, 16)
  }

  // MARK: - Delete Button
  @ViewBuilder
  private var deleteButton: some View {
    if isEditing && !isBlocking {
      Button(action: {
        alertIdentifier = AlertIdentifier(id: .deleteProfile)
      }) {
        Text(String(localized: "刪除模式"))
          .font(.subheadline)
          .foregroundColor(.secondary)
      }
      .padding(.top, 4)
      .padding(.bottom, 16)
    }
  }

  // MARK: - Strategy Pill Button
  @ViewBuilder
  private func strategyPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline)
        .fontWeight(isSelected ? .semibold : .regular)
        .foregroundColor(isSelected ? .white : .secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
          RoundedRectangle(cornerRadius: 10)
            .fill(isSelected ? themeManager.themeColor : Color.clear)
        )
    }
    .buttonStyle(.plain)
  }

  private func showError(message: String) {
    alertIdentifier = AlertIdentifier(id: .error, errorMessage: message)
  }

  private func writeProfile() {
    if let profileToWrite = profile {
      let url = BlockedProfiles.getProfileDeepLink(profileToWrite)

      // Check if a physical unblock NFC tag is already set
      if profileToWrite.physicalUnblockNFCTagIds != nil {
        pendingNFCWriteURL = url
        alertIdentifier = AlertIdentifier(id: .overwriteNFCWarning)
      } else {
        nfcWriter.writeURL(url)
      }
    }
  }

  private func saveProfile() {
    do {
      // Calculate reminder time in seconds or nil if disabled
      let reminderTimeSeconds: UInt32? =
        enableReminder ? UInt32(reminderTimeInMinutes * 60) : nil

      if let existingProfile = profile {
        // Update existing profile
        let updatedProfile = try BlockedProfiles.updateProfile(
          existingProfile,
          in: modelContext,
          name: name,
          selection: selectedActivity,
          blockingStrategyId: selectedStrategy?.getIdentifier(),
          enableLiveActivity: enableLiveActivity,
          reminderTime: reminderTimeSeconds,
          customReminderMessage: customReminderMessage,
          enableBreaks: enableBreaks,
          breakTimeInMinutes: breakTimeInMinutes,
          enableAllowMode: enableAllowMode,
          enableAllowModeDomains: enableAllowModeDomain,
          enableSafariBlocking: enableSafariBlocking,
          domains: domains,
          physicalUnblockNFCTagIds: physicalUnblockNFCTagIds
        )

        // Re-register schedule restrictions for existing schedules
        try DeviceActivityCenterUtil.scheduleTimerActivities(for: updatedProfile)
      } else {
        let newProfile = try BlockedProfiles.createProfile(
          in: modelContext,
          name: name,
          selection: selectedActivity,
          blockingStrategyId: selectedStrategy?
            .getIdentifier() ?? NFCBlockingStrategy.id,
          enableLiveActivity: enableLiveActivity,
          reminderTimeInSeconds: reminderTimeSeconds,
          customReminderMessage: customReminderMessage,
          enableBreaks: enableBreaks,
          breakTimeInMinutes: breakTimeInMinutes,
          enableAllowMode: enableAllowMode,
          enableAllowModeDomains: enableAllowModeDomain,
          enableSafariBlocking: enableSafariBlocking,
          domains: domains,
          physicalUnblockNFCTagIds: physicalUnblockNFCTagIds
        )

        // Register schedule restrictions (empty for new profiles)
        try DeviceActivityCenterUtil.scheduleTimerActivities(for: newProfile)
      }

      dismiss()
    } catch {
      alertIdentifier = AlertIdentifier(id: .error, errorMessage: error.localizedDescription)
    }
  }
}

// MARK: - Dimmed Area Shape (full rect with cutout hole for hit testing)

private struct DimmedAreaShape: Shape {
  let cutoutRect: CGRect
  let cornerRadius: CGFloat

  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.addRect(rect)
    path.addRoundedRect(in: cutoutRect, cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
    return path
  }
}

// MARK: - Tutorial Step 2 Overlay

private struct TutorialStep2Overlay: View {
  // Name row in the ScrollView: 16pt top padding, then the row (~54pt height)
  private let nameRowTop: CGFloat = 16
  private let nameRowHeight: CGFloat = 54

  private var cutoutRect: CGRect {
    CGRect(x: 16, y: nameRowTop, width: UIScreen.main.bounds.width - 32, height: nameRowHeight)
  }

  var body: some View {
    GeometryReader { overlayGeo in
      Canvas { context, size in
        // Draw full dim
        context.fill(
          Path(CGRect(origin: .zero, size: size)),
          with: .color(.black.opacity(0.9))
        )
        // Punch out the name row
        context.blendMode = .destinationOut
        context.fill(
          Path(roundedRect: cutoutRect, cornerRadius: 16),
          with: .color(.white)
        )
      }
      .compositingGroup()
      // Block taps on dimmed area, allow taps through the cutout to the name TextField
      .contentShape(
        DimmedAreaShape(cutoutRect: cutoutRect, cornerRadius: 16),
        eoFill: true
      )
      .onTapGesture {
        // Consume taps on dimmed area — do nothing
      }
      .overlay(alignment: .top) {
        VStack(spacing: 6) {
          Image(systemName: "arrow.up")
            .font(.system(size: 20, weight: .medium))
            .foregroundColor(.white)
            .padding(.bottom, 2)

          Text(String(localized: "步驟二"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ThemeManager.shared.themeColor)

          Text(String(localized: "為你的模式取名，完成後點選鍵盤輸入鍵\n模式名稱舉例：「我要變強」\n或是「專心唸國文」"))
            .font(.system(size: 17, weight: .medium))
            .foregroundColor(.white)
        }
        .allowsHitTesting(false)
        .padding(.top, nameRowTop + nameRowHeight + 16)
      }
    }
  }
}

// MARK: - Tutorial Step 3 Overlay

private struct TutorialStep3Overlay: View {
  // Layout: VStack(.top, 16) → nameRow(~54pt) → spacing(16) → strategyCard
  // nameRow: .padding(.vertical, 16) + single-line HStack text ≈ 54pt
  private let strategyCardTop: CGFloat = 16 + 54 + 16  // 86pt

  let topSectionHeight: CGFloat  // height of strategyTopSection (header + toggle + divider + description)
  let pillTapped: Bool  // whether user has tapped a strategy pill
  let onDimmedTap: () -> Void
  @State private var arrowBounce = false

  var body: some View {
    GeometryReader { overlayGeo in
      // Card padding(20) top + topSection content + small bottom padding
      let cutoutHeight = 20 + topSectionHeight + 4
      let cutoutRect = CGRect(
        x: 16,
        y: strategyCardTop,
        width: overlayGeo.size.width - 32,
        height: cutoutHeight
      )

      Canvas { context, size in
        // Draw full dim
        context.fill(
          Path(CGRect(origin: .zero, size: size)),
          with: .color(.black.opacity(0.9))
        )
        // Punch out the strategy card
        context.blendMode = .destinationOut
        context.fill(
          Path(roundedRect: cutoutRect, cornerRadius: 16),
          with: .color(.white)
        )
      }
      .compositingGroup()
      // Only capture taps on the dimmed area (outside cutout)
      .contentShape(
        DimmedAreaShape(cutoutRect: cutoutRect, cornerRadius: 16),
        eoFill: true
      )
      .onTapGesture {
        if pillTapped {
          onDimmedTap()
        }
      }
      .overlay(alignment: .top) {
        VStack(spacing: 6) {
          if pillTapped {
            // Phase 2: user tapped a pill, show "tap to continue"
            Text(String(localized: "點擊繼續"))
              .font(.system(size: 17, weight: .medium))
              .foregroundColor(.white.opacity(0.8))
              .transition(.opacity)
          } else {
            // Phase 1: prompt to tap a pill
            Image(systemName: "arrow.up")
              .font(.system(size: 20, weight: .medium))
              .foregroundColor(.white)
              .offset(y: arrowBounce ? -2 : 6)
              .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: arrowBounce
              )
              .padding(.bottom, 2)

            Text(String(localized: "步驟三"))
              .font(.system(size: 14, weight: .semibold))
              .foregroundColor(ThemeManager.shared.themeColor)

            Text(String(localized: "選擇經典模式或計時模式"))
              .font(.system(size: 17, weight: .medium))
              .foregroundColor(.white)
          }
        }
        .allowsHitTesting(false)
        .padding(.top, cutoutRect.maxY + 16)
      }
    }
    .onAppear {
      arrowBounce = true
    }
  }
}

// MARK: - Tutorial Step 4 Overlay

private struct TutorialStep4Overlay: View {
  // Same layout constants as Step 3
  private let strategyCardTop: CGFloat = 16 + 54 + 16  // 86pt

  let topSectionHeight: CGFloat
  let bottomSectionHeight: CGFloat
  let interacted: Bool  // whether user has opened App/Website picker
  let onDimmedTap: () -> Void
  @State private var arrowBounce = false

  var body: some View {
    GeometryReader { overlayGeo in
      // Bottom section starts after: card top + padding(20) + topSection + spacing(12)
      // Extend 8pt upward so nothing is clipped above the App row
      let cutoutTop = strategyCardTop + 20 + topSectionHeight + 12 - 8
      // Bottom section height + bottom padding of card + the 8pt extension
      let cutoutHeight = bottomSectionHeight + 20 + 8
      let cutoutRect = CGRect(
        x: 16,
        y: cutoutTop,
        width: overlayGeo.size.width - 32,
        height: cutoutHeight
      )

      Canvas { context, size in
        // Draw full dim
        context.fill(
          Path(CGRect(origin: .zero, size: size)),
          with: .color(.black.opacity(0.9))
        )
        // Punch out the app/website section
        context.blendMode = .destinationOut
        context.fill(
          Path(roundedRect: cutoutRect, cornerRadius: 16),
          with: .color(.white)
        )
      }
      .compositingGroup()
      // Only capture taps on the dimmed area (outside cutout)
      .contentShape(
        DimmedAreaShape(cutoutRect: cutoutRect, cornerRadius: 16),
        eoFill: true
      )
      .onTapGesture {
        if interacted {
          onDimmedTap()
        }
      }
      .overlay(alignment: .top) {
        Group {
          if interacted {
            // Phase 2: show "tap to continue" below the highlight
            Text(String(localized: "點擊繼續"))
              .font(.system(size: 17, weight: .medium))
              .foregroundColor(.white.opacity(0.8))
              .padding(.top, cutoutRect.maxY + 20)
              .transition(.opacity)
          } else {
            // Phase 1: step text + arrow above the highlight
            VStack(spacing: 6) {
              Text(String(localized: "步驟四"))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(ThemeManager.shared.themeColor)

              Text(String(localized: "選擇要鎖定的App 跟 網站"))
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)

              Image(systemName: "arrow.down")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.white)
                .offset(y: arrowBounce ? 6 : -2)
                .animation(
                  .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                  value: arrowBounce
                )
                .padding(.top, 2)
            }
            .padding(.top, cutoutTop - 80)
          }
        }
        .allowsHitTesting(false)
      }
    }
    .onAppear {
      arrowBounce = true
    }
  }
}

// Preview provider for SwiftUI previews
#Preview {
  BlockedProfileView()
    .environmentObject(ThemeManager.shared)
    .environmentObject(NFCWriter())
    .environmentObject(StrategyManager())
    .environmentObject(OnboardingManager.shared)
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}

#Preview {
  let previewProfile = BlockedProfiles(
    name: "test",
    selectedActivity: FamilyActivitySelection(),
    reminderTimeInSeconds: 60
  )

  BlockedProfileView(profile: previewProfile)
    .environmentObject(ThemeManager.shared)
    .environmentObject(NFCWriter())
    .environmentObject(StrategyManager())
    .environmentObject(OnboardingManager.shared)
    .modelContainer(for: BlockedProfiles.self, inMemory: true)
}
