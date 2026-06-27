import SwiftUI

/// Settings → "Mac 連動". Shows a 6-character pairing code that the user enters
/// in the Chrome Extension popup. Polls Supabase to detect when the extension
/// has claimed the code, then flips into a "已配對" state.
struct MacPairingView: View {
  /// Set to `true` from the debug section to force-show the preflight
  /// checklist regardless of current pairing state.
  var forcePreflightForDebug: Bool = false

  @EnvironmentObject var themeManager: ThemeManager
  @StateObject private var pairingService = MacPairingService()
  @State private var alreadyPaired: Bool = false
  @State private var checkingExisting: Bool = true
  @State private var showPreflightCheck: Bool = false
  @State private var now: Date = Date()
  @State private var showRegenerateConfirm: Bool = false
  @State private var showRevokeAllConfirm: Bool = false

  // Drives the live countdown.
  private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 24) {
        if checkingExisting {
          ProgressView()
            .progressViewStyle(.circular)
            .tint(themeManager.themeColor)
        } else {
          content
        }
      }
      .padding(.horizontal, 24)
      .padding(.top, 32)
    }
    .navigationTitle(DeviceSyncStrings.featureTitle)
    .navigationBarTitleDisplayMode(.inline)
    .task {
      if forcePreflightForDebug {
        checkingExisting = false
        showPreflightCheck = true
        return
      }
      alreadyPaired = await MacPairingService.isAlreadyPairedToMac()
      checkingExisting = false
      if !alreadyPaired {
        showPreflightCheck = true   // show checklist before generating code
      }
    }
    .onReceive(timer) { now = $0 }
    .confirmationDialog(
      String(localized: "重新產生配對碼？"),
      isPresented: $showRegenerateConfirm,
      titleVisibility: .visible
    ) {
      Button(String(localized: "重新產生")) {
        Task { await pairingService.generateNewPairingCode() }
      }
      Button(String(localized: "取消"), role: .cancel) {}
    } message: {
      Text(String(localized: "原配對碼將立即失效。"))
    }
    .confirmationDialog(
      String(localized: "解除所有 Chrome / Safari 與 iPad 連動？"),
      isPresented: $showRevokeAllConfirm,
      titleVisibility: .visible
    ) {
      Button(String(localized: "解除所有"), role: .destructive) {
        revokeAllAndRestart()
      }
      Button(String(localized: "取消"), role: .cancel) {}
    } message: {
      Text(String(
        localized:
          "已配對的 Chrome / Safari 與 iPad 將不再收到刷卡訊號。要徹底清除，請另外在每個瀏覽器 popup（或 iPad App）上按「解除配對」。"
      ))
    }
  }

  private func revokeAllAndRestart() {
    // Order matters: prepareForRevoke reads the CURRENT token to queue an
    // 'ended' for it. Must run before revokeAllMacPairings deletes the
    // browser_clients rows + rotates the token (both of which depend on
    // the current iphone_token still being valid for RLS).
    Task { @MainActor in
      MacSessionSyncService.shared.prepareForRevoke()
      await MacPairingService.revokeAllMacPairings()
      MacSessionSyncService.shared.resetAfterRevoke()
      alreadyPaired = false
      await pairingService.generateNewPairingCode()
    }
  }

  // MARK: - Content states

  @ViewBuilder
  private var content: some View {
    if showPreflightCheck {
      preflightCheckView
    } else if alreadyPaired, case .idle = pairingService.state {
      pairedSuccessView
    } else {
      switch pairingService.state {
      case .idle, .generating:
        ProgressView()
          .progressViewStyle(.circular)
          .tint(themeManager.themeColor)

      case .awaitingClaim(let code, let expiresAt):
        awaitingClaimView(code: code, expiresAt: expiresAt)

      case .claimedAdditionalsOpen(let code, let expiresAt):
        claimedAdditionalsOpenView(code: code, expiresAt: expiresAt)

      case .paired:
        pairedSuccessView

      case .failed(let message):
        failedView(message: message)
      }
    }
  }

  // MARK: - Preflight check (shown before code is generated)

  private var preflightCheckView: some View {
    VStack(spacing: 24) {
      Spacer()

      Text(String(localized: "連接前先確認"))
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(.white)

      VStack(alignment: .leading, spacing: 20) {
        // Item 1 — Chrome Extension installed
        VStack(alignment: .leading, spacing: 6) {
          HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle")
              .foregroundColor(themeManager.themeColor)
              .font(.system(size: 20))
            Text(String(localized: "已在 Mac 安裝 Chrome / Safari 擴充功能，或在 iPad 安裝 DO Card App"))
              .font(.system(size: 15))
              .foregroundColor(.white.opacity(0.9))
          }
          Text(String(localized: "還沒安裝？Chrome 在「Chrome 線上應用程式商店」、Safari 在 Mac App Store、iPad 在 App Store 搜尋「Do Card」即可找到。"))
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.45))
            .padding(.leading, 32)
        }

        // Item 2 — both devices nearby
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "checkmark.circle")
            .foregroundColor(themeManager.themeColor)
            .font(.system(size: 20))
          Text(String(localized: "iPhone 和要連動的 Mac / iPad 都在手邊"))
            .font(.system(size: 15))
            .foregroundColor(.white.opacity(0.9))
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.white.opacity(0.04))
      )

      Spacer()

      Button(action: {
        showPreflightCheck = false
        Task { await pairingService.generateNewPairingCode() }
      }) {
        Text(String(localized: "準備好了，產生代碼"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(Capsule().fill(themeManager.themeColor))
      }
      .padding(.bottom, 8)
    }
  }

  private func awaitingClaimView(code: String, expiresAt: Date) -> some View {
    VStack(spacing: 20) {
      Text(String(localized: "在 Chrome / Safari 或 iPad 中輸入這組代碼"))
        .font(.system(size: 14))
        .foregroundColor(.white.opacity(0.6))

      Text(code)
        .font(.system(size: 44, weight: .bold, design: .monospaced))
        .foregroundColor(themeManager.themeColor)
        .tracking(6)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.05))
        )

      Text(countdownText(until: expiresAt))
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.white.opacity(0.5))

      Spacer()

      Text(String(localized: "還沒安裝？Chrome 在「Chrome 線上應用程式商店」、Safari 在 Mac App Store、iPad 在 App Store 搜尋「Do Card」即可找到。"))
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.45))
        .multilineTextAlignment(.center)

      VStack(alignment: .leading, spacing: 12) {
        InstructionRow(number: "1", text: String(localized: "打開 Chrome / Safari，或 iPad 上的 DO Card"))
        InstructionRow(number: "2", text: String(localized: "點擊瀏覽器擴充功能圖示，或 iPad App 的連動頁面"))
        InstructionRow(number: "3", text: String(localized: "輸入上方代碼並按「配對」"))
      }
      .padding(20)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.white.opacity(0.04))
      )

      Text(String(localized: "10 分鐘內可重複使用，可配對多個瀏覽器或 iPad"))
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.4))
        .multilineTextAlignment(.center)
        .padding(.top, 4)

      Spacer()

      Button(action: { showRegenerateConfirm = true }) {
        Text(String(localized: "重新產生配對碼"))
          .font(.system(size: 14, weight: .medium))
          .foregroundColor(.white.opacity(0.5))
          .underline()
      }
      .padding(.bottom, 8)
    }
  }

  private func claimedAdditionalsOpenView(code: String, expiresAt: Date) -> some View {
    VStack(spacing: 20) {
      // Success indicator pulled to the top — clear acknowledgement that the
      // first browser pairing landed.
      HStack(spacing: 8) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
          .font(.system(size: 16))
        Text(String(localized: "配對成功"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.green)
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(
        Capsule().fill(Color.green.opacity(0.12))
      )

      Text(String(localized: "可在其他瀏覽器或 iPad 繼續輸入這組代碼"))
        .font(.system(size: 13))
        .foregroundColor(.white.opacity(0.6))
        .multilineTextAlignment(.center)

      Text(code)
        .font(.system(size: 44, weight: .bold, design: .monospaced))
        .foregroundColor(themeManager.themeColor)
        .tracking(6)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
          RoundedRectangle(cornerRadius: 16)
            .fill(Color.white.opacity(0.05))
        )

      Text(countdownText(until: expiresAt))
        .font(.system(size: 13, weight: .medium))
        .foregroundColor(.white.opacity(0.5))

      Spacer()

      Button(action: { pairingService.confirmPaired() }) {
        Text(String(localized: "完成"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(Capsule().fill(themeManager.themeColor))
      }
      .padding(.bottom, 8)
    }
  }

  private var pairedSuccessView: some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "checkmark.seal.fill")
        .font(.system(size: 64))
        .foregroundColor(.green)
      Text(String(localized: "已配對"))
        .font(.system(size: 22, weight: .bold))
        .foregroundColor(.white)
      Text(String(localized: "刷卡開始 session 時，Chrome / Safari 與 iPad 上的分心內容會自動封鎖。"))
        .font(.system(size: 14))
        .foregroundColor(.white.opacity(0.6))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)

      Text(String(
        localized: "可同時連動多個 Chrome / Safari 與 iPad。配對狀態由各裝置端記憶，iPhone 無法逐一查看。"
      ))
      .font(.system(size: 12))
      .foregroundColor(.white.opacity(0.4))
      .multilineTextAlignment(.center)
      .padding(.horizontal, 24)
      .padding(.top, 4)

      Spacer()

      VStack(spacing: 14) {
        Button(action: {
          alreadyPaired = false
          Task { await pairingService.generateNewPairingCode() }
        }) {
          Text(String(localized: "新增另一個 Chrome / Safari 或 iPad"))
            .font(.system(size: 15, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
              Capsule().fill(themeManager.themeColor)
            )
        }

        Button(action: { showRevokeAllConfirm = true }) {
          Text(String(localized: "解除所有 Chrome / Safari 與 iPad 連動"))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
        }
      }
      .padding(.bottom, 8)
    }
  }

  private func failedView(message: String) -> some View {
    VStack(spacing: 16) {
      Spacer()
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 56))
        .foregroundColor(.orange)
      Text(message)
        .font(.system(size: 15))
        .foregroundColor(.white.opacity(0.7))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
      Spacer()
      Button(action: { Task { await pairingService.generateNewPairingCode() } }) {
        Text(String(localized: "重新產生配對碼"))
          .font(.system(size: 16, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 50)
          .background(Capsule().fill(themeManager.themeColor))
      }
    }
  }

  private func countdownText(until expiresAt: Date) -> String {
    let remaining = max(0, Int(expiresAt.timeIntervalSince(now)))
    let minutes = remaining / 60
    let seconds = remaining % 60
    return String(
      format: String(localized: "代碼將在 %d:%02d 後過期"),
      minutes, seconds)
  }
}

private struct InstructionRow: View {
  let number: String
  let text: String

  var body: some View {
    HStack(spacing: 12) {
      Text(number)
        .font(.system(size: 13, weight: .bold))
        .foregroundColor(.white)
        .frame(width: 22, height: 22)
        .background(Circle().fill(Color.white.opacity(0.12)))
      Text(text)
        .font(.system(size: 14))
        .foregroundColor(.white.opacity(0.85))
      Spacer()
    }
  }
}

#Preview {
  NavigationStack {
    MacPairingView()
      .environmentObject(ThemeManager.shared)
  }
}
