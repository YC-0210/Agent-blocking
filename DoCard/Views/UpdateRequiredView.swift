import SwiftUI

/// A single modifier keeps the app entry-point change separate from other startup work.
struct AppUpdateGate: ViewModifier {
  @Environment(\.scenePhase) private var scenePhase
  @EnvironmentObject private var manager: StrategyManager
  @EnvironmentObject private var authorizer: RequestAuthorizer
  @EnvironmentObject private var onboarding: OnboardingManager
  @StateObject private var updates = AppUpdateManager()

  private var shouldGate: Bool {
    AppUpdatePolicy.shouldGate(
      updateRequired: updates.requiredUpdate != nil,
      isBlocking: manager.activeSessionStatus.isBlocking
        || SharedData.getActiveStrategySharedSession() != nil,
      isOnboarding: onboarding.shouldShowOnboarding,
      isAuthorized: authorizer.isAuthorized)
  }

  func body(content: Content) -> some View {
    Group {
      if shouldGate, let configuration = updates.requiredUpdate {
        UpdateRequiredView(configuration: configuration, updates: updates)
      } else {
        content
      }
    }
    .task { await checkForUpdate() }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { Task { await checkForUpdate() } }
    }
  }

  private func checkForUpdate() async {
    #if DEBUG && targetEnvironment(simulator)
      // Existing simulator portfolios must not depend on the live website policy.
      if MaestroFixture.isRequested
        || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
      {
        return
      }
    #endif
    await updates.checkForUpdate()
  }
}

struct UpdateRequiredView: View {
  let configuration: AppUpdateConfiguration
  @ObservedObject var updates: AppUpdateManager
  @Environment(\.openURL) private var openURL
  @EnvironmentObject private var theme: ThemeManager
  @State private var showEmergency = false

  private var message: String {
    let remote = configuration.updateMessage?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return remote.isEmpty
      ? String(localized: "Please update DO Card to continue.", table: "AppUpdate")
      : String(remote.prefix(300))
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        Image(systemName: "arrow.down.app.fill")
          .font(.system(size: 60))
          .foregroundStyle(theme.themeColor)
          .accessibilityHidden(true)
        Text(String(localized: "Update DO Card", table: "AppUpdate"))
          .font(.largeTitle.bold())
          .accessibilityIdentifier("update.title")
        Text(message)
          .multilineTextAlignment(.center)
        Text(
          String(localized: "Minimum version: \(configuration.minimumVersion)", table: "AppUpdate")
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        Button {
          openURL(AppUpdateManager.appStoreURL)
        } label: {
          Text(String(localized: "Update on the App Store", table: "AppUpdate"))
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .tint(theme.themeColor)
        .accessibilityIdentifier("update.store")
        Button(String(localized: "Check again", table: "AppUpdate")) {
          Task { await updates.checkForUpdate() }
        }
        .disabled(updates.isChecking)
        .accessibilityIdentifier("update.retry")
        // Always leave a recovery escape even if a session snapshot is stale.
        Button(String(localized: "Emergency Unlock", table: "AppUpdate")) { showEmergency = true }
          .accessibilityIdentifier("update.emergency")
      }
      .padding(32)
      .frame(maxWidth: 480)
      .frame(maxWidth: .infinity)
    }
    .sheet(isPresented: $showEmergency) { EmergencyView() }
  }
}
