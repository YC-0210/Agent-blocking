import SwiftUI

// MARK: - Root

struct FocusPairingView: View {
  @EnvironmentObject var manager: CoFocusManager
  @EnvironmentObject var deviceStore: PairingDeviceStore

  var body: some View {
    NavigationStack {
      Group {
        switch manager.phase {
        case .idle, .loading:
          PairingIdleHome()
        case .waitingJoin(let session):
          PairingCodeDisplayView(session: session)
        case .waitingTap(let session):
          PairingWaitingView(session: session)
        case .active(let session):
          CoFocusActiveView(session: session, partnerEnded: false)
        case .partnerEnded(let session):
          CoFocusActiveView(session: session, partnerEnded: true)
        }
      }
      .animation(.easeInOut(duration: 0.6), value: phaseId(manager.phase))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  /// Stable token for SwiftUI's `.animation(value:)` so we don't re-fire
  /// on irrelevant payload changes (e.g. polling refreshes that return same status).
  private func phaseId(_ phase: CoFocusManager.Phase) -> String {
    switch phase {
    case .idle:                       return "idle"
    case .loading:                    return "loading"
    case .waitingJoin(let s):         return "waitingJoin:\(s.id)"
    case .waitingTap(let s):          return "waitingTap:\(s.id)"
    case .active(let s):              return "active:\(s.id)"
    case .partnerEnded(let s):        return "partnerEnded:\(s.id)"
    }
  }
}

// MARK: - Idle home (monthly total + entry buttons + history)

private struct PairingIdleHome: View {
  @EnvironmentObject var manager: CoFocusManager
  @EnvironmentObject var deviceStore: PairingDeviceStore

  enum PendingAction { case create, join }
  @State private var nicknameDraft: String = ""
  @State private var showNicknameSheet: Bool = false
  @State private var showJoinSheet: Bool = false
  @State private var pendingAction: PendingAction = .create

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        MonthlyTotalCard(total: manager.monthlyTotal)
          .padding(.top, 8)

        VStack(spacing: 12) {
          Button(action: { primaryAction(.create) }) {
            HStack {
              Image(systemName: "plus.circle.fill")
              Text(String(localized: "開始配對"))
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(ThemeManager.shared.themeColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .buttonStyle(.plain)

          Button(action: { primaryAction(.join) }) {
            HStack {
              Image(systemName: "number")
              Text(String(localized: "輸入代碼"))
                .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          }
          .buttonStyle(.plain)
        }

        HistorySection(records: manager.history)

        if let err = manager.lastError {
          Text(err).font(.footnote).foregroundStyle(.secondary)
            .padding(.top, 4)
        }
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 40)
    }
    .navigationTitle(String(localized: "共同專注"))
    .task {
      await manager.refreshAll()
    }
    .sheet(isPresented: $showNicknameSheet) {
      NicknameSheet(draft: $nicknameDraft) {
        deviceStore.setMyNickname(nicknameDraft)
        showNicknameSheet = false
        nicknameDraft = ""
        proceedWithPendingAction()
      }
      .presentationDetents([.height(320)])
    }
    .sheet(isPresented: $showJoinSheet) {
      JoinCodeSheet { code in
        showJoinSheet = false
        Task {
          await manager.joinPairing(
            code: code,
            nickname: deviceStore.myNickname ?? ""
          )
        }
      }
      .presentationDetents([.height(380)])
    }
  }

  private func primaryAction(_ action: PendingAction) {
    pendingAction = action
    if !deviceStore.hasMyNickname {
      nicknameDraft = ""
      showNicknameSheet = true
    } else {
      proceedWithPendingAction()
    }
  }

  private func proceedWithPendingAction() {
    switch pendingAction {
    case .create:
      Task {
        await manager.createPairing(nickname: deviceStore.myNickname ?? "")
      }
    case .join:
      showJoinSheet = true
    }
  }
}

private struct MonthlyTotalCard: View {
  let total: CoFocusMonthlyTotal

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(String(localized: "本月共同專注"))
        .font(.subheadline)
        .foregroundStyle(.secondary)
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(formatHoursMinutes(seconds: total.totalSeconds))
          .font(.system(size: 44, weight: .semibold, design: .rounded))
          .monospacedDigit()
        Text(String.localizedStringWithFormat(
          String(localized: "%lld 次"), Int64(total.sessionCount)))
          .font(.body)
          .foregroundStyle(.secondary)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

private struct HistorySection: View {
  let records: [PairFocusRecord]

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(localized: "歷史記錄"))
        .font(.headline)
        .padding(.top, 4)

      if records.isEmpty {
        Text(String(localized: "還沒有共同專注的記錄。把代碼分享給朋友，一起做就對了。"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .padding(.vertical, 24)
          .frame(maxWidth: .infinity, alignment: .center)
      } else {
        VStack(spacing: 8) {
          ForEach(records) { record in
            HistoryRow(record: record)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct HistoryRow: View {
  @EnvironmentObject var deviceStore: PairingDeviceStore
  let record: PairFocusRecord

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 4) {
        Text(deviceStore.displayName(
          forPartner: record.partnerUserId,
          defaultNickname: record.partnerNickname
        ))
        .font(.body.weight(.medium))
        Text(record.createdAt, format: .dateTime.year().month().day())
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(formatDuration(seconds: record.durationSeconds))
        .monospacedDigit()
        .foregroundStyle(.primary)
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
  }
}

// MARK: - Nickname sheet (first-action gate)

private struct NicknameSheet: View {
  @Binding var draft: String
  let onConfirm: () -> Void

  var body: some View {
    VStack(spacing: 16) {
      Text(String(localized: "設定你的暱稱"))
        .font(.title2.weight(.semibold))
        .padding(.top, 24)
      Text(String(localized: "你的夥伴會在配對畫面看到這個名字。"))
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)

      TextField(String(localized: "暱稱"), text: $draft)
        .textFieldStyle(.roundedBorder)
        .padding(.horizontal, 24)

      Button(action: onConfirm) {
        Text(String(localized: "完成"))
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(ThemeManager.shared.themeColor)
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
      .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
      .padding(.horizontal, 24)

      Spacer()
    }
  }
}

// MARK: - Join code sheet (6-digit OTP-style input)

private struct JoinCodeSheet: View {
  let onSubmit: (String) -> Void

  @State private var code: String = ""
  @FocusState private var focused: Bool

  var body: some View {
    VStack(spacing: 16) {
      Text(String(localized: "輸入夥伴的代碼"))
        .font(.title2.weight(.semibold))
        .padding(.top, 24)

      TextField("", text: $code)
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .font(.system(size: 36, weight: .semibold, design: .monospaced))
        .focused($focused)
        .onChange(of: code) { _, newValue in
          let filtered = String(newValue.filter(\.isNumber).prefix(6))
          if filtered != code { code = filtered }
        }
        .padding(.horizontal, 24)

      Button(action: { onSubmit(code) }) {
        Text(String(localized: "加入"))
          .fontWeight(.semibold)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(ThemeManager.shared.themeColor)
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(.plain)
      .disabled(code.count != 6)
      .opacity(code.count == 6 ? 1 : 0.5)
      .padding(.horizontal, 24)

      Spacer()
    }
    .onAppear { focused = true }
  }
}

// MARK: - Code display (initiator, status = waiting_join)

private struct PairingCodeDisplayView: View {
  @EnvironmentObject var manager: CoFocusManager
  let session: PairingSession

  @State private var now: Date = .now
  let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var remainingSeconds: Int {
    max(0, Int(session.expiresAt.timeIntervalSince(now)))
  }

  var body: some View {
    VStack(spacing: 28) {
      Spacer()
      Text(String(localized: "告訴夥伴這個代碼"))
        .font(.title3)
        .foregroundStyle(.secondary)

      Text(session.code ?? "------")
        .font(.system(size: 72, weight: .semibold, design: .monospaced))
        .tracking(6)
        .foregroundStyle(.primary)

      Text(String.localizedStringWithFormat(
        String(localized: "剩餘 %@"),
        formatDuration(seconds: remainingSeconds)
      ))
      .font(.subheadline)
      .foregroundStyle(.secondary)

      Spacer()

      Button(role: .destructive, action: {
        Task { await manager.cancelCurrentPairing() }
      }) {
        Text(String(localized: "取消代碼"))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(.ultraThinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
    }
    .onReceive(timer) { now = $0 }
    .navigationTitle(String(localized: "等待夥伴加入"))
  }
}

// MARK: - Waiting tap (status = waiting_tap)

private struct PairingWaitingView: View {
  @EnvironmentObject var manager: CoFocusManager
  let session: PairingSession

  private var partnerNickname: String {
    guard let myId = manager.myUserId else { return "" }
    return session.partnerNickname(forCaller: myId) ?? ""
  }
  private var iHaveTapped: Bool {
    guard let myId = manager.myUserId else { return false }
    return session.hasTapped(myId)
  }

  var body: some View {
    VStack(spacing: 24) {
      Spacer()
      Image(systemName: "person.2.fill")
        .font(.system(size: 60))
        .foregroundStyle(ThemeManager.shared.themeColor)

      Text(String.localizedStringWithFormat(
        String(localized: "%@ 已就緒"),
        partnerNickname
      ))
      .font(.title2.weight(.semibold))

      if iHaveTapped {
        Text(String(localized: "等待對方刷卡…"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      } else {
        Text(String(localized: "刷卡開始共同專注"))
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if !iHaveTapped {
        Text(String(localized: "兩個人各自刷卡，才算正式開始"))
          .font(.footnote)
          .foregroundStyle(.tertiary)
          .padding(.bottom, 8)
      }

      Button(role: .destructive, action: {
        Task { await manager.cancelCurrentPairing() }
      }) {
        Text(String(localized: "取消配對"))
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(.ultraThinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 20)
      .padding(.bottom, 32)
    }
    .navigationTitle(String(localized: "共同專注"))
  }
}

// MARK: - Active overlay (status = active or partnerEnded)
//
// Visual layers (per spec section "個人 vs 共同 UI 區分"):
//   active phase           — top: "與 X 共同專注中"   center: COMMON time   bottom: "個人 N"
//   partnerEnded phase     — top: "X 已結束共同專注"   center: PERSONAL time bottom: "共同時長 N"
//
// Phase 1 → Phase 2 transition uses a scale+opacity insertion on the COMMON time
// to create the儀式感 "0:00 從中央放大進場" effect.

private struct CoFocusActiveView: View {
  @EnvironmentObject var manager: CoFocusManager
  @EnvironmentObject var strategyManager: StrategyManager
  let session: PairingSession
  let partnerEnded: Bool

  private var partnerNickname: String {
    guard let myId = manager.myUserId else { return "" }
    return session.partnerNickname(forCaller: myId) ?? ""
  }

  /// Seconds elapsed since both parties tapped (the共同 timer).
  /// Frozen on partnerEnded at session_end_at.
  private func coFocusSeconds(at now: Date) -> Int {
    guard let start = session.sessionStartAt else { return 0 }
    let end = partnerEnded ? (session.sessionEndAt ?? now) : now
    return max(0, Int(end.timeIntervalSince(start)))
  }

  /// Seconds elapsed since this user tapped NFC.
  /// Sourced from StrategyManager so it stays consistent with the main UI.
  private var personalSeconds: Int {
    Int(strategyManager.elapsedTime)
  }

  var body: some View {
    // TimelineView owns the periodic re-render for the timer display, isolated
    // from external @Published churn. Without this, body re-renders triggered
    // by polling / strategyManager updates would re-create a Timer.publish
    // subscription whose first fire would be 1s in the future, causing the
    // visible counter to occasionally skip a tick (47 → 49).
    TimelineView(.periodic(from: session.sessionStartAt ?? .now, by: 1)) { context in
      bodyContent(now: context.date)
    }
  }

  @ViewBuilder
  private func bodyContent(now: Date) -> some View {
    let coSec = coFocusSeconds(at: now)
    VStack(spacing: 18) {
      Spacer()

      // ─── Caption (top) ───────────────────────────────
      if partnerEnded {
        VStack(spacing: 8) {
          Image(systemName: "person.fill.checkmark")
            .font(.title)
            .foregroundStyle(ThemeManager.shared.themeColor)
          Text(String.localizedStringWithFormat(
            String(localized: "%@ 已結束共同專注"),
            partnerNickname
          ))
          .font(.title3.weight(.semibold))
          .foregroundStyle(.primary)
        }
        .transition(.opacity)
        .onAppear {
          // Haptic so the partner-ended transition is impossible to miss
          // even if the user's eyes are off the screen.
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
      } else {
        Text(String.localizedStringWithFormat(
          String(localized: "與 %@ 共同專注中"),
          partnerNickname
        ))
        .font(.headline)
        .foregroundStyle(.secondary)
        .transition(.opacity)
      }

      // ─── Primary time (center) ───────────────────────
      // Active phase   → coFocusSeconds is now-anchored, so it ticks.
      // partnerEnded   → coFocusSeconds is session_end_at-anchored, so it freezes.
      // Same expression, different anchor → consistent main-number identity, the
      // freeze is what visually pairs with "X 已結束共同專注".
      Text(formatDuration(seconds: coSec))
        .font(.system(size: 88, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(.primary)
        .transition(.asymmetric(
          insertion: .scale(scale: 0.3).combined(with: .opacity),
          removal: .opacity
        ))

      // ─── Subordinate time (bottom) ────────────────────
      // Personal time keeps ticking in BOTH modes (the user's NFC is still
      // active until they unlock locally). In partnerEnded mode this is the
      // only visible cue that the user is still in their solo session.
      Text(String.localizedStringWithFormat(
        String(localized: "個人 %@"),
        formatDuration(seconds: personalSeconds)
      ))
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .monospacedDigit()

      Spacer()

      Text(String(localized: "刷卡解鎖即可結束。"))
        .font(.footnote)
        .foregroundStyle(.tertiary)

      // Manual escape hatch — covers any case where Realtime / polling
      // lags behind server state and the active overlay would otherwise stay stuck.
      // Active phase: ends the co-session on server (records get written).
      // partnerEnded phase: just dismisses the sticky message.
      Button(action: {
        Task { await manager.endCoFocusFromUI() }
      }) {
        Text(partnerEnded
          ? String(localized: "返回主頁")
          : String(localized: "結束共同專注"))
          .font(.subheadline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
          .background(.ultraThinMaterial)
          .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 40)
      .padding(.bottom, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .animation(.easeInOut(duration: 0.6), value: partnerEnded)
    .navigationTitle(partnerEnded
      ? String(localized: "共同專注")
      : String(localized: "共同專注中"))
  }
}

// MARK: - Format helpers

/// "MM:SS" under an hour, "H:MM:SS" otherwise.
fileprivate func formatDuration(seconds: Int) -> String {
  let s = max(0, seconds)
  let h = s / 3600
  let m = (s % 3600) / 60
  let sec = s % 60
  if h > 0 {
    return String(format: "%d:%02d:%02d", h, m, sec)
  } else {
    return String(format: "%02d:%02d", m, sec)
  }
}

/// "Xh Ym" / "Ym" — used for the monthly total card.
fileprivate func formatHoursMinutes(seconds: Int) -> String {
  let h = seconds / 3600
  let m = (seconds % 3600) / 60
  if h > 0 {
    return String(format: "%dh %dm", h, m)
  } else {
    return String(format: "%dm", m)
  }
}

#Preview {
  FocusPairingView()
    .environmentObject(CoFocusManager.shared)
    .environmentObject(PairingDeviceStore.shared)
    .environmentObject(StrategyManager.shared)
    .environmentObject(ThemeManager.shared)
}
