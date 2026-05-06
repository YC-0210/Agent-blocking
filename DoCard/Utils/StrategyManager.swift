import OSLog
import SwiftData
import SwiftUI
import WidgetKit

private let smLogger = Logger(subsystem: "app.docard", category: "StrategyManager")

@MainActor
class StrategyManager: ObservableObject {
  static let shared = StrategyManager()
  private static let emergencyUnlockedSchedulePrefix = "emergencyUnlockedSchedule_"
  private static let cardTapSuppressedSchedulePrefix = "cardTapSuppressedSchedule_"
  private static let scheduleSuppressionPrefixes = [
    emergencyUnlockedSchedulePrefix,
    cardTapSuppressedSchedulePrefix,
  ]

  static let availableStrategies: [BlockingStrategy] = [
    NFCBlockingStrategy(),
    NFCTimerBlockingStrategy(),
  ]

  @Published var elapsedTime: TimeInterval = 0
  @Published var timer: Timer?
  @Published var activeSession: BlockedProfileSession?

  @Published var showCustomStrategyView: Bool = false
  @Published var customStrategyView: (any View)? = nil

  @Published var errorMessage: String?

  /// Set when a session ends and meets share-prompt eligibility (normal completion ≥ 30 min,
  /// user has not disabled the prompt in Settings). Observed by HomeView to present the
  /// share-prompt bottom sheet. HomeView nils this back to consume the event.
  @Published var pendingShareSession: ShareableSession?

  /// The name of the most recently tapped DO Card, read live from the NFC payload.
  /// Updated on every successful NFC tap (start or stop session).
  /// Not persisted — initialized from `OnboardingManager.doCardName` on first view appearance.
  @Published var activeCardName: String?

  /// True while an NFC scan initiated by `startSessionWithNFCScan` is waiting for a card tap.
  /// Used by the onboarding tutorial Step 5 to show a scanning indicator and apply a timeout.
  @Published var isNFCScanInProgress: Bool = false

  // SECURITY: Emergency unlock counters stored in Keychain to resist
  // tampering via backup restoration or jailbreak (V-06 fix).
  private var emergencyUnblocksRemaining: Int {
    get { KeychainHelper.load("emergencyUnblocksRemaining", defaultValue: 3) }
    set { KeychainHelper.save("emergencyUnblocksRemaining", value: newValue) }
  }
  private var lastEmergencyUnblocksResetDateTimestamp: Double {
    get { KeychainHelper.load("lastEmergencyUnblocksResetDate", defaultValue: 0) }
    set { KeychainHelper.save("lastEmergencyUnblocksResetDate", value: newValue) }
  }

  private let liveActivityManager = LiveActivityManager.shared

  private let timersUtil = TimersUtil()
  private let appBlocker = AppBlockerUtil()

  /// Guard flag to prevent re-entrant calls to toggleBlocking.
  /// Without this, rapid taps can trigger overlapping NFC sessions
  /// that suppress each other's dialogs.
  private var isToggling: Bool = false

  /// Holds a strong reference to the active strategy while an NFC scan is in progress.
  /// Without this, the strategy created in getStrategy() would be deallocated when
  /// startBlocking()/stopBlocking() returns, causing NFC callbacks to silently no-op
  /// because [weak self] in the closures would be nil.
  private var activeStrategy: BlockingStrategy?

  /// Retains the NFCScannerUtil during an NFC-gated session start.
  /// Released on scan success (before startBlocking fires), cancel, or error.
  private var pendingNFCScanner: NFCScannerUtil?

  /// Pending triggerSource to apply when the next session is created via onSessionCreation.
  /// Set before calling startBlocking(), consumed in the callback.
  private var pendingTriggerSource: String = "manual"

  var isBlocking: Bool {
    return activeSession?.isActive == true
  }

  var isBreakActive: Bool {
    return activeSession?.isBreakActive == true
  }

  var isBreakAvailable: Bool {
    return activeSession?.isBreakAvailable ?? false
  }

  // SECURITY: NFC strategy IDs that require physical card tap to unlock.
  // Used to enforce the core promise: "Only the physical card can unlock."
  private static let nfcStrategyIds: Set<String> = [
    NFCBlockingStrategy.id,
    NFCTimerBlockingStrategy.id,
    NFCManualBlockingStrategy.id,
  ]

  /// Returns true if the given strategy ID requires an NFC card tap to stop.
  func isNFCStrategy(_ strategyId: String) -> Bool {
    return StrategyManager.nfcStrategyIds.contains(strategyId)
  }

  // Timer strategy IDs that use a duration-based timer.
  // These conflict with schedules — only one time-based mechanism should be active.
  private static let timerStrategyIds: Set<String> = [
    NFCTimerBlockingStrategy.id,
    ShortcutTimerBlockingStrategy.id,
  ]

  /// Returns true if the given strategy ID uses a duration-based timer.
  static func isTimerStrategy(_ strategyId: String) -> Bool {
    return timerStrategyIds.contains(strategyId)
  }

  func defaultReminderMessage(forProfile profile: BlockedProfiles?) -> String {
    let baseMessage = "Get back to productivity"
    guard let profile else {
      return baseMessage
    }
    return baseMessage + " by enabling \(profile.name)"
  }

