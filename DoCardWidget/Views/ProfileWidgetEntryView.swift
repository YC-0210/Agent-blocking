//
//  ProfileWidgetEntryView.swift
//  DoCardWidget
//
//  Created by Ali Waseem on 2025-03-11.
//

import AppIntents
import FamilyControls
import SwiftUI
import WidgetKit

// Brand orange from widget Assets.xcassets AccentColor (#FF6B35)
private let brandOrange = Color("AccentColor")

// MARK: - Widget View
struct ProfileWidgetEntryView: View {
  var entry: ProfileControlProvider.Entry

  // Computed property to determine if the widget should show as unavailable
  private var isUnavailable: Bool {
    guard let selectedProfileId = entry.selectedProfileId,
      let activeSession = entry.activeSession
    else {
      return false
    }

    // Check if the active session's profile ID matches the widget's selected profile ID
    return activeSession.blockedProfileId.uuidString != selectedProfileId
  }

  // Known-valid URL constant — safe to force unwrap
  // swiftlint:disable:next force_unwrapping
  private static let fallbackURL = URL(string: "do://")!

  private var linkToOpen: URL {
    // Don't open the app via profile to stop the session
    if entry.isSessionActive {
      return URL(string: "https://do-card.online") ?? Self.fallbackURL
    }

    return entry.deepLinkURL ?? Self.fallbackURL
  }

  var body: some View {
    ZStack {
      // Main content
      VStack(spacing: 8) {
        // Top section: Profile name (left) and hourglass (right)
        HStack {
          Text(entry.profileName ?? "No Profile")
            .font(.system(size: 14))
            .fontWeight(.bold)
            .foregroundColor(.white)
            .lineLimit(1)

          Spacer()

          Image(systemName: "hourglass")
            .font(.body)
            .foregroundColor(brandOrange)
        }
        .padding(.top, 8)

        // Middle section: Blocked count + enabled options count
        HStack {
          VStack(alignment: .leading, spacing: 2) {
            if let profile = entry.profileSnapshot {
              let blockedCount = getBlockedCount(from: profile)
              let enabledOptionsCount = getEnabledOptionsCount(from: profile)

              Text("\(blockedCount) \(String(localized: "Blocked"))")
                .font(.system(size: 10))
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.6))

              Text("\(String(localized: "with")) \(enabledOptionsCount) \(String(localized: "Options"))")
                .font(.system(size: 8))
                .fontWeight(.regular)
                .foregroundColor(.white.opacity(0.6))
            } else {
              Text(String(localized: "No profile selected"))
                .font(.system(size: 8))
                .foregroundColor(.white.opacity(0.6))
            }
          }

          Spacer()
        }

        // Bottom section: Status message or timer (takes up most space)
        VStack {
          if entry.isSessionActive {
            VStack(spacing: 2) {
              if let startTime = entry.sessionStartTime {
                Text(
                  Date(
                    timeIntervalSinceNow: startTime.timeIntervalSince1970
                      - Date().timeIntervalSince1970
                  ),
                  style: .timer
                )
                .font(.system(size: 22))
                .fontWeight(.bold)
                .foregroundColor(brandOrange)
              }
              Text(String(localized: "專注中"))
                .font(.system(size: 10))
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.6))
            }
          } else {
            Link(destination: linkToOpen) {
              Text(String(localized: "輕觸卡片開始專注"))
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.6))
            }
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 8)
      }
      .blur(radius: isUnavailable ? 3 : 0)

      // Unavailable overlay
      if isUnavailable {
        VStack(spacing: 4) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.title2)
            .foregroundColor(brandOrange)

          Text(String(localized: "Unavailable"))
            .font(.system(size: 16))
            .fontWeight(.bold)
            .foregroundColor(.white)

          Text(String(localized: "Different profile active"))
            .font(.system(size: 10))
            .foregroundColor(.white.opacity(0.6))
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.9))
        .cornerRadius(8)
      }
    }
  }

  // Helper function to count total blocked items
  private func getBlockedCount(from profile: SharedData.ProfileSnapshot) -> Int {
    let appCount =
      profile.selectedActivity.categories.count + profile.selectedActivity.applications.count
    let webDomainCount = profile.selectedActivity.webDomains.count
    let customDomainCount = profile.domains?.count ?? 0
    return appCount + webDomainCount + customDomainCount
  }

  // Helper function to count enabled options
  private func getEnabledOptionsCount(from profile: SharedData.ProfileSnapshot) -> Int {
    var count = 0
    if profile.enableLiveActivity { count += 1 }
    if profile.enableBreaks { count += 1 }
    if profile.enableAllowMode { count += 1 }
    if profile.enableAllowModeDomains { count += 1 }
    if profile.reminderTimeInSeconds != nil { count += 1 }
    if profile.physicalUnblockNFCTagIds != nil { count += 1 }
    return count
  }
}

