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
  @EnvironmentObject var coFocusManager: CoFocusManager

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

  // Profile selection
  @State private var selectedProfileIndex: Int = 0
  @State private var showSelectModeSheet: Bool = false

  // Tutorial
  @State private var newProfileButtonFrame: CGRect = .zero
  @State private var focusButtonFrame: CGRect = .zero
  @State private var showTutorialComplete: Bool = false
  @State private var showConfetti: Bool = false

  // Card-image tap entry point (Change 2)
  @GestureState private var isCardPressed = false
  @State private var showForceStartConfirm = false

  // Tutorial Step 5 — NFC timeout state
  @State private var tutorialNFCTimeoutVisible = false
  @State private var nfcTimeoutWorkItem: DispatchWorkItem? = nil
  @State private var nfcTimeoutDismissWorkItem: DispatchWorkItem? = nil

  // Card naming nudge (one-time, for existing users who haven't named their card)
  @AppStorage("hasShownCardNamingNudge") private var hasShownCardNamingNudge: Bool = false
  @State private var showCardNamingNudge = false

  // Callbacks to HomeView
  var onEditProfile: (BlockedProfiles) -> Void
  var onManageProfiles: () -> Void
  var onNewProfile: (String) -> Void
  var onNavigateToSettings: () -> Void
  var navigateToProfileId: UUID?

  var isBlocking: Bool {
    strategyManager.isBlocking
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

  /// User-facing label describing the current active session's type, shown
  /// beneath the timer when blocking. Co-focus active takes precedence so
  /// the user sees "共同專注中" while the pairing is in progress, then sees
  /// the underlying session type (e.g. "排程鎖定中") if blocking continues
  /// after co-focus ends. Returns nil when there is no active session.
  /// (Bug #7.)
  private var sessionTypeLabel: String? {
    if case .active = coFocusManager.phase {
      return String(localized: "共同專注中")
    }
    guard let session = strategyManager.activeSession else { return nil }
    if session.triggerSource == "scheduled" {
      return String(localized: "排程鎖定中")
    }
    if let strategyId = session.blockedProfile.blockingStrategyId,
      StrategyManager.isTimerStrategy(strategyId)
    {
      if let plannedDurationMinutes =
        SharedData.getActiveStrategySharedSession()?.plannedDurationMinutes
      {
        return String(localized: "定時 \(plannedDurationMinutes) 分鐘")
      }
      return String(localized: "定時專注中")
    }
    return String(localized: "正常鎖定中")
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

        // Timer pill badge — always visible. Mac 連動 status badge appears
        // beneath it during an active session, but only if the user has ever
        // paired a Mac (otherwise nothing useful to show).
        VStack(spacing: 8) {
          DOTimerDisplay(
            elapsedTime: strategyManager.elapsedTime,
            isBlocking: isBlocking,
            todayFocusTime: todayFocusTime
          )
          if isBlocking, let label = sessionTypeLabel {
            // Bug #7: surface the session type beneath the timer so the
            // user can tell whether the current block came from a schedule,
            // a co-focus pairing, a timer, or a manual NFC tap. Especially
            // important after co-focus ends inside an active schedule
            // window — without this the schedule re-applying looks like a
            // bug from the user's POV.
            Text(label)
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.white.opacity(0.5))
          }
          if isBlocking {
            MacSyncStatusBadge(sync: MacSessionSyncService.shared)
          }
        }
        .padding(.bottom, 50)

        // DO logo image — tap to force-start without NFC (Change 2 entry point)
        DOCardImageView()
          .scaleEffect(isCardPressed ? 0.96 : 1.0)
          .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCardPressed)
          .gesture(
            DragGesture(minimumDistance: 0)
              .updating($isCardPressed) { _, state, _ in state = true }
              .onEnded { _ in
                guard !isBlocking, currentProfile != nil else { return }
                showForceStartConfirm = true
              }
          )
          .confirmationDialog(
            String(localized: "開始專注？"),
            isPresented: $showForceStartConfirm,
            titleVisibility: .visible
          ) {
            Button(String(localized: "開始")) {
              if let profile = currentProfile {
                strategyManager.forceStartSession(context: context, profile: profile)
                ratingManager.incrementLaunchCount()
              }
            }
            Button(String(localized: "取消"), role: .cancel) {}
          } message: {
            Text(String(localized: "不需要刷卡，直接開始這次專注。"))
          }
          .padding(.bottom, strategyManager.activeCardName != nil ? 8 : 30)

        // DO Card name — reflects the most recently tapped card's name
        if let cardName = strategyManager.activeCardName {
          Text(cardName)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.35))
            .padding(.bottom, 22)
        }

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
              simpleTapMode: false,
              coFocusAwaitingMyTap: coFocusManager.shouldDivertNFCTapToCoFocus,
              onStartTapped: {
                // Both tutorial Step 5 and normal mode: long-press → NFC scan → session starts
                strategyManager.startSessionWithNFCScan(context: context, profile: profile)
                ratingManager.incrementLaunchCount()

                // Tutorial Step 5: arm a 15-second timeout
                if onboardingManager.tutorialStep == 5 {
                  tutorialNFCTimeoutVisible = false
                  nfcTimeoutWorkItem?.cancel()
                  nfcTimeoutDismissWorkItem?.cancel()

                  let timeout = DispatchWorkItem { [self] in
                    guard !strategyManager.isBlocking else { return }
                    strategyManager.cancelPendingNFCScan()
                    withAnimation(.easeIn(duration: 0.2)) {
                      tutorialNFCTimeoutVisible = true
                    }
                    let dismiss = DispatchWorkItem {
                      withAnimation(.easeOut(duration: 0.3)) {
                        tutorialNFCTimeoutVisible = false
                      }
                    }
                    nfcTimeoutDismissWorkItem = dismiss
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: dismiss)
                  }
                  nfcTimeoutWorkItem = timeout
                  DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
                }
              },
              onStopTapped: {
                strategyButtonPress(profile)
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

            // Tutorial Step 5 timeout message — auto-dismisses after 3 seconds
            if tutorialNFCTimeoutVisible {
              Text(String(localized: "請靠上 DO Card 才能開始專注"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

          } else {
            // No mode yet — show "Create Mode" button
            Button(action: {
              if onboardingManager.tutorialStep == 1 {
                onboardingManager.advanceTutorial()
              }
              onNewProfile("")
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
        TutorialStep5Overlay(
          buttonFrame: focusButtonFrame,
          isNFCScanning: strategyManager.isNFCScanInProgress
        )
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
    .onChange(of: isBlocking) { _, newValue in
      if let activeId = strategyManager.activeSession?.blockedProfile.id,
        let index = profiles.firstIndex(where: { $0.id == activeId })
      {
        selectedProfileIndex = index
      }
      // Tutorial Step 5: NFC scan succeeded → session started → complete tutorial
      if newValue && onboardingManager.tutorialStep == 5 {
        nfcTimeoutWorkItem?.cancel()
        nfcTimeoutWorkItem = nil
        nfcTimeoutDismissWorkItem?.cancel()
        nfcTimeoutDismissWorkItem = nil
        tutorialNFCTimeoutVisible = false
        showTutorialComplete = true
        showConfetti = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
          showTutorialComplete = false
          onboardingManager.completeTutorial()
        }
      }
    }
    .onChange(of: strategyManager.isNFCScanInProgress) { _, scanning in
      // Tutorial Step 5: user cancelled NFC dialog before timeout — disarm the timer
      if !scanning && onboardingManager.tutorialStep == 5 {
        nfcTimeoutWorkItem?.cancel()
        nfcTimeoutWorkItem = nil
      }
    }
    .onAppear {
      if let activeId = strategyManager.activeSession?.blockedProfile.id,
        let index = profiles.firstIndex(where: { $0.id == activeId })
      {
        selectedProfileIndex = index
      }
      // Cold-launch default: use the persisted name from pairing/rename until the first NFC tap
      if strategyManager.activeCardName == nil {
        strategyManager.activeCardName = onboardingManager.doCardName
      }
      // One-time card naming nudge: shown only after onboarding, for paired cards without a name
      if !hasShownCardNamingNudge
        && onboardingManager.isOnboardingCompleted
        && onboardingManager.isDOCardPaired
        && onboardingManager.doCardName == nil
      {
        hasShownCardNamingNudge = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
          showCardNamingNudge = true
        }
      }
    }
    .sheet(isPresented: $showCardNamingNudge) {
      CardNamingNudgeSheet(
        onGoToSettings: {
          showCardNamingNudge = false
          onNavigateToSettings()
        },
        onDismiss: {
          showCardNamingNudge = false
        }
      )
      .presentationDetents([.height(260)])
      .presentationDragIndicator(.visible)
    }
    .sheet(isPresented: $showSelectModeSheet) {
      SelectModeView(
        profiles: profiles,
        selectedIndex: $selectedProfileIndex,
        onEditProfile: { profile in
          onEditProfile(profile)
        },
        onCreateNew: { name in
          onNewProfile(name)
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

        Text(String(localized: "點這裡，建立你第一個專注模式"))
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
  let isNFCScanning: Bool

  @State private var arrowBounce = false
  @State private var pulseScale: CGFloat = 1.0
  @State private var pulseOpacity: CGFloat = 0.6

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
      .overlay {
        // Pulse ring — visible only while NFC scan is in progress
        if isNFCScanning && buttonFrame != .zero {
          Capsule()
            .stroke(ThemeManager.shared.themeColor.opacity(pulseOpacity), lineWidth: 2)
            .frame(width: cutoutRect.width + 16, height: cutoutRect.height + 16)
            .scaleEffect(pulseScale)
            .position(x: cutoutRect.midX, y: cutoutRect.midY)
            .allowsHitTesting(false)
        }
      }
      .overlay(alignment: .top) {
        VStack(spacing: 6) {
          Text(String(localized: "步驟五"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(ThemeManager.shared.themeColor)

          Text(
            isNFCScanning
              ? String(localized: "靠上你的 DO Card…")
              : String(localized: "準備好了嗎？長按靠上 DO Card")
          )
          .font(.system(size: 17, weight: .medium))
          .foregroundColor(.white)
          .animation(.easeInOut(duration: 0.2), value: isNFCScanning)

          if !isNFCScanning {
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
        }
        .allowsHitTesting(false)
        .padding(.top, cutoutRect.minY - 80)
      }
    }
    .onAppear {
      arrowBounce = true
    }
    .onChange(of: isNFCScanning) { _, scanning in
      if scanning {
        withAnimation(
          .easeOut(duration: 1.2)
            .repeatForever(autoreverses: false)
        ) {
          pulseScale = 1.25
          pulseOpacity = 0
        }
      } else {
        pulseScale = 1.0
        pulseOpacity = 0.6
      }
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

        Text(String(localized: "完成了！"))
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)

        Text(String(localized: "做就對了，開始你的第一次專注"))
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

// MARK: - Card Naming Nudge Sheet

private struct CardNamingNudgeSheet: View {
  let onGoToSettings: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 20) {
      Spacer()

      Image(systemName: "pencil.and.outline")
        .font(.system(size: 36, weight: .light))
        .foregroundColor(ThemeManager.shared.themeColor)

      VStack(spacing: 8) {
        Text(String(localized: "幫你的 DO Card 命名吧"))
          .font(.system(size: 19, weight: .bold))
          .multilineTextAlignment(.center)

        Text(String(localized: "在設定中替你的卡片取一個專屬名字，每次靠卡時主頁就會顯示它。"))
          .font(.system(size: 14, weight: .regular))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 24)
      }

      Spacer()

      VStack(spacing: 10) {
        Button(action: onGoToSettings) {
          Text(String(localized: "前往設定"))
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(Capsule().fill(ThemeManager.shared.themeColor))
        }

        Button(action: onDismiss) {
          Text(String(localized: "之後再說"))
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.secondary)
        }
        .frame(height: 36)
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 16)
    }
  }
}