  func loadActiveSession(context: ModelContext) {
    let previousSession = activeSession
    activeSession = getActiveSession(context: context)

    DebugLogStore.log(
      "loadActiveSession",
      "previousSession.isActive=\(previousSession?.isActive ?? false) previousId=\(previousSession?.id ?? "nil") activeSession.isActive=\(activeSession?.isActive ?? false) activeId=\(activeSession?.id ?? "nil") activeStrategyShared=\(SharedData.getActiveStrategySharedSession()?.id ?? "nil") activeScheduleShared=\(SharedData.getActiveScheduleSharedSession()?.id ?? "nil")"
    )

    if activeSession?.isActive == true {
      // MARK: - Restore restrictions on launch
      // ManagedSettingsStore restrictions are process-scoped and lost on restart.
      // Re-apply the block immediately whenever we find an active session on load.
      if let session = activeSession {
        let strategyId = session.blockedProfile.blockingStrategyId ?? ManualBlockingStrategy.id

        // For timer-based strategies, the DeviceActivity extension fires timer expiry
        // independently. If the app was killed before the extension could propagate the
        // end back to SwiftData, the session may still appear active even though its
        // planned duration has fully elapsed. Detect and close it here rather than
        // re-blocking the user's phone for a session that should already be over.
        if StrategyManager.isTimerStrategy(strategyId),
          let plannedDurationMinutes = SharedData.getActiveStrategySharedSession()?.plannedDurationMinutes
            ?? {
              guard let strategyData = session.blockedProfile.strategyData else { return nil }
              return StrategyTimerData.toStrategyTimerData(from: strategyData).durationInMinutes
            }()
        {
          let plannedEndTime = session.startTime.addingTimeInterval(
            TimeInterval(plannedDurationMinutes * 60)
          )

          if Date() >= plannedEndTime {
            smLogger.info(
              "restoreOnLaunch: timer expired at \(plannedEndTime, privacy: .public) — closing stale session '\(session.id, privacy: .private)'"
            )
            session.endReason = "timer_expired"
            session.endSession()
            try? context.save()
            evaluateShareEligibility(session: session)

            appBlocker.deactivateRestrictions()
            activeSession = nil
            stopTimer()
            elapsedTime = 0
            liveActivityManager.endSessionActivity()
            DeviceActivityCenterUtil.removeAllBreakTimerActivities()
            DeviceActivityCenterUtil.removeAllStrategyTimerActivities()
            WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
            scheduleReminder(profile: session.blockedProfile)

            // Mac sync: extension's notifySessionEnded may not have fired
            // (extension was killed before delivery). Fire defensively here —
            // PATCH WHERE state=eq.active is idempotent so a double-send is
            // harmless. Without this a paired Mac stays blocked until next
            // foreground reconcile (or forever if reconcile sees stale state).
            MacSessionSyncService.shared.endSession()

            restoreScheduledSessionIfNeeded()
            return
          }
        }

        // Schedule-driven session expiry guard. Mirrors the timer-strategy block
        // above: if the schedule's wall-clock window has ended (or is currently
        // suppressed by a card tap), the SwiftData session is stale and should
        // not be re-blocked. Without this, intervalDidEnd's deactivate runs in
        // the extension but the next foreground re-applies the shield from this
        // path because syncScheduleSessions hadn't yet propagated the snapshot's
        // endTime into SwiftData (cross-process UserDefaults visibility lag).
        if session.triggerSource == "scheduled" {
          let snapshot = BlockedProfiles.getSnapshot(for: session.blockedProfile)
          let stillInWindow =
            SharedData.isScheduleCurrentlyActiveAndUnsuppressed(profile: snapshot)
          if !stillInWindow {
            smLogger.info(
              "restoreOnLaunch: schedule window ended — closing stale scheduled session '\(session.id, privacy: .private)'"
            )
            DebugLogStore.log(
              "loadActiveSession",
              "scheduleExpiryGuard: ending stale scheduled session id=\(session.id) profile=\(session.blockedProfile.name)"
            )
            session.endReason = "timer_expired"
            session.endSession()
            try? context.save()
            evaluateShareEligibility(session: session)

            appBlocker.deactivateRestrictions()
            activeSession = nil
            stopTimer()
            elapsedTime = 0
            liveActivityManager.endSessionActivity()
            DeviceActivityCenterUtil.removeAllBreakTimerActivities()
            DeviceActivityCenterUtil.removeAllStrategyTimerActivities()
            WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
            scheduleReminder(profile: session.blockedProfile)

            // Mac sync: extension's notifySessionEnded may have failed or the
            // PATCH may not have landed. Idempotent — harmless on a clean state.
            MacSessionSyncService.shared.endSession()

            restoreScheduledSessionIfNeeded()
            return
          }
        }

        // Session is still valid — re-apply ManagedSettingsStore restrictions.
        // Skip during an active break (restrictions are intentionally lifted then).
        if !session.isBreakActive {
          smLogger.info(
            "restoreOnLaunch: re-applying restrictions for '\(session.blockedProfile.name, privacy: .private)'"
          )
          DebugLogStore.log(
            "loadActiveSession",
            "reApplyRestrictions: profile=\(session.blockedProfile.name) sessionId=\(session.id) trigger=\(session.triggerSource ?? "nil")"
          )
          appBlocker.activateRestrictions(
            for: BlockedProfiles.getSnapshot(for: session.blockedProfile)
          )
        } else {
          smLogger.info("restoreOnLaunch: session in break — skipping restriction re-apply")
        }
      }

      // If a break expired while the app was in the background, handle it
      // immediately rather than waiting for the next timer tick (1 second delay).
      if let session = activeSession, session.isBreakActive,
        let breakStartTime = session.breakStartTime
      {
        let breakDuration = TimeInterval(session.blockedProfile.breakTimeInMinutes * 60)
        let elapsed = Date().timeIntervalSince(breakStartTime)
        if elapsed >= breakDuration {
          handleBreakExpired(session: session)
        }
      }

      startTimer()

      // Start live activity for existing session if one exists
      // live activities can only be started when the app is in the foreground
      if let session = activeSession {
        liveActivityManager.startSessionActivity(session: session)
      }
    } else {
      // Session ended while app was in background (e.g. strategy timer expired)
      // Clean up all session state
      let hadPreviouslyActiveSession = previousSession?.isActive == true

      if hadPreviouslyActiveSession {
        appBlocker.deactivateRestrictions()
        // Mac sync: out-of-band session end (extension may have fired
        // notifySessionEnded already, or may have failed). Fire defensively —
        // idempotent PATCH on no-active-rows is harmless.
        MacSessionSyncService.shared.endSession()
        evaluateShareEligibility(session: previousSession)
      }

      activeSession = nil
      stopTimer()
      elapsedTime = 0
      liveActivityManager.endSessionActivity()

      // Clean up device activity timers
      DeviceActivityCenterUtil.removeAllBreakTimerActivities()
      DeviceActivityCenterUtil.removeAllStrategyTimerActivities()

      // Refresh widgets when session ends
      WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

      // Schedule reminder if a session was previously active
      if let endedProfile = previousSession?.blockedProfile {
        scheduleReminder(profile: endedProfile)
      }

      restoreScheduledSessionIfNeeded()
    }
  }

