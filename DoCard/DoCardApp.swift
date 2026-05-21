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
  let schema = Schema(versionedSchema: AppSchemaV5.self)
  let config = ModelConfiguration(schema: schema)
  do {
    return try ModelContainer(
      for: schema,
      migrationPlan: AppMigrationPlan.self,
      configurations: [config]
    )
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
      return try ModelContainer(
        for: schema,
        migrationPlan: AppMigrationPlan.self,
        configurations: [config]
      )
    } catch {
      fatalError("Couldn’t create ModelContainer even after store reset: \(error)")
    }
  }
}()

@main
struct DoCardApp: App {
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
  @StateObject private var coFocusManager = CoFocusManager.shared
  @StateObject private var pairingDeviceStore = PairingDeviceStore.shared
  @StateObject private var whatsNewManager = WhatsNewManager.shared

  init() {
    TimersUtil.registerBackgroundTasks()

    // Migrate legacy single-schedule data to multi-schedule array
    let migrationContext = ModelContext(container)
    BlockedProfiles.migrateSchedulesToArray(in: migrationContext)

    let asyncDependency: @Sendable () async -> (ModelContainer) = {
      @MainActor in
      return container
    }
    AppDependencyManager.shared.add(
      key: "ModelContainer",
      dependency: asyncDependency
    )
  }

  var body: some Scene {
    WindowGroup {
      Group {
        if onboardingManager.shouldShowOnboarding {
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
      .environmentObject(requestAuthorizer)
      .environmentObject(startegyManager)
      .environmentObject(navigationManager)
      .environmentObject(nfcWriter)
      .environmentObject(ratingManager)
      .environmentObject(liveActivityManager)
      .environmentObject(themeManager)
      .environmentObject(onboardingManager)
      .environmentObject(subscriptionManager)
      .environmentObject(coFocusManager)
      .environmentObject(pairingDeviceStore)
      .environmentObject(whatsNewManager)
      .task { await coFocusManager.bootstrap() }
      .preferredColorScheme(.dark)
    }
    .modelContainer(container)
  }

  private func handleUniversalLink(_ url: URL) {
    navigationManager.handleLink(url)
  }
}
