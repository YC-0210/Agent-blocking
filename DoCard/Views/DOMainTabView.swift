import FamilyControls
import OSLog
import SwiftData
import SwiftUI

private let logger = Logger(subsystem: "app.docard", category: "DOMainTabView")

// MARK: - Tutorial Button Frame PreferenceKeys

private struct NewProfileButtonFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

private struct FocusButtonFrameKey: PreferenceKey {
  static var defaultValue: CGRect = .zero
  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}

struct DOMainTabView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject var requestAuthorizer: RequestAuthorizer
  @EnvironmentObject var strategyManager: StrategyManager
  @EnvironmentObject var ratingManager: RatingManager
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var onboardingManager: OnboardingManager

  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private var profiles: [BlockedProfiles]

  // Query completed sessions for accumulated focus time
  @Query(
    filter: #Predicate<BlockedProfileSession> { $0.endTime != nil },
    sort: \BlockedProfileSession.endTime,
    order: .reverse
  ) private var completedSessions: [BlockedProfileSession]

  // Global break settings
  @AppStorage("globalEnableBreaks") private var globalEnableBreaks: Bool = false

  // Profile selection
  @State private var selectedProfileIndex: Int = 0
  @State private var showSelectModeSheet: Bool = false

  // Tutorial
  @State private var newProfileButtonFrame: CGRect = .zero
  @State private var focusButtonFrame: CGRect = .zero
  @State private var showTutorialComplete: Bool = false
  @State private var showConfetti: Bool = false

  // Callbacks to HomeView
  var onEditProfile: (BlockedProfiles) -> Void
  var onManageProfiles: () -> Void
  var onNewProfile: () -> Void
  var navigateToProfileId: UUID?

  var isBlocking: Bool {
    strategyManager.isBlocking
  }

  var isBreakAvailable: Bool {
    guard globalEnableBreaks else { return false }
    guard let session = strategyManager.activeSession else { return false }
    // Break is available if it hasn't been used yet (breakEndTime is nil)
    return session.breakEndTime == nil
  }

  var isBreakActive: Bool {
    strategyManager.isBreakActive
  }

  var breakUsed: Bool {
    guard let session = strategyManager.activeSession else { return false }
    return session.breakEndTime != nil
  }

  private var currentProfile: BlockedProfiles? {
    if isBlocking,
      let activeProfile = strategyManager.activeSession?.blockedProfile
    {
      return activeProfile
    }
    guard !profiles.isEmpty else { return nil }
    let index = min(selectedProfileIndex, profiles.count - 1)
    return profiles[max(0, index)]
  }

  /// Accumulated focus time since the last noon reset (completed sessions only).
  /// Resets daily at 12:00 PM — if it's before noon, the window starts at yesterday's noon.
  private var todayFocusTime: TimeInterval {
    let calendar = Calendar.current
    let now = Date()
    let todayNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: now)!
    let resetTime = now >= todayNoon ? todayNoon : calendar.date(byAdding: .day, value: -1, to: todayNoon)!
    return completedSessions
      .filter { session in
        guard let end = session.endTime else { return false }
        return end >= resetTime
      }
      .reduce(0) { total, session in
        guard let end = session.endTime else { return total }
        return total + end.timeIntervalSince(session.startTime)
      }
  }

  var body: some View {
    ZStack {
      // Pure black background
      Color.black.ignoresSafeArea()

      // Always show the main DO page layout — even on first launch
      VStack(spacing: 0) {

        // Authorization callout (if needed)
        AuthorizationCallout(
          authorizationStatus: requestAuthorizer.getAuthorizationStatus(),
          onAuthorizationHandler: {
            requestAuthorizer.requestAuthorization()
          }
        )
        .padding(.horizontal, 24)

        Spacer()

        // Timer pill badge — always visible
        DOTimerDisplay(
          elapsedTime: strategyManager.elapsedTime,
          isBlocking: isBlocking,
          todayFocusTime: todayFocusTime
        )
        .padding(.bottom, 50)

        // DO logo image
        DOCardImageView()
          .padding(.bottom, 30)

        // Mode + blocking count (only if profile exists)
        if let profile = currentProfile {
          DOProfileInfoView(
            profile: profile,
            isBlocking: isBlocking,
            onModeTapped: { showSelectModeSheet = true }
          )
        }

        Spacer()

        // Bottom section
        VStack(spacing: 12) {
          if let profile = currentProfile {
            // Has profile — show start/stop button
            DOFocusButton(
              isBlocking: isBlocking,
              showStopButton: profile.showStopButton(
                elapsedTime: strategyManager.elapsedTime),
              isBreakAvailable: isBreakAvailable,
              isBreakActive: isBreakActive,
              breakUsed: breakUsed,
              simpleTapMode: onboardingManager.tutorialStep == 5,
              onStartTapped: {
                if onboardingManager.tutorialStep == 5 {
                  showTutorialComplete = true
                  showConfetti = true
                  DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    showTutorialComplete = false
                    onboardingManager.completeTutorial()
                  }
                }
                strategyButtonPress(profile)
              },
              onStopTapped: {
                strategyButtonPress(profile)
              },
              onBreakTapped: { selectedMinutes in
                // Sync global break settings to profile before toggling
                if let session = strategyManager.activeSession {
                  session.blockedProfile.enableBreaks = true
                  // Use slider-selected time when starting, ignore when ending
                  if !session.isBreakActive {
                    session.blockedProfile.breakTimeInMinutes = selectedMinutes
                  }
                  do {
                    try context.save()
                  } catch {
                    logger.error("Failed to save break settings: \(error.localizedDescription)")
                  }
                }
                strategyManager.toggleBreak(context: context)
              }
            )
            .background(
              GeometryReader { geo in
                let frame = geo.frame(in: .named("DOMainTab"))
                Color.clear
                  .preference(
                    key: FocusButtonFrameKey.self,
                    value: frame
                  )
                  .onAppear {
                    DispatchQueue.main.async {
                      focusButtonFrame = frame
                    }
                  }
              }
            )

          } else {
            // No mode yet — show "Create Mode" button
            Button(action: {
              if onboardingManager.tutorialStep == 1 {
                onboardingManager.advanceTutorial()
              }
              onNewProfile()
            }) {
              Text(String(localized: "新增模式"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                  Capsule()
                    .fill(themeManager.themeColor)
                )
            }
            .background(
              GeometryReader { geo in
                Color.clear
                  .preference(
                    key: NewProfileButtonFrameKey.self,
                    value: geo.frame(in: .named("DOMainTab"))
                  )
              }
            )
          }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
      }


      // Tutorial Step 1 overlay
      if onboardingManager.tutorialStep == 1, newProfileButtonFrame != .zero {
        TutorialStep1Overlay(
          buttonTopY: newProfileButtonFrame.minY
        )
        .allowsHitTesting(false)
      }

      // Tutorial Step 5 overlay
      if onboardingManager.tutorialStep == 5 {
        TutorialStep5Overlay(buttonFrame: focusButtonFrame)
          .opacity(focusButtonFrame != .zero ? 1 : 0)
          .animation(.easeIn(duration: 0.3), value: focusButtonFrame != .zero)
      }

      // Tutorial complete overlay with confetti
      if showTutorialComplete {
        TutorialCompleteOverlay(showConfetti: $showConfetti)
      }
    }
    .coordinateSpace(name: "DOMainTab")
    .onPreferenceChange(NewProfileButtonFrameKey.self) { frame in
      newProfileButtonFrame = frame
    }
    .onPreferenceChange(FocusButtonFrameKey.self) { frame in
      focusButtonFrame = frame
    }
    .onChange(of: navigateToProfileId) { _, newId in
      if let targetId = newId,
        let index = profiles.firstIndex(where: { $0.id == targetId })
      {
        selectedProfileIndex = index
      }
    }
    .onChange(of: isBlocking) { _, _ in
      if let activeId = strategyManager.activeSession?.blockedProfile.id,
        let index = profiles.firstIndex(where: { $0.id == activeId })
      {
        selectedProfileIndex = index
      }
    }
    .onAppear {
      if let activeId = strategyManager.activeSession?.blockedProfile.id,
        let index = profiles.firstIndex(where: { $0.id == activeId })
      {
        selectedProfileIndex = index
      }
    }
    .sheet(isPresented: $showSelectModeSheet) {
      SelectModeView(
        profiles: profiles,
        selectedIndex: $selectedProfileIndex,
        onEditProfile: { profile in
          onEditProfile(profile)
        },
        onCreateNew: {
          onNewProfile()
        }
      )
      .presentationDetents([.medium, .large])
    }
  }

  private func strategyButtonPress(_ profile: BlockedProfiles) {
    strategyManager.toggleBlocking(context: context, activeProfile: profile)
    ratingManager.incrementLaunchCount()
  }
}