  /// Eligibility:
  ///   - endReason is "card_tap" or "timer_expired" (not emergency_unlock, not nil)
  ///   - duration ≥ 30 minutes
  ///   - user has not turned off the prompt in Settings (`askToShareAfterSession`)
  /// Sets `pendingShareSession` to a value-type snapshot for HomeView to observe.
  private func evaluateShareEligibility(session: BlockedProfileSession?) {
    guard let session,
          let reason = session.endReason,
          reason == "card_tap" || reason == "timer_expired"
    else { return }

    // TEST: lowered to 60s for easier QA — revert to 1800 (30 min) before ship.
    guard session.duration >= 60 else { return }

    // @AppStorage default is true; explicit object check preserves that default.
    let askEnabled = UserDefaults.standard.object(forKey: "askToShareAfterSession") as? Bool ?? true
    guard askEnabled else { return }

    pendingShareSession = ShareableSession(
      profileName: session.blockedProfile.name,
      duration: session.duration
    )
  }

  func handleProfileDeletion(_ profile: BlockedProfiles, context: ModelContext) {
    guard let currentActiveSession = getActiveSession(context: context) else {
      return
    }

    guard currentActiveSession.blockedProfile.id == profile.id else {
      return
    }

    smLogger.info(
      "handleProfileDeletion: clearing active restrictions for '\(profile.name, privacy: .private)'"
    )

    appBlocker.deactivateRestrictions()
    activeSession = nil
    stopTimer()
    elapsedTime = 0
    liveActivityManager.endSessionActivity()
    DeviceActivityCenterUtil.removeAllBreakTimerActivities()
    DeviceActivityCenterUtil.removeAllStrategyTimerActivities()
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
  }

