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

  // Profile management
  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private
    var profiles: [BlockedProfiles]
  @State private var isProfileListPresent = false

  // New profile view
  @State private var showNewProfileView = false

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

  // Confetti celebration state
  @State private var showConfetti = false
  @State private var wasBlocking = false

  // Tab selection
  @State private var selectedTab: Tab = .doMain

  enum Tab: Hashable {
    case doMain
    case schedule
    case activity
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
          onNewProfile: {
            showNewProfileView = true
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

        // Tab 3: Activity
        ActivityTabView()
          .tabItem {
            Label(String(localized: "活動"), systemImage: "chart.bar.fill")
          }
          .tag(Tab.activity)

        // Tab 4: Settings
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
      } else if newPhase == .background {
        unloadApp()
      }
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
      if onboardingManager.shouldShowTutorial && onboardingManager.tutorialStep == 0 {
        onboardingManager.startTutorial()
      }
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
      BlockedProfileView(profile: nil)
        .environmentObject(onboardingManager)
    }
    .sheet(isPresented: $strategyManager.showCustomStrategyView) {
      BlockingStrategyActionView(
        customView: strategyManager.customStrategyView
      )
      .presentationDetents([.medium])
    }
    .sheet(isPresented: $showEmergencyView) {
      EmergencyView()
        .presentationDetents([.height(350)])
    }
    .alert(alertTitle, isPresented: $showingAlert) {
      Button(String(localized: "OK"), role: .cancel) { dismissAlert() }
    } message: {
      Text(alertMessage)
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
    strategyManager.cleanUpGhostSchedules(context: context)
  }

  private func unloadApp() {
    strategyManager.stopTimer()
  }

  private func showErrorAlert(message: String) {
    alertTitle = String(localized: "Whoops")
    alertMessage = message
    showingAlert = true
  }

  private func dismissAlert() {
    showingAlert = false
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
    .defaultAppStorage(UserDefaults(suiteName: "preview")!)
}
