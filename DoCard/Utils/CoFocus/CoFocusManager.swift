import Combine
import Foundation
import OSLog
import Supabase

private let log = Logger(subsystem: "online.do.card.app", category: "CoFocusManager")

/// Co-focus pairing state machine + Supabase Realtime + NFC-tap hook.
///
/// Architecture overview:
///  - Anonymous Auth on first launch → JWT auto-stored by SDK in Keychain.
///    `auth.uid()` is the device's persistent identity for this feature.
///  - All writes go through SECURITY DEFINER RPCs (see Migration 3).
///  - Realtime subscription on `pairing_sessions` filtered to the user's
///    current pairing id; falls back to REST refresh on each event for
///    payload-decoding robustness.
///  - Subscribes to `StrategyManager.shared.$activeSession` (Combine) to
///    bridge NFC-tap → tap_card RPC and NFC-unlock → unlock_pairing /
///    cancel_pairing RPC. The NFC trigger itself is unmodified.
@MainActor
final class CoFocusManager: ObservableObject {
  static let shared = CoFocusManager()

  // MARK: - Phase

  enum Phase: Equatable {
    case idle
    case loading
    case waitingJoin(PairingSession)
    case waitingTap(PairingSession)
    case active(PairingSession)
    case partnerEnded(PairingSession)

    var pairing: PairingSession? {
      switch self {
      case .idle, .loading: return nil
      case .waitingJoin(let p), .waitingTap(let p), .active(let p), .partnerEnded(let p):
        return p
      }
    }
  }

  // MARK: - Published state

  @Published private(set) var phase: Phase = .idle
  @Published private(set) var monthlyTotal: CoFocusMonthlyTotal = .zero
  @Published private(set) var history: [PairFocusRecord] = []
  @Published private(set) var myUserId: UUID?
  @Published var lastError: String?

  /// HomeView observes this; when set true (pairing just transitioned to active),
  /// HomeView switches selectedTab to .focusPairing and resets the flag.
  @Published var shouldFocusTab: Bool = false

  // MARK: - Private

  private let client = CoFocusSupabase.shared
  private var realtimeChannel: RealtimeChannelV2?
  private var realtimeTask: Task<Void, Never>?
  private var pollTask: Task<Void, Never>?
  private var partnerEndedTimer: Task<Void, Never>?
  private var sessionObservation: AnyCancellable?
  private var lastSeenSessionActive: Bool = false
  private var didBootstrap: Bool = false

  // Sticky duration for the "夥伴已結束" overlay before we drop back to .idle.
  private static let partnerEndedStickyDuration: Duration = .seconds(10)
  // Polling fallback cadence — kicks in only when a non-idle pairing exists.
  // Belt-and-suspenders against Realtime drops; cheap (single RPC every 3s).
  private static let pollingInterval: Duration = .seconds(3)

  private init() {}

  // MARK: - Bootstrap

  /// Idempotent. Call once on app init and again on scenePhase = active.
  /// Performs Anonymous Auth sign-in if needed, then loads any in-flight pairing.
  func bootstrap() async {
    do {
      let user = try await ensureAuthenticated()
      self.myUserId = user.id
      if !didBootstrap {
        didBootstrap = true
        observeStrategyManager()
      }
      await refreshAll()
    } catch {
      log.error("bootstrap failed: \(error.localizedDescription, privacy: .public)")
      lastError = String(localized: "無法連線到伺服器")
    }
  }

  func refreshAll() async {
    await refreshActivePairing()
    await refreshMonthlyTotal()
    await refreshHistory()
  }

  // MARK: - Auth

  private func ensureAuthenticated() async throws -> User {
    if let user = client.auth.currentUser {
      return user
    }
    let response = try await client.auth.signInAnonymously()
    return response.user
  }

  // MARK: - Public actions (called from views)

