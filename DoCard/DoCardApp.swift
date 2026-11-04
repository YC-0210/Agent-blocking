//
//  DoCardApp.swift
//  DoCard
//
//  Created by Ali Waseem on 2024-10-06.
//

import AppIntents
import BackgroundTasks
import SwiftData
import SwiftUI

private let container: ModelContainer = {
  #if DEBUG && targetEnvironment(simulator)
    if let fixture = MaestroFixture.makeContainerIfRequested() { return fixture }
  #endif
  let schema = Schema(versionedSchema: AppSchemaV5.self)
  let config = ModelConfiguration(schema: schema)
  do {
    return try AppModelStore.open(configuration: config)
  } catch {
    // Strategy B: back up the corrupt store and recreate a fresh one.
    // This fires only when SwiftData cannot apply the migration plan —
    // e.g. a device whose store stamp was never correctly written and
    // whose entity hash doesn’t match any declared schema version.
    let fm = FileManager.default
    let storeURL = config.url
    let backupSuffix = "bak-\(Int(Date().timeIntervalSince1970))"

    // Back up the store and its WAL sidecars using the real `.store` filenames.
    let sidecarSuffixes = ["", "-shm", "-wal"]
    for suffix in sidecarSuffixes {
      let src = suffix.isEmpty
        ? storeURL
        : storeURL.deletingLastPathComponent().appendingPathComponent(
          "\(storeURL.lastPathComponent)\(suffix)"
        )
      let dst = storeURL.deletingLastPathComponent().appendingPathComponent(
        "\(storeURL.lastPathComponent)-\(backupSuffix)\(suffix)"
      )
      if fm.fileExists(atPath: src.path) {
        try? fm.moveItem(at: src, to: dst)
      }
    }

    UserDefaults.standard.set(true, forKey: "didResetStoreOnMigrationFailure")

    do {
      return try AppModelStore.open(configuration: config)
    } catch {
      fatalError("Couldn’t create ModelContainer even after store reset: \(error)")
    }
  }
}()

@main
struct DoCardApp: App {
  #if DEBUG && targetEnvironment(simulator)
    // Force fixture preparation before any app services read persisted state.
    private let preparedContainer: ModelContainer = container
  #endif
  @Environment(\.scenePhase) private var scenePhase
  private let retentionPrepared: Void = RetentionCapture.prepare()
  @StateObject private var requestAuthorizer = RequestAuthorizer()
  @StateObject private var navigationManager = NavigationManager()
  @StateObject private var nfcWriter = NFCWriter()
  @StateObject private var ratingManager = RatingManager()

  // Singletons for shared functionality
  @StateObject private var startegyManager = StrategyManager.shared
  @StateObject private var liveActivityManager = LiveActivityManager.shared
  @StateObject private var themeManager = ThemeManager.shared
  @StateObject private var onboardingManager = OnboardingManager.shared
  @StateObject private var subscriptionManager = SubscriptionManager.shared
  @StateObject private var whatsNewManager = WhatsNewManager.shared

  init() {
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--debug-premium-test") {
        SharedData.debugForcedTier = .premium
      }
    #endif
    TimersUtil.registerBackgroundTasks()

    // Migrate legacy single-schedule data to multi-schedule array
    let migrationContext = ModelContext(container)
    BlockedProfiles.migrateSchedulesToArray(in: migrationContext)

    // Migrate the legacy gallery on/off toggle to the 3-way home-centerpiece
    // selection (true → gallery, false → card). Idempotent.
    HomeCenterpiece.migrateLegacySettingIfNeeded()

    let asyncDependency: @Sendable () async -> (ModelContainer) = {
      @MainActor in
      return container
    }
    AppDependencyManager.shared.add(
      key: "ModelContainer",
      dependency: asyncDependency
    )
  }

  // Throwaway UI review only: this flag cannot bypass access in device or Release builds.
  private var isOnboardingUIPrototype: Bool {
    #if DEBUG && targetEnvironment(simulator)
      ProcessInfo.processInfo.arguments.contains("--onboarding-ui-prototype")
    #else
      false
    #endif
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if isOnboardingUIPrototype {
          OnboardingView()
        } else if !subscriptionManager.permits(.otherFeature) {
          SubscriptionRequiredView()
        } else if onboardingManager.shouldShowOnboarding {
          OnboardingView()
        } else {
          HomeView()
            .onOpenURL { url in
              handleUniversalLink(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) {
              userActivity in
              guard let url = userActivity.webpageURL else {
                return
              }
              handleUniversalLink(url)
            }
        }
      }
      .modifier(AppUpdateGate())
      .environmentObject(requestAuthorizer)
      .environmentObject(startegyManager)
      .environmentObject(navigationManager)
      .environmentObject(nfcWriter)
      .environmentObject(ratingManager)
      .environmentObject(liveActivityManager)
      .environmentObject(themeManager)
      .environmentObject(onboardingManager)
      .environmentObject(subscriptionManager)
      .environmentObject(whatsNewManager)
      .task {
        OnboardingTracking.shared.start()
        guard !isOnboardingUIPrototype else { return }
        RetentionUploadService.setActive(scenePhase == .active)
        await subscriptionManager.checkCurrentEntitlements()
        reconcileSubscription()
      }
      .onChange(of: subscriptionManager.accessRevision) { _, _ in
        if !isOnboardingUIPrototype { reconcileSubscription() }
      }
      .onChange(of: requestAuthorizer.isAuthorized) { _, authorized in
        if authorized { subscriptionManager.refreshLocalAccess() }
      }
      .onReceive(NotificationCenter.default.publisher(for: RetentionUploadService.disclosureChanged)) { _ in
        RetentionUploadService.setActive(scenePhase == .active && !isOnboardingUIPrototype)
      }
      .onChange(of: scenePhase) { _, phase in
        RetentionUploadService.setActive(phase == .active && !isOnboardingUIPrototype)
        guard phase == .active, !isOnboardingUIPrototype else { return }
        subscriptionManager.refreshLocalAccess()
        reconcileSubscription()
        Task { await subscriptionManager.checkCurrentEntitlements() }
      }
      #if DEBUG && targetEnvironment(simulator)
        .safeAreaInset(edge: .top) {
          if MaestroFixture.isRequested {
            MaestroSessionPanel(container: container, manager: startegyManager)
          }
        }
      #endif
      .preferredColorScheme(.dark)
    }
    .modelContainer(container)
  }

  private func reconcileSubscription() {
    let context = container.mainContext
    if subscriptionManager.isPremium {
      startegyManager.loadActiveSession(context: context)
    } else { startegyManager.reconcileSubscription(context: context) }
  }

  private func handleUniversalLink(_ url: URL) {
    navigationManager.handleLink(url)
  }
}