#Preview(as: .systemSmall) {
  ProfileControlWidget()
} timeline: {
  // Preview 1: No active session
  ProfileWidgetEntry(
    date: .now,
    selectedProfileId: "test-id",
    profileName: "Focus Session",
    activeSession: nil,
    profileSnapshot: SharedData.ProfileSnapshot(
      id: UUID(),
      name: "Focus Session",
      selectedActivity: {
        var selection = FamilyActivitySelection()
        return selection
      }(),
      createdAt: Date(),
      updatedAt: Date(),
      blockingStrategyId: nil,
      order: 0,
      enableLiveActivity: true,
      reminderTimeInSeconds: nil,
      customReminderMessage: nil,
      enableBreaks: true,
      enableAllowMode: true,
      enableAllowModeDomains: true,
      enableSafariBlocking: true,
      domains: ["facebook.com", "twitter.com", "instagram.com"],
      physicalUnblockNFCTagIds: nil,
      schedules: []
    ),
    deepLinkURL: URL(string: "https://do.app/profile/test-id"),
    focusMessage: "Stay focused and avoid distractions",
    useProfileURL: true
  )

  // Preview 2: Active session matching widget profile
  let activeProfileId = UUID()
  ProfileWidgetEntry(
    date: .now,
    selectedProfileId: activeProfileId.uuidString,
    profileName: "Deep Work Session",
    activeSession: SharedData.SessionSnapshot(
      id: "test-session",
      tag: "test-tag",
      blockedProfileId: activeProfileId,
      startTime: Date(timeIntervalSinceNow: -300),
      endTime: nil,
      breakStartTime: nil,
      breakEndTime: nil,
      forceStarted: true
    ),
    profileSnapshot: SharedData.ProfileSnapshot(
      id: activeProfileId,
      name: "Deep Work Session",
      selectedActivity: FamilyActivitySelection(),
      createdAt: Date(),
      updatedAt: Date(),
      blockingStrategyId: nil,
      order: 0,
      enableLiveActivity: true,
      reminderTimeInSeconds: nil,
      customReminderMessage: nil,
      enableBreaks: true,
      enableAllowMode: true,
      enableAllowModeDomains: true,
      enableSafariBlocking: true,
      domains: ["youtube.com", "reddit.com"],
      physicalUnblockNFCTagIds: nil,
      schedules: []
    ),
    deepLinkURL: URL(string: "https://do.app/profile/\(activeProfileId.uuidString)"),
    focusMessage: "Deep focus time",
    useProfileURL: true
  )

  // Preview 3: No profile selected
  ProfileWidgetEntry(
    date: .now,
    selectedProfileId: nil,
    profileName: "No Profile Selected",
    activeSession: nil,
    profileSnapshot: nil,
    deepLinkURL: URL(string: "do://"),
    focusMessage: "Select a profile to get started",
    useProfileURL: false
  )

  // Preview 4: Unavailable state - different profile active
  let unavailableProfileId = UUID()
  let differentActiveProfileId = UUID()
  ProfileWidgetEntry(
    date: .now,
    selectedProfileId: unavailableProfileId.uuidString,
    profileName: "Work Focus",
    activeSession: SharedData.SessionSnapshot(
      id: "different-session",
      tag: "different-tag",
      blockedProfileId: differentActiveProfileId,
      startTime: Date(timeIntervalSinceNow: -180),
      endTime: nil,
      breakStartTime: nil,
      breakEndTime: nil,
      forceStarted: true
    ),
    profileSnapshot: SharedData.ProfileSnapshot(
      id: unavailableProfileId,
      name: "Work Focus",
      selectedActivity: FamilyActivitySelection(),
      createdAt: Date(),
      updatedAt: Date(),
      blockingStrategyId: nil,
      order: 0,
      enableLiveActivity: true,
      reminderTimeInSeconds: nil,
      customReminderMessage: nil,
      enableBreaks: true,
      enableAllowMode: false,
      enableAllowModeDomains: false,
      enableSafariBlocking: true,
      domains: ["linkedin.com", "slack.com"],
      physicalUnblockNFCTagIds: nil,
      schedules: []
    ),
    deepLinkURL: URL(string: "https://do.app/profile/\(unavailableProfileId.uuidString)"),
    focusMessage: "Different profile is currently active",
    useProfileURL: true
  )
}