  func toggleBlocking(context: ModelContext, activeProfile: BlockedProfiles?) {
    guard !isToggling else { return }
    isToggling = true

    if isBlocking {
      stopBlocking(context: context)
    } else {
      startBlocking(context: context, activeProfile: activeProfile)
    }

    // Reset after a short delay to allow the NFC dialog to appear.
    // For non-NFC strategies that complete synchronously, this is
    // effectively immediate.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.isToggling = false
    }
  }

  /// Long-press "開始專注" entry point: triggers an NFC scan first, then starts the session
  /// on successful card read. Cancel or error → no session started, no state changed.
  func startSessionWithNFCScan(context: ModelContext, profile: BlockedProfiles) {
    guard !isToggling else { return }
    isToggling = true

    let scanner = NFCScannerUtil()
    pendingNFCScanner = scanner  // retain across async NFC session

    scanner.onTagScanned = { [weak self] result in
      guard let self else { return }
      self.isNFCScanInProgress = false
      self.activeCardName = result.cardName
      self.pendingNFCScanner = nil
      self.startBlocking(context: context, activeProfile: profile)
    }
    scanner.onError = { [weak self] _ in
      guard let self else { return }
      self.isNFCScanInProgress = false
      self.pendingNFCScanner = nil
      self.isToggling = false
    }
    scanner.onCancel = { [weak self] in
      guard let self else { return }
      self.isNFCScanInProgress = false
      self.pendingNFCScanner = nil
      self.isToggling = false
    }

    isNFCScanInProgress = true
    scanner.scan(profileName: profile.name, isUnlocking: false)

    // Mirror toggleBlocking's defensive reset, but only clear the guard if
    // nothing is actively happening anymore.
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
      self?.resetPendingStartIfIdle()
    }
  }

  /// Cancels an in-progress NFC scan started by `startSessionWithNFCScan`.
  /// Releasing `pendingNFCScanner` triggers `NFCScannerUtil.deinit` → `nfcSession?.invalidate()`,
  /// which closes the system NFC dialog. Used by the onboarding tutorial Step 5 timeout.
  func cancelPendingNFCScan() {
    pendingNFCScanner = nil  // deinit → nfcSession?.invalidate() → dialog closes
    isNFCScanInProgress = false
    isToggling = false
  }

  func cancelPendingStart() {
    resetPendingStartIfIdle(force: true)
  }

  /// Card-image tap entry point: bypasses NFC and starts the session immediately.
  /// triggerSource = "manual" → Focus Score weight = 1.0 (same as physical card tap).
  func forceStartSession(context: ModelContext, profile: BlockedProfiles) {
    guard !isToggling, !isBlocking else { return }
    isToggling = true

    // Audit log: distinguishes force-start (no physical card tap) from card-tap starts
    context.insert(NFCTapEvent(
      action: NFCTapEvent.actionForceStart,
      profileId: profile.id,
      profileName: profile.name
    ))

    // pendingTriggerSource defaults to "manual" → Focus Score weight = 1.0
    let manualStrategy = getStrategy(id: ManualBlockingStrategy.id)
    _ = manualStrategy.startBlocking(
      context: context,
      profile: profile,
      forceStart: true
    )
  }

  func toggleBreak(context: ModelContext) {
    guard let session = activeSession else {
      smLogger.warning("active session does not exist")
      return
    }

    if session.isBreakActive {
      stopBreak(context: context)
    } else {
      startBreak(context: context)
    }
  }

  func startTimer() {
    // Invalidate any existing timer before creating a new one to prevent accumulation
    timer?.invalidate()
    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      guard let self, let session = self.activeSession else { return }

      if session.isBreakActive {
        // Calculate break time remaining (countdown)
        guard let breakStartTime = session.breakStartTime else { return }
        let timeSinceBreakStart = Date().timeIntervalSince(breakStartTime)
        let breakDurationInSeconds = TimeInterval(session.blockedProfile.breakTimeInMinutes * 60)
        let remaining = breakDurationInSeconds - timeSinceBreakStart
        self.elapsedTime = max(0, remaining)

        // Break time expired — automatically end the break and return to focus
        if remaining <= 0 {
          self.handleBreakExpired(session: session)
        }
      } else {
        // Calculate session elapsed time
        let rawElapsedTime = Date().timeIntervalSince(session.startTime)
        let breakDuration = self.calculateBreakDuration()
        self.elapsedTime = rawElapsedTime - breakDuration
      }
    }
  }

  func stopTimer() {
    timer?.invalidate()
    timer = nil
  }

  /// Called by the timer when break duration has elapsed.
  /// Updates the in-memory session and re-activates restrictions so the UI
  /// transitions back to the focus state automatically.
  private func handleBreakExpired(session: BlockedProfileSession) {
    // Guard against being called more than once
    guard session.breakEndTime == nil else { return }

    // End break on the in-memory session (also persists to SharedData)
    session.endBreak()

    // Re-activate app restrictions
    let profile = session.blockedProfile
    appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: profile))

    // Clean up the break timer activity
    DeviceActivityCenterUtil.removeBreakTimerActivity(for: profile)

    // Cancel break notifications
    timersUtil.cancelAllNotifications()

    // Refresh widgets
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

    // Update live activity to show focus state
    liveActivityManager.updateBreakState(session: session)

    smLogger.info("Break expired automatically, returned to focus mode")
  }

  private func calculateBreakDuration() -> TimeInterval {
    guard let session = activeSession else {
      return 0
    }

    guard let breakStartTime = session.breakStartTime else {
      return 0
    }

    if let breakEndTime = session.breakEndTime {
      return breakEndTime.timeIntervalSince(breakStartTime)
    }

    return 0
  }

  func toggleSessionFromDeeplink(
    _ profileId: String,
    url: URL,
    context: ModelContext
  ) {
    guard let profileUUID = UUID(uuidString: profileId) else {
      self.errorMessage = "failed to parse profile in tag"
      return
    }

    do {
      guard
        let profile: BlockedProfiles = try BlockedProfiles.findProfile(
          byID: profileUUID,
          in: context
        )
      else {
        self.errorMessage =
          "Failed to find a profile stored locally that matches the tag"
        return
      }

      if let localActiveSession = getActiveSession(context: context) {
        // SECURITY (V-02): Check if the active session uses an NFC strategy.
        // Deep links cannot trigger NFC scanning, so refuse to stop NFC sessions.
        let strategyId =
          localActiveSession.blockedProfile.blockingStrategyId ?? ManualBlockingStrategy.id
        if isNFCStrategy(strategyId) {
          self.errorMessage = String(
            localized: "This mode requires your DO Card to unlock. Please tap your DO Card.")
          return
        }

        let strategy = getStrategy(id: strategyId)
        _ = strategy.stopBlocking(
          context: context,
          session: localActiveSession
        )

        if localActiveSession.blockedProfile.id != profile.id {
          smLogger.info("User is switching sessions from deep link")

          pendingTriggerSource = "deeplink"
          let manualStrategy = getStrategy(id: ManualBlockingStrategy.id)
          _ = manualStrategy.startBlocking(
            context: context,
            profile: profile,
            forceStart: true
          )
        }
      } else {
        pendingTriggerSource = "deeplink"
        let manualStrategy = getStrategy(id: ManualBlockingStrategy.id)
        _ = manualStrategy.startBlocking(
          context: context,
          profile: profile,
          forceStart: true
        )
      }
    } catch {
      self.errorMessage = "Something went wrong fetching profile"
    }
  }

  func startSessionFromBackground(
    _ profileId: UUID,
    context: ModelContext,
    durationInMinutes: Int? = nil
  ) {
    do {
      guard
        let profile = try BlockedProfiles.findProfile(
          byID: profileId,
          in: context
        )
      else {
        self.errorMessage =
          "Failed to find a profile stored locally that matches the tag"
        return
      }

      if let localActiveSession = getActiveSession(context: context) {
        smLogger.info("session is already active for profile: \(localActiveSession.blockedProfile.name, privacy: .private), not starting a new one")
        return
      }

      if let duration = durationInMinutes {
        if duration < 15 || duration > 1440 {
          self.errorMessage = "Duration must be between 15 and 1440 minutes"
          return
        }

        if let strategyTimerData = StrategyTimerData.toData(
          from: StrategyTimerData(durationInMinutes: duration, hideStopButton: false)
        ) {
          profile.strategyData = strategyTimerData
          profile.updatedAt = Date()
          BlockedProfiles.updateSnapshot(for: profile)
          try context.save()
        }

        pendingTriggerSource = "shortcut"
        let shortcutTimerStrategy = getStrategy(id: ShortcutTimerBlockingStrategy.id)
        _ = shortcutTimerStrategy.startBlocking(
          context: context,
          profile: profile,
          forceStart: true
        )
      } else {
        pendingTriggerSource = "shortcut"
        let manualStrategy = getStrategy(id: ManualBlockingStrategy.id)
        _ = manualStrategy.startBlocking(
          context: context,
          profile: profile,
          forceStart: true
        )
      }
    } catch {
      self.errorMessage = "Something went wrong fetching profile"
    }
  }

  func stopSessionFromBackground(
    _ profileId: UUID,
    context: ModelContext
  ) {
    do {
      guard
        let profile = try BlockedProfiles.findProfile(
          byID: profileId,
          in: context
        )
      else {
        self.errorMessage =
          "Failed to find a profile stored locally that matches the tag"
        return
      }

      guard let localActiveSession = getActiveSession(context: context) else {
        smLogger.info("session is not active for profile: \(profile.name, privacy: .private), not stopping it")
        return
      }

      if localActiveSession.blockedProfile.id != profile.id {
        smLogger.info("session is not active for profile: \(profile.name, privacy: .private), not stopping it")
        self.errorMessage =
          "session is not active for profile: \(profile.name), not stopping it"
        return
      }

      // SECURITY (V-01): Check if the active session uses an NFC strategy.
      // Background contexts (Siri Shortcuts, Intents) cannot trigger NFC UI,
      // so refuse to stop NFC-based sessions from background.
      let strategyId =
        localActiveSession.blockedProfile.blockingStrategyId ?? ManualBlockingStrategy.id
      if isNFCStrategy(strategyId) {
        self.errorMessage = String(
          localized: "This mode requires your DO Card to unlock. Please tap your DO Card.")
        return
      }

      let strategy = getStrategy(id: strategyId)
      let _ = strategy.stopBlocking(
        context: context,
        session: localActiveSession
      )
    } catch {
      self.errorMessage = "Something went wrong fetching profile"
    }
  }

  func getRemainingEmergencyUnblocks() -> Int {
    return emergencyUnblocksRemaining
  }

  func emergencyUnblock(context: ModelContext) {
    // Do not allow emergency unblocks if there are no remaining
    if emergencyUnblocksRemaining == 0 {
      return
    }

    // Do not allow emergency unblocks if there is no active session
    guard let activeSession = getActiveSession(context: context) else {
      return
    }

    // Capture session duration before stopBlocking sets endTime
    let sessionDuration = Date().timeIntervalSince(activeSession.startTime)

    // Set end reason before stopBlocking persists the session
    activeSession.endReason = "emergency_unlock"

    // Stop the active session using the manual strategy, by passes any other strategy in view
    let manualStrategy = getStrategy(id: ManualBlockingStrategy.id)
    _ = manualStrategy.stopBlocking(
      context: context,
      session: activeSession
    )

    // EMERGENCY_UNLOCK_AUDIT: suppress extension re-block for the current
    // scheduled window without stopping the repeating monitor itself.
    suppressScheduledReblockIfNeeded(for: activeSession)

    // Defensive reset: the happy path relies on onSessionCreation(.ended) firing synchronously
    // inside stopBlocking() above to nil activeSession and stop the timer. If that chain is
    // interrupted for any reason (e.g. save error, ARC timing), this fallback prevents a zombie
    // state where the UI shows blocking-active but Screen Time is already deactivated.
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.activeSession?.isActive != true {
        self.activeSession = nil
        self.elapsedTime = 0
      }
    }

    // Log the emergency unlock event
    context.insert(EmergencyUnlockEvent(
      sessionId: activeSession.id,
      profileId: activeSession.blockedProfile.id,
      sessionDuration: sessionDuration
    ))
    // EMERGENCY_UNLOCK_AUDIT: explicit save to avoid losing the audit event
    // if the app exits immediately after a successful unlock.
    try? context.save()

    // Do end sections for the profile
    self.liveActivityManager.endSessionActivity()
    // scheduleReminder is intentionally omitted here — the onSessionCreation(.ended) callback
    // already calls it. Calling it again would schedule a duplicate reminder notification.
    self.stopTimer()

    // Decrement the remaining emergency unblocks
    emergencyUnblocksRemaining -= 1

    // Refresh widgets when emergency unblock ends session
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")
  }

  func resetEmergencyUnblocks() {
    emergencyUnblocksRemaining = 3
    lastEmergencyUnblocksResetDateTimestamp = Date().timeIntervalSinceReferenceDate
  }

  func checkAndResetEmergencyUnblocks() {
    // Initialize the last reset date if it hasn't been set
    if lastEmergencyUnblocksResetDateTimestamp == 0 {
      lastEmergencyUnblocksResetDateTimestamp = Date().timeIntervalSinceReferenceDate
      return
    }

    let lastResetDate = Date(
      timeIntervalSinceReferenceDate: lastEmergencyUnblocksResetDateTimestamp)
    let nextResetDate = Calendar.current.date(byAdding: .month, value: 1, to: lastResetDate) ?? lastResetDate

    if Date() >= nextResetDate {
      emergencyUnblocksRemaining = 3
      lastEmergencyUnblocksResetDateTimestamp = Date().timeIntervalSinceReferenceDate
    }
  }

  func getNextResetDate() -> Date? {
    guard lastEmergencyUnblocksResetDateTimestamp > 0 else {
      return nil
    }

    let lastResetDate = Date(
      timeIntervalSinceReferenceDate: lastEmergencyUnblocksResetDateTimestamp)
    return Calendar.current.date(byAdding: .month, value: 1, to: lastResetDate)
  }

  /// Creates a fresh strategy instance for the given ID.
  /// Each call returns a new instance to avoid shared-state bugs where
  /// callbacks on a singleton get overwritten by concurrent calls.
  static func getStrategyFromId(id: String) -> BlockingStrategy {
    switch id {
    case NFCBlockingStrategy.id:
      return NFCBlockingStrategy()
    case NFCTimerBlockingStrategy.id:
      return NFCTimerBlockingStrategy()
    case ManualBlockingStrategy.id:
      return ManualBlockingStrategy()
    case NFCManualBlockingStrategy.id:
      return NFCManualBlockingStrategy()
    case ShortcutTimerBlockingStrategy.id:
      return ShortcutTimerBlockingStrategy()
    default:
      return NFCBlockingStrategy()
    }
  }

  func getStrategy(id: String) -> BlockingStrategy {
    var strategy = StrategyManager.getStrategyFromId(id: id)

    strategy.onSessionCreation = { [weak self] session in
      guard let self else { return }
      self.isToggling = false
      self.activeStrategy = nil
      self.dismissView()

      // Remove any timers and notifications that were scheduled
      self.timersUtil.cancelAll()

      switch session {
      case .started(let session):
        // Apply pending triggerSource from the call site
        session.triggerSource = self.pendingTriggerSource
        self.pendingTriggerSource = "manual" // reset default

        // Update the snapshot of the profile in case some settings were changed
        BlockedProfiles.updateSnapshot(for: session.blockedProfile)

        self.errorMessage = nil

        self.activeSession = session
        self.startTimer()
        self.liveActivityManager
          .startSessionActivity(session: session)

        // Refresh widgets when session starts
        WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

        // Notify any paired Mac (Chrome Extension) — fire-and-forget; failures
        // here must never block the iPhone-side Screen Time flow.
        MacSessionSyncService.shared.startSession()
      case .ended(let endedProfile):
        // Capture before nil-ing so we can evaluate share eligibility on the just-ended session.
        let endedSession = self.activeSession
        self.activeSession = nil
        self.liveActivityManager.endSessionActivity()
        self.scheduleReminder(profile: endedProfile)
        self.evaluateShareEligibility(session: endedSession)

        self.stopTimer()
        self.elapsedTime = 0

        // Refresh widgets when session ends
        WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

        // Tell paired Mac the session ended; failures are queued for retry so
        // the user's Mac doesn't stay blocked forever after a network blip.
        MacSessionSyncService.shared.endSession()

        // Remove all break timer activities
        DeviceActivityCenterUtil.removeAllBreakTimerActivities()

        // Remove all strategy timer activities
        DeviceActivityCenterUtil.removeAllStrategyTimerActivities()

        self.restoreScheduledSessionIfNeeded()
      }
    }

    strategy.onErrorMessage = { [weak self] message in
      guard let self else { return }
      self.isToggling = false
      self.activeStrategy = nil
      self.dismissView()

      // Empty message means user cancelled (e.g. dismissed NFC dialog) — don't show error
      if !message.isEmpty {
        self.errorMessage = message
      }
    }

    strategy.onCardNameScanned = { [weak self] name in
      self?.activeCardName = name
    }

    // Retain the strategy so it survives async NFC scanning
    self.activeStrategy = strategy

    return strategy
  }

  private func startBreak(context: ModelContext) {
    guard let session = activeSession else {
      smLogger.warning("Breaks only available in active session")
      return
    }

    if !session.isBreakAvailable {
      smLogger.warning("Breaks is not availble")
      return
    }

    // Set break start time directly on the session and SharedData.
    // The DeviceActivity monitor runs in a separate extension process and its
    // intervalDidStart may not fire reliably (the schedule starts at 00:00,
    // which has already passed), so we must set the state here.
    session.startBreak()
    appBlocker.deactivateRestrictions()
    do {
      try context.save()
    } catch {
      smLogger.error("Failed to save break start: \(error.localizedDescription)")
    }

    // Start the break timer activity (handles auto-ending the break when time expires)
    DeviceActivityCenterUtil.startBreakTimerActivity(for: session.blockedProfile)

    // Schedule a reminder to get back to the profile after the break
    scheduleBreakReminder(profile: session.blockedProfile)

    // Refresh widgets when break starts
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

    // Update live activity to show break state
    liveActivityManager.updateBreakState(session: session)
  }

  private func stopBreak(context: ModelContext) {
    guard let session = activeSession else {
      smLogger.warning("Breaks only available in active session")
      return
    }

    if !session.isBreakAvailable {
      smLogger.warning("Breaks is not availble")
      return
    }

    // End break directly on the session and re-activate restrictions.
    // Same reasoning as startBreak — we cannot rely on the DeviceActivity
    // monitor's intervalDidEnd to set state synchronously.
    session.endBreak()
    appBlocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: session.blockedProfile))
    do {
      try context.save()
    } catch {
      smLogger.error("Failed to save break end: \(error.localizedDescription)")
    }

    // Remove the break timer activity
    DeviceActivityCenterUtil.removeBreakTimerActivity(for: session.blockedProfile)

    // Cancel all notifications that were scheduled during break
    timersUtil.cancelAllNotifications()

    // Refresh widgets when break ends
    WidgetCenter.shared.reloadTimelines(ofKind: "ProfileControlWidget")

    // Update live activity to show break has ended
    liveActivityManager.updateBreakState(session: session)
  }

  private func dismissView() {
    showCustomStrategyView = false
    customStrategyView = nil
  }

  private func resetPendingStartIfIdle(force: Bool = false) {
    let isIdle =
      !isBlocking
      && !isNFCScanInProgress
      && !showCustomStrategyView

    guard force || isIdle else { return }

    isToggling = false
    activeStrategy = nil
  }

  private func getActiveSession(context: ModelContext)
    -> BlockedProfileSession?
  {
    // Before fetching the active session, sync any schedule sessions
    syncScheduleSessions(context: context)

    return
      BlockedProfileSession
      .mostRecentActiveSession(in: context)
  }

  private func syncScheduleSessions(context: ModelContext) {
    // Process active strategy sessions first, since they are the authoritative
    // foreground session while schedules are intentionally suppressed underneath.
    if let activeStrategySession = SharedData.getActiveStrategySharedSession() {
      DebugLogStore.log(
        "syncScheduleSessions",
        "upserting activeStrategySession id=\(activeStrategySession.id) endTime=\(activeStrategySession.endTime?.description ?? "nil")"
      )
      BlockedProfileSession.upsertSessionFromSnapshot(
        in: context,
        withSnapshot: activeStrategySession
      )
    } else if let activeScheduledSession = SharedData.getActiveScheduleSharedSession() {
      DebugLogStore.log(
        "syncScheduleSessions",
        "upserting activeScheduledSession id=\(activeScheduledSession.id) endTime=\(activeScheduledSession.endTime?.description ?? "nil")"
      )
      BlockedProfileSession.upsertSessionFromSnapshot(
        in: context,
        withSnapshot: activeScheduledSession
      )
    }

    // Process any completed scheduled sessions
    let completedScheduleSessions = SharedData.getCompletedSessionsForSchedular()
    DebugLogStore.log(
      "syncScheduleSessions",
      "completedSessionsCount=\(completedScheduleSessions.count)"
    )
    for completedScheduleSession in completedScheduleSessions {
      DebugLogStore.log(
        "syncScheduleSessions",
        "upserting completedSession id=\(completedScheduleSession.id) endTime=\(completedScheduleSession.endTime?.description ?? "nil") endReason=\(completedScheduleSession.endReason ?? "nil")"
      )
      BlockedProfileSession.upsertSessionFromSnapshot(
        in: context,
        withSnapshot: completedScheduleSession
      )
    }

    // Flush completed scheduled sessions
    SharedData.flushCompletedSessionsForSchedular()
  }

  private func resultFromURL(_ url: String) -> NFCResult {
    return NFCResult(id: url, payload: url, DateScanned: Date())
  }

  private func startBlocking(
    context: ModelContext,
    activeProfile: BlockedProfiles?
  ) {
    guard let definedProfile = activeProfile else {
      smLogger.warning("No active profile found, calling stop blocking with no session")
      return
    }

    if let strategyId = definedProfile.blockingStrategyId {
      let snapshot = BlockedProfiles.getSnapshot(for: definedProfile)
      if !appBlocker.wouldShieldAnything(for: snapshot) {
        let errorMessage =
          SharedData.effectiveSubscriptionTier == .free
          ? String(
            localized:
              "免費版目前只支援封鎖 App。請先選擇要封鎖的 App，才能開始專注"
          )
          : String(localized: "請先選擇要封鎖的 App，才能開始專注")

        self.errorMessage = errorMessage
        self.isToggling = false
        smLogger.warning(
          "Blocking start aborted for '\(definedProfile.name, privacy: .private)' because effective tokens are empty after tier enforcement"
        )
        return
      }

      let strategy = getStrategy(id: strategyId)
      let view = strategy.startBlocking(
        context: context,
        profile: definedProfile,
        forceStart: false
      )

      if let customView = view {
        showCustomStrategyView = true
        customStrategyView = customView
      }
    }
  }

  private func stopBlocking(context: ModelContext) {
    guard let session = activeSession else {
      smLogger.warning("No active session found, calling stop blocking with no session")
      return
    }

    if let strategyId = session.blockedProfile.blockingStrategyId {
      let strategy = getStrategy(id: strategyId)
      let view = strategy.stopBlocking(context: context, session: session)

      if let customView = view {
        showCustomStrategyView = true
        customStrategyView = customView
      }
    }
  }

  private func scheduleReminder(profile: BlockedProfiles) {
    guard let reminderTimeInSeconds = profile.reminderTimeInSeconds else {
      return
    }

    let profileName = profile.name
    let message = profile.customReminderMessage ?? defaultReminderMessage(forProfile: profile)
    timersUtil
      .scheduleNotification(
        title: profileName + " time!",
        message: message,
        seconds: TimeInterval(reminderTimeInSeconds)
      )
  }

  private func scheduleBreakReminder(profile: BlockedProfiles) {
    let profileName = profile.name

    // Schedule a reminder to let the user know that the break is about to end
    let breakNotificationTimeInSeconds = UInt32((profile.breakTimeInMinutes - 1) * 60)
    if breakNotificationTimeInSeconds > 0 {
      timersUtil.scheduleNotification(
        title: "Break almost over!",
        message: "Hope you enjoyed your break, starting " + profileName + " in a 1 minute.",
        seconds: TimeInterval(breakNotificationTimeInSeconds)
      )
    }

    // Schedule a notification at the exact break end time so the user is alerted
    // even if they are inside a temporarily unlocked app (where the main app timer
    // cannot fire because the app is suspended in the background).
    let breakEndTimeInSeconds = TimeInterval(profile.breakTimeInMinutes * 60)
    timersUtil.scheduleNotification(
      title: profileName + " break ended",
      message: "Your apps are locked again. Time to focus!",
      seconds: breakEndTimeInSeconds
    )
  }

  func cleanUpGhostSchedules(context: ModelContext) {
    let allActivities = DeviceActivityCenterUtil.getDeviceActivities()
    let scheduleTimerActivity = ScheduleTimerActivity()
    let scheduleActivities = scheduleTimerActivity.getAllScheduleTimerActivities(
      from: allActivities)

    smLogger.debug("Found \(scheduleActivities.count) schedule timer activities out of \(allActivities.count) total activities")

    for activity in scheduleActivities {
      let rawValue = activity.rawValue
      guard let profileIdString = scheduleTimerActivity.extractProfileId(from: activity),
        let profileId = UUID(uuidString: profileIdString)
      else {
        smLogger.error("Unexpected: failed to parse profile id from filtered activity: \(rawValue, privacy: .private)")
        continue
      }

      do {
        if let profile = try BlockedProfiles.findProfile(byID: profileId, in: context) {
          if profile.schedules.isEmpty {
            smLogger.warning("Profile '\(profile.name, privacy: .private)' has no schedules but has device activity registered. Removing ghost schedule...")
            DeviceActivityCenterUtil.removeScheduleTimerActivities(for: profile)
          } else {
            smLogger.debug("Profile '\(profile.name, privacy: .private)' has schedules - activity is valid")
          }
        } else {
          // Profile truly doesn't exist in database
          smLogger.warning("No profile found for activity \(rawValue, privacy: .private). Removing orphaned schedule...")
          DeviceActivityCenterUtil.removeScheduleTimerActivities(for: activity)
        }
      } catch {
        // Database error occurred - do NOT delete the schedule since we don't know the true state
        smLogger.error("Error fetching profile \(rawValue, privacy: .private): \(error.localizedDescription). Skipping cleanup for safety.")
      }
    }
  }

  func restoreScheduledSessionIfNeeded() {
    cleanUpExpiredScheduleSuppressions()

    guard activeSession == nil else {
      smLogger.debug("restoreScheduledSessionIfNeeded: active manual/NFC session present — skipping scheduled restore")
      return
    }

    if let activeScheduledSession = SharedData.getActiveScheduleSharedSession() {
      let profileId = activeScheduledSession.blockedProfileId.uuidString

      guard let profile = SharedData.snapshot(for: profileId) else {
        smLogger.warning(
          "restoreScheduledSessionIfNeeded: snapshot missing for shared schedule session profile '\(profileId, privacy: .private)' — flushing stale session"
        )
        SharedData.flushActiveScheduleSession()
        return
      }

      guard SharedData.isScheduleCurrentlyActiveAndUnsuppressed(profile: profile) else {
        smLogger.info(
          "restoreScheduledSessionIfNeeded: no active schedule window for '\(profile.name, privacy: .private)' — ending stale shared session"
        )
        SharedData.endActiveScheduleSharedSession()
        return
      }

      smLogger.info(
        "restoreScheduledSessionIfNeeded: re-applying scheduled restrictions for '\(profile.name, privacy: .private)'"
      )
      DebugLogStore.log(
        "restoreScheduledSessionIfNeeded",
        "branch=existingSharedSession reApply profile=\(profile.name)"
      )
      appBlocker.activateRestrictions(for: profile)
      // Mac sync: schedule resumed in-app (no extension callback fires here),
      // so paired Macs need an explicit start signal.
      MacSessionSyncService.shared.startSession()
      return
    }

    guard let profile = SharedData.currentScheduledProfileSnapshot() else {
      smLogger.debug("restoreScheduledSessionIfNeeded: no schedule currently in window")
      return
    }

    SharedData.createSessionForSchedular(for: profile.id)

    smLogger.info(
      "restoreScheduledSessionIfNeeded: re-applying scheduled restrictions for '\(profile.name, privacy: .private)'"
    )
    DebugLogStore.log(
      "restoreScheduledSessionIfNeeded",
      "branch=newWindow reApply profile=\(profile.name)"
    )
    appBlocker.activateRestrictions(for: profile)
    // Mac sync: same as above — schedule activated in-app, not via extension.
    MacSessionSyncService.shared.startSession()
  }

  private func suppressScheduledReblockIfNeeded(for session: BlockedProfileSession) {
    SharedData.writeEmergencyUnlockSuppressionFlags(
      for: BlockedProfiles.getSnapshot(for: session.blockedProfile),
      triggerSource: session.triggerSource
    )
  }

  private func cleanUpExpiredScheduleSuppressions(
    now: Date = Date(),
    suite: UserDefaults? = UserDefaults(suiteName: "group.DO.version3")
  ) {
    suite?.dictionaryRepresentation().keys
      .filter { key in
        Self.scheduleSuppressionPrefixes.contains { prefix in
          key.hasPrefix(prefix)
        }
      }
      .forEach { key in
        guard let timestamp = suite?.object(forKey: key) as? Data else {
          suite?.removeObject(forKey: key)
          suite?.removeObject(forKey: key + ".hmac")
          return
        }

        let decodedTimestamp = (try? JSONDecoder().decode(Double.self, from: timestamp)) ?? 0
        if now >= Date(timeIntervalSince1970: decodedTimestamp) {
          suite?.removeObject(forKey: key)
          suite?.removeObject(forKey: key + ".hmac")
        }
      }
  }

  func reconcileScheduleRegistrations(context: ModelContext) {
    do {
      let profiles = try context.fetch(FetchDescriptor<BlockedProfiles>())

      guard !profiles.isEmpty else {
        smLogger.debug("reconcileScheduleRegistrations: no profiles found")
        return
      }

      for profile in profiles {
        guard profile.scheduleIsOutOfSync else { continue }

        smLogger.info(
          "reconcileScheduleRegistrations: re-registering schedules for '\(profile.name, privacy: .private)'"
        )

        do {
          try DeviceActivityCenterUtil.scheduleTimerActivities(for: profile)
        } catch {
          smLogger.error(
            "reconcileScheduleRegistrations: failed to re-register '\(profile.name, privacy: .private)': \(error.localizedDescription)"
          )
        }
      }
    } catch {
      smLogger.error(
        "reconcileScheduleRegistrations: failed to fetch profiles: \(error.localizedDescription)"
      )
    }
  }

  func resetBlockingState(context: ModelContext) {
    guard !isBlocking else {
      smLogger.warning("Cannot reset blocking state while a profile is active")
      return
    }

    smLogger.info("Resetting blocking state...")

    // Clean up ghost schedules
    cleanUpGhostSchedules(context: context)

    // Clear all restrictions
    appBlocker.deactivateRestrictions()

    // Remove all break timer activities
    DeviceActivityCenterUtil.removeAllBreakTimerActivities()

    // Remove all strategy timer activities
    DeviceActivityCenterUtil.removeAllStrategyTimerActivities()

    smLogger.info("Blocking state reset complete")
  }
}