// MARK: - Tutorial Step 1 Overlay

private struct TutorialStep1Overlay: View {
  let buttonTopY: CGFloat

  @State private var arrowBounce = false

  var body: some View {
    VStack(spacing: 0) {
      // Dim area covering everything above the tutorial content
      Color.black.opacity(0.7)
        .frame(height: buttonTopY - 100)

      // Tutorial content (not dimmed)
      VStack(spacing: 12) {
        Text(String(localized: "步驟一"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(ThemeManager.shared.themeColor)

        Text(String(localized: "點擊此處來開始你的旅程"))
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
      }

      // Remaining space below — no dim (button lives here)
      Spacer()
    }
    .onAppear {
      arrowBounce = true
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

// MARK: - Tutorial Step 5 Overlay

private struct TutorialStep5Overlay: View {
  let buttonFrame: CGRect  // in DOMainTab coordinate space

  @State private var arrowBounce = false

  var body: some View {
    GeometryReader { geo in
      let cutoutRect = CGRect(
        x: buttonFrame.minX - 6,
        y: buttonFrame.minY - 6,
        width: buttonFrame.width + 12,
        height: buttonFrame.height + 12
      )

      Canvas { context, size in
        // Draw full dim
        context.fill(
          Path(CGRect(origin: .zero, size: size)),
          with: .color(.black.opacity(0.85))
        )
        // Punch out the focus button
        context.blendMode = .destinationOut
        context.fill(
          Path(roundedRect: cutoutRect, cornerRadius: 35),
          with: .color(.white)
        )
      }
      .compositingGroup()
      // Block taps on dimmed area, allow taps through the cutout to the focus button
      .contentShape(
        DimmedAreaShape(cutoutRect: cutoutRect, cornerRadius: 35),
        eoFill: true
      )
      .onTapGesture {
        // Consume taps on dimmed area — do nothing
      }
      .overlay(alignment: .top) {
        VStack(spacing: 6) {
          Text(String(localized: "步驟五"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ThemeManager.shared.themeColor)

          Text(String(localized: "準備好了嗎？點擊開始專注"))
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
        .allowsHitTesting(false)
        .padding(.top, cutoutRect.minY - 80)
      }
    }
    .onAppear {
      arrowBounce = true
    }
  }
}

// MARK: - Tutorial Complete Overlay

private struct TutorialCompleteOverlay: View {
  @Binding var showConfetti: Bool

  @State private var appear = false

  var body: some View {
    ZStack {
      Color.black.opacity(0.85)
        .ignoresSafeArea()

      VStack(spacing: 16) {
        Text("🎉")
          .font(.system(size: 60))

        Text(String(localized: "恭喜完成教學！"))
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)

        Text(String(localized: "你已經準備好開始專注了"))
          .font(.system(size: 16, weight: .medium))
          .foregroundColor(.white.opacity(0.7))
      }
      .scaleEffect(appear ? 1.0 : 0.8)
      .opacity(appear ? 1.0 : 0)

      ConfettiView(isActive: $showConfetti, themeColor: ThemeManager.shared.themeColor)
    }
    .allowsHitTesting(false)
    .onAppear {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
        appear = true
      }
    }
  }
}