  /// Initiator path: generate a 6-digit code that the partner will enter.
  func createPairing(nickname: String) async {
    let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      lastError = String(localized: "請輸入暱稱")
      return
    }
    do {
      let session: PairingSession = try await client
        .rpc("create_pairing", params: CoFocusRPC.CreatePairingParams(
          p_initiator_nickname: trimmed
        ))
        .execute()
        .value
      await applyServerState(session)
    } catch {
      lastError = friendlyError(error)
    }
  }

  /// Joiner path: claim a 6-digit code, advance to waiting_tap.
  func joinPairing(code: String, nickname: String) async {
    let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedNick = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmedCode.count == 6, trimmedCode.allSatisfy(\.isNumber) else {
      lastError = String(localized: "代碼格式錯誤")
      return
    }
    guard !trimmedNick.isEmpty else {
      lastError = String(localized: "請輸入暱稱")
      return
    }
    do {
      let session: PairingSession = try await client
        .rpc("join_pairing", params: CoFocusRPC.JoinPairingParams(
          p_code: trimmedCode,
          p_joiner_nickname: trimmedNick
        ))
        .execute()
        .value
      await applyServerState(session)
    } catch {
      lastError = friendlyError(error)
    }
  }

  /// Manual escape hatch from the active / partnerEnded overlay.
  /// Always lands the user back on the idle home, regardless of which side
  /// the pairing is on. Does NOT release ScreenTime (NFC stays in charge of that).
  ///
  ///   waitingJoin / waitingTap → cancel_pairing on server
  ///   active                   → unlock_pairing on server (writes records)
  ///   partnerEnded             → just clear local sticky UI
  ///   anything else            → already idle
  func endCoFocusFromUI() async {
    guard let pairing = phase.pairing else {
      await transitionToIdle()
      return
    }
    switch pairing.status {
    case .waitingJoin, .waitingTap:
      await cancelCurrentPairing()
    case .active:
      do {
        let updated: PairingSession = try await client
          .rpc("unlock_pairing", params: CoFocusRPC.PairingIdParams(p_pairing_id: pairing.id))
          .execute()
          .value
        await applyServerState(updated)
      } catch {
        log.error("endCoFocusFromUI/unlock failed: \(error.localizedDescription, privacy: .public)")
        // Worst case: dismiss the UI anyway so the user isn't trapped.
        await transitionToIdle()
      }
    case .completed, .cancelled, .expired, .abandoned:
      partnerEndedTimer?.cancel()
      await transitionToIdle()
    }
  }

  /// Caller-driven cancel from the UI (the "取消" button).
  /// NOTE: this does NOT release the user's ScreenTime — that stays under NFC's control.
  func cancelCurrentPairing() async {
    guard let pairing = phase.pairing else { return }
    guard pairing.status == .waitingJoin || pairing.status == .waitingTap else { return }
    do {
      let updated: PairingSession = try await client
        .rpc("cancel_pairing", params: CoFocusRPC.PairingIdParams(p_pairing_id: pairing.id))
        .execute()
        .value
      await applyServerState(updated)
    } catch {
      lastError = friendlyError(error)
    }
  }

  // MARK: - Server state ingestion

  /// Single source of truth for "given a server-side pairing row, how does the
  /// local phase change?". Called from create/join/cancel responses, REST
  /// refreshes, and Realtime updates.
  private func applyServerState(_ session: PairingSession) async {
    guard let myId = myUserId, session.isParticipant(myId) else {
      // Server returned a pairing we're no longer part of (e.g. someone else's row arrived
      // during a stale Realtime event). Just clear local state.
      await transitionToIdle()
      return
    }

    let oldPhase = phase
    let newPhase: Phase

    switch session.status {
    case .waitingJoin:
      newPhase = .waitingJoin(session)
    case .waitingTap:
      newPhase = .waitingTap(session)
    case .active:
      newPhase = .active(session)
    case .completed:
      // First-to-unlock writes records; either side reaching here = session done.
      // If partner ended (and I haven't yet), keep a "partner ended" sticky phase
      // so the UI shows the closing message before going idle.
      if session.endedByUserId != myId {
        newPhase = .partnerEnded(session)
        // Only schedule the 10s auto-idle timer when we ENTER partnerEnded.
        // Re-firing this from polling repeats would keep resetting the timer.
        if !isSameCase(oldPhase, newPhase) {
          scheduleAutoIdleAfterPartnerEnded()
          Task { await self.refreshMonthlyTotal() }
          Task { await self.refreshHistory() }
        }
      } else {
        newPhase = .idle
        if !isSameCase(oldPhase, newPhase) {
          Task { await self.refreshMonthlyTotal() }
          Task { await self.refreshHistory() }
        }
      }
    case .cancelled, .expired, .abandoned:
      newPhase = .idle
    }

    self.phase = newPhase

    // If we just transitioned into .active, signal HomeView to surface the tab.
    if case .active = newPhase, !isSameCase(oldPhase, .active(session)) {
      shouldFocusTab = true
    }

    // (Re)subscribe Realtime to the right pairing id.
    await reconcileRealtime(for: session)
    reconcilePolling()
  }

  private func transitionToIdle() async {
    self.phase = .idle
    await stopRealtime()
    reconcilePolling()
  }

  /// Polling fallback. Active whenever phase is non-idle. Belt-and-suspenders
  /// against Realtime drops (and currently the only way the active→completed
  /// partnerEnded transition is delivered, since the Supabase project's Realtime
  /// tenant has been observed to silently drop replication events).
  private func reconcilePolling() {
    let shouldPoll: Bool
    switch phase {
    case .idle, .loading: shouldPoll = false
    case .waitingJoin, .waitingTap, .active, .partnerEnded: shouldPoll = true
    }

    if shouldPoll && pollTask == nil {
      pollTask = Task { [weak self] in
        while !Task.isCancelled {
          try? await Task.sleep(for: Self.pollingInterval)
          if Task.isCancelled { return }
          await self?.refreshActivePairing()
        }
      }
    } else if !shouldPoll {
      pollTask?.cancel()
      pollTask = nil
    }
  }

  private func scheduleAutoIdleAfterPartnerEnded() {
    partnerEndedTimer?.cancel()
    partnerEndedTimer = Task { [weak self] in
      try? await Task.sleep(for: Self.partnerEndedStickyDuration)
      guard let self else { return }
      if case .partnerEnded = self.phase {
        await self.transitionToIdle()
      }
    }
  }

  // MARK: - Refreshers

  private func refreshActivePairing() async {
    do {
      let row: PairingSession? = try await client
        .rpc("get_user_active_pairing")
        .execute()
        .value
      if let row {
        await applyServerState(row)
      } else {
        await transitionToIdle()
      }
    } catch {
      log.error("refreshActivePairing failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func refreshMonthlyTotal() async {
    do {
      // RPC returns a TABLE (single-row); decode into [CoFocusMonthlyTotal].
      let rows: [CoFocusMonthlyTotal] = try await client
        .rpc("get_monthly_co_focus_total")
        .execute()
        .value
      self.monthlyTotal = rows.first ?? .zero
    } catch {
      log.error("refreshMonthlyTotal failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  func refreshHistory(limit: Int = 50) async {
    guard let myId = myUserId else { return }
    do {
      let rows: [PairFocusRecord] = try await client
        .from("pair_focus_records")
        .select()
        .eq("user_id", value: myId.uuidString)
        .order("created_at", ascending: false)
        .limit(limit)
        .execute()
        .value
      self.history = rows
    } catch {
      log.error("refreshHistory failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  // MARK: - Realtime

  private func reconcileRealtime(for session: PairingSession) async {
    // Only keep Realtime alive while the pairing is in-flight.
    guard session.status.isInFlight else {
      await stopRealtime()
      return
    }
    let currentChannelTopic = realtimeChannel?.topic
    let desiredTopic = "co_focus:\(session.id.uuidString)"
    if currentChannelTopic == desiredTopic { return }
    await stopRealtime()

    let channel = client.channel(desiredTopic)
    let updates = channel.postgresChange(
      AnyAction.self,
      schema: "public",
      table: "pairing_sessions",
      filter: "id=eq.\(session.id.uuidString)"
    )
    await channel.subscribe()
    self.realtimeChannel = channel

    self.realtimeTask = Task { [weak self] in
      for await _ in updates {
        // We could decode the payload directly, but pulling fresh state from REST
        // is simpler and keeps decoding logic in one place.
        await self?.refreshActivePairing()
      }
    }
  }

  private func stopRealtime() async {
    realtimeTask?.cancel()
    realtimeTask = nil
    if let channel = realtimeChannel {
      await channel.unsubscribe()
    }
    realtimeChannel = nil
  }

  // MARK: - StrategyManager hook (NFC-tap bridge)

  private func observeStrategyManager() {
    sessionObservation = StrategyManager.shared.$activeSession
      .receive(on: DispatchQueue.main)
      .sink { [weak self] session in
        Task { [weak self] in
          await self?.handleStrategySessionChange(isActive: session != nil)
        }
      }
  }

  private func handleStrategySessionChange(isActive: Bool) async {
    let was = lastSeenSessionActive
    lastSeenSessionActive = isActive

    guard was != isActive else { return }

    if isActive {
      // NFC just started a ScreenTime block. If we have an in-flight pairing
      // expecting taps, record this as the caller's tap.
      await handleNFCTapStarted()
    } else {
      // NFC just ended a ScreenTime block. Decide: end co-session, cancel pairing,
      // or do nothing (no in-flight co-pairing).
      await handleNFCTapEnded()
    }
  }

  private func handleNFCTapStarted() async {
    guard let myId = myUserId, let pairing = phase.pairing else { return }
    guard pairing.status == .waitingTap, !pairing.hasTapped(myId) else { return }
    do {
      let updated: PairingSession = try await client
        .rpc("tap_card", params: CoFocusRPC.PairingIdParams(p_pairing_id: pairing.id))
        .execute()
        .value
      await applyServerState(updated)
    } catch {
      // Silent: NFC trigger is the source of truth for ScreenTime; co-focus is opportunistic.
      log.error("tap_card RPC failed: \(error.localizedDescription, privacy: .public)")
    }
  }

  private func handleNFCTapEnded() async {
    guard let myId = myUserId, let pairing = phase.pairing else { return }
    switch pairing.status {
    case .active:
      // First to unlock ends the co-session.
      do {
        let updated: PairingSession = try await client
          .rpc("unlock_pairing", params: CoFocusRPC.PairingIdParams(p_pairing_id: pairing.id))
          .execute()
          .value
        await applyServerState(updated)
      } catch {
        log.error("unlock_pairing RPC failed: \(error.localizedDescription, privacy: .public)")
      }
    case .waitingTap where pairing.hasTapped(myId):
      // I tapped but unlocked before partner did → cancel the pairing.
      await cancelCurrentPairing()
    default:
      break
    }
  }

  // MARK: - Error mapping

  /// Maps Postgres / network errors into user-facing strings.
  /// Codes match Migration 3's RAISE EXCEPTION ERRCODE annotations.
  private func friendlyError(_ error: Error) -> String {
    let nsErr = error as NSError
    let message = nsErr.localizedDescription
    if message.contains("P0001") { return String(localized: "請先登入") }
    if message.contains("P0002") { return String(localized: "目前已有進行中的配對") }
    if message.contains("P0003") { return String(localized: "代碼產生失敗，請稍後再試") }
    if message.contains("P0004") { return String(localized: "找不到代碼或已過期") }
    if message.contains("P0005") { return String(localized: "找不到該配對") }
    return String(localized: "出了一點狀況，請稍後再試")
  }
}

// MARK: - Pattern-match helpers

/// True iff `lhs` and `rhs` are the same phase case, ignoring associated values.
private func isSameCase(_ lhs: CoFocusManager.Phase, _ rhs: CoFocusManager.Phase) -> Bool {
  switch (lhs, rhs) {
  case (.idle, .idle), (.loading, .loading),
       (.waitingJoin, .waitingJoin), (.waitingTap, .waitingTap),
       (.active, .active), (.partnerEnded, .partnerEnded):
    return true
  default:
    return false
  }
}
