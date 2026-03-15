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
  do {
    return try ModelContainer(
      for: BlockedProfileSession.self,
      BlockedProfiles.self
    )
  } catch {
    fatalError("Couldn’t create ModelContainer: \(error)")
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

  init() {
    TimersUtil.registerBackgroundTasks()

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
      .preferredColorScheme(.dark)
    }
    .modelContainer(container)
  }

  private func handleUniversalLink(_ url: URL) {
    navigationManager.handleLink(url)
  }
}
