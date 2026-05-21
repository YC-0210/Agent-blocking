import FamilyControls
import SwiftData
import SwiftUI

struct HomeView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.openURL) var openURL

  @Environment(\.scenePhase) private var scenePhase

  @EnvironmentObject var requestAuthorizer: RequestAuthorizer
  @EnvironmentObject var strategyManager: StrategyManager
  @EnvironmentObject var navigationManager: NavigationManager
  @EnvironmentObject var ratingManager: RatingManager
  @EnvironmentObject var onboardingManager: OnboardingManager
  @EnvironmentObject var coFocusManager: CoFocusManager
  @EnvironmentObject var whatsNewManager: WhatsNewManager

  // What's New — remembers which tab to switch to after sheet dismisses
  @State private var whatsNewDestination: Tab? = nil

  // Profile management
  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private
    var profiles: [BlockedProfiles]
  @State private var isProfileListPresent = false

  // New profile view
  @State private var showNewProfileView = false
  @State private var newProfileInitialName: String = ""

  // Edit profile
  @State private var profileToEdit: BlockedProfiles? = nil

  // Emergency View
  @State private var showEmergencyView = false

  // Navigate to profile
  @State private var navigateToProfileId: UUID? = nil

  // Alerts
  @State private var showingAlert = false
  @State private var alertTitle = ""
  @State private var alertMessage = ""

  // One-time analytics disclosure (opt-out; default on)
  @State private var showAnalyticsDisclosure = false

  // Confetti celebration state
  @State private var showConfetti = false
  @State private var wasBlocking = false

  // Saved time banner
  @State private var showSavedTimeBanner = false

  // Share session full-screen preview (presented after user taps "分享" in the prompt sheet)
  @State private var shareSessionToPresent: ShareableSession? = nil

  @Query(
    filter: #Predicate<BlockedProfileSession> { $0.endTime != nil },
    sort: \BlockedProfileSession.endTime,
    order: .reverse
  ) private var allCompletedSessions: [BlockedProfileSession]

  private static let savedTimeBannerIntervalKey = "lastSavedTimeBannerDate"
  private static let bannerInterval: TimeInterval = 14 * 24 * 60 * 60  // 14 days

  // Tab selection
  @State private var selectedTab: Tab = .doMain

  enum Tab: Hashable {
    case doMain
    case schedule
    case coFocus
    case report
    case settings
  }

  var isBlocking: Bool {
    return strategyManager.isBlocking
  }

  var body: some View {
    ZStack {
      TabView(selection: $selectedTab) {
        // Tab 1: DO Main
        DOMainTabView(
          onEditProfile: { profile in
            profileToEdit = profile
          },
          onManageProfiles: {
            isProfileListPresent = true
          },
          onNewProfile: { name in
            newProfileInitialName = name
            showNewProfileView = true
          },
          onNavigateToSettings: {
            selectedTab = .settings
          },
          navigateToProfileId: navigateToProfileId
        )
        .tabItem {
          Label("DO", systemImage: "shield.fill")
        }
        .tag(Tab.doMain)

        // Tab 2: Schedule
        ScheduleTabView()
          .tabItem {
            Label(String(localized: "排程"), systemImage: "calendar.badge.clock")
          }
          .tag(Tab.schedule)

        // Tab 3: 共同專注
        FocusPairingView()
          .tabItem {
            Label(String(localized: "共同專注"), systemImage: "person.2.fill")
          }
          .tag(Tab.coFocus)

        // Tab 4: Report
        ReportView()
          .tabItem {
            Label(String(localized: "週報"), systemImage: "chart.line.uptrend.xyaxis")
          }
          .tag(Tab.report)

        // Tab 5: Settings
        SettingsTabView(onEmergencyTapped: {
          showEmergencyView = true
        })
          .tabItem {
            Label(String(localized: "設定"), systemImage: "gear")
          }
          .tag(Tab.settings)
      }
      .tint(ThemeManager.shared.themeColor)

      // Confetti overlay on session completion
      ConfettiView(
        isActive: $showConfetti,
        themeColor: ThemeManager.shared.themeColor
      )
      .allowsHitTesting(false)

      // Saved time banner
      if showSavedTimeBanner {
        SavedTimeBanner(
          totalSavedTime: totalAllTimeFocusDuration,
          onDismiss: {
            showSavedTimeBanner = false
          }
        )
        .padding(.top, 8)
        .zIndex(1)
      }
    }
    .sheet(
      isPresented: $isProfileListPresent
    ) {
      BlockedProfileListView()
    }
    .onChange(of: navigationManager.profileId) { _, newValue in
      if let profileId = newValue, let url = navigationManager.link {
        toggleSessionFromDeeplink(profileId, link: url)
        navigationManager.clearNavigation()
      }
    }
    .onChange(of: navigationManager.navigateToProfileId) { _, newValue in
      if let profileId = newValue {
        navigateToProfileId = UUID(uuidString: profileId)
        selectedTab = .doMain
        navigationManager.clearNavigation()
      }
    }
    .onChange(of: profiles) { oldValue, newValue in
      if !newValue.isEmpty {
        loadApp()
      }
    }
    .onChange(of: scenePhase) { oldPhase, newPhase in
      if newPhase == .active {
        loadApp()
        checkSavedTimeBanner()
        Task { await coFocusManager.bootstrap() }
      } else if newPhase == .background {
        unloadApp()
      }
    }
    .onChange(of: coFocusManager.shouldFocusTab) { _, newValue in
      // Pairing flipped to .active → surface the tab so both sides see the
      // individual→共同 timer transition.
      guard newValue else { return }
      selectedTab = .coFocus
      coFocusManager.shouldFocusTab = false
    }
    .onReceive(strategyManager.$errorMessage) { errorMessage in
      if let message = errorMessage {
        showErrorAlert(message: message)
      }
    }
    .onChange(of: isBlocking) { _, newValue in
      if !newValue && wasBlocking {
        // Session just ended — celebrate!
        showConfetti = true
      }
      wasBlocking = newValue
    }
    .onAppear {
      wasBlocking = isBlocking
      onAppearApp()
      // "使用他人卡片" users land with no profiles — silently create a starter
      // "讀書模式" so the mode selector is visible and the screen isn't blank.
      // Guard: only fires when no card is paired AND no profiles exist yet.
      // Once the profile exists, profiles.isEmpty is false and this never fires again.
      if !onboardingManager.isDOCardPaired && profiles.isEmpty {
        try? BlockedProfiles.createProfile(in: context, name: String(localized: "讀書模式"))
      }
      // Only run the tutorial for users who own a DO Card.
      // "使用他人卡片" users skip pairing, so isDOCardPaired stays false —
      // the tutorial's Step 5 (NFC tap) would be a dead end for them.
      if onboardingManager.shouldShowTutorial
        && onboardingManager.tutorialStep == 0
        && onboardingManager.isDOCardPaired
      {
        onboardingManager.startTutorial()
      }
      checkSavedTimeBanner()

      // One-time analytics notice (opt-out; default on). Only after onboarding.
      if !onboardingManager.shouldShowOnboarding && !AnalyticsConsent.disclosureShown {
        showAnalyticsDisclosure = true
      }

      // Re-assert distraction-usage monitoring (no-op unless opted in + apps chosen).
      DistractionMonitor.reconcile()
    }
    .sheet(item: $profileToEdit) { profile in
      BlockedProfileView(profile: profile)
    }
    .sheet(
      isPresented: $showNewProfileView,
      onDismiss: {
        // When new profile sheet dismisses during tutorial, advance to step 5
        if onboardingManager.shouldShowTutorial,
           onboardingManager.tutorialStep >= 2,
           onboardingManager.tutorialStep <= 4
        {
          // Use a longer delay to ensure @Query picks up the new profile
          // and DOFocusButton has rendered before showing the step 5 overlay
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onboardingManager.tutorialStep = 5
          }
        }
      }
    ) {
      BlockedProfileView(profile: nil, initialName: newProfileInitialName)
        .environmentObject(onboardingManager)
    }
    .sheet(
      isPresented: $strategyManager.showCustomStrategyView,
      onDismiss: {
        strategyManager.cancelPendingStart()
      }
    ) {
      BlockingStrategyActionView(
        customView: strategyManager.customStrategyView
      )
      .presentationDetents([.medium])
    }
    .sheet(isPresented: $showEmergencyView) {
      EmergencyView()
        .presentationDetents([.height(350)])
    }
    .sheet(item: $strategyManager.pendingShareSession) { session in
      ShareSessionPromptSheet(
        profileName: session.profileName,
        duration: session.duration,
        onShare: {
          shareSessionToPresent = session
          strategyManager.pendingShareSession = nil
        },
        onLater: {
          strategyManager.pendingShareSession = nil
        }
      )
      .presentationDetents([.height(540)])
      .presentationDragIndicator(.visible)
    }
    .sheet(
      isPresented: $whatsNewManager.shouldShowWhatsNew,
      onDismiss: {
        whatsNewManager.markAsSeen()
        if let dest = whatsNewDestination {
          selectedTab = dest
          whatsNewDestination = nil
        }
      }
    ) {
      WhatsNewView(
        onGoToGallery: {
          whatsNewDestination = .doMain
          whatsNewManager.markAsSeen()
        },
        onDismiss: {
          whatsNewManager.markAsSeen()
        }
      )
      .presentationDetents([.height(440)])
      .presentationDragIndicator(.visible)
    }
    .sheet(item: $shareSessionToPresent) { session in
      FocusShareCardView(
        profileName: session.profileName,
        duration: session.duration
      )
      .presentationDetents([.large])
      .presentationDragIndicator(.hidden)
    }
    .alert(alertTitle, isPresented: $showingAlert) {
      Button(String(localized: "OK"), role: .cancel) { dismissAlert() }
    } message: {
      Text(alertMessage)
    }
    .alert(
      String(localized: "匿名使用統計"),
      isPresented: $showAnalyticsDisclosure
    ) {
      Button(String(localized: "好，我知道了")) {
        AnalyticsConsent.markDisclosureShown()
      }
      Button(String(localized: "關閉收集"), role: .cancel) {
        AnalyticsConsent.setGeneralEnabled(false)
        AnalyticsConsent.markDisclosureShown()
      }
    } message: {
      Text(String(localized: "為了改善 App，我們會傳送匿名的使用統計（不含任何個人資料）。你可以隨時在「設定 → 資料與隱私」關閉。"))
    }
    .task {
      await DailyUsageReporter.reportIfNeeded(context: context)
    }
  }

  private func toggleSessionFromDeeplink(_ profileId: String, link: URL) {
    strategyManager
      .toggleSessionFromDeeplink(profileId, url: link, context: context)
  }

  private func loadApp() {
    strategyManager.loadActiveSession(context: context)
  }

  private func onAppearApp() {
    strategyManager.loadActiveSession(context: context)
    strategyManager.restoreScheduledSessionIfNeeded()
    strategyManager.cleanUpGhostSchedules(context: context)
    strategyManager.reconcileScheduleRegistrations(context: context)
  }

  private func unloadApp() {
    strategyManager.stopTimer()
  }

  private func showErrorAlert(message: String) {
    alertTitle = String(localized: "出了一點狀況")
    alertMessage = message
    showingAlert = true
  }

  private func dismissAlert() {
    showingAlert = false
  }

  // MARK: - Saved Time Banner

  private var totalAllTimeFocusDuration: TimeInterval {
    allCompletedSessions.reduce(0.0) { sum, session in
      guard let end = session.endTime else { return sum }
      return sum + max(0, end.timeIntervalSince(session.startTime))
    }
  }

  private func checkSavedTimeBanner() {
    let defaults = UserDefaults(suiteName: "group.DO.version3")!
    let lastShown = defaults.object(forKey: Self.savedTimeBannerIntervalKey) as? Date

    if let lastShown = lastShown {
      // Check if 14 days have passed since last shown
      guard Date().timeIntervalSince(lastShown) >= Self.bannerInterval else { return }
    } else {
      // First time — record now as baseline, show on next eligible check
      defaults.set(Date(), forKey: Self.savedTimeBannerIntervalKey)
      return
    }

    // Only show if total saved time exceeds 1 hour
    guard totalAllTimeFocusDuration >= 3600 else { return }

    // Show banner and record timestamp
    defaults.set(Date(), forKey: Self.savedTimeBannerIntervalKey)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
      showSavedTimeBanner = true
    }
  }
}

#Preview {
  HomeView()
    .environmentObject(RequestAuthorizer())
    .environmentObject(NavigationManager())
    .environmentObject(StrategyManager())
    .environmentObject(ThemeManager.shared)
    .environmentObject(RatingManager())
    .environmentObject(OnboardingManager.shared)
    .environmentObject(SubscriptionManager.shared)
    .defaultAppStorage(UserDefaults(suiteName: "preview")!)
}
