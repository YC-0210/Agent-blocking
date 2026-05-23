import FamilyControls
import SwiftUI

struct OnboardingPermissionPage: View {
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var requestAuthorizer: RequestAuthorizer

  var onContinue: (() -> Void)? = nil

  @State private var showContent = false
  @State private var showCard = false
  @State private var showButton = false
  @State private var pulseIcon = false

  var body: some View {
    VStack(spacing: 0) {
      // Title
      Text(String(localized: "安全連結螢幕使用時間"))
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      // Subtitle
      Text(String(localized: "DO 需要你的授權才能陪你展開行動\n你的資料由 Apple 安全保護"))
        .font(.system(size: 16, weight: .regular))
        .foregroundColor(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .padding(.horizontal, 40)
        .padding(.top, 12)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      Spacer()

      // Permission explanation card
      permissionCard
        .opacity(showCard ? 1.0 : 0)
        .scaleEffect(showCard ? 1.0 : 0.92)

      Spacer()

      // Authorize button
      Button(action: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        requestAuthorizer.requestAuthorization()
      }) {
        Text(String(localized: "授權螢幕使用時間"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 58)
          .background(
            Capsule()
              .fill(Color.white)
          )
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .opacity(showButton ? 1.0 : 0)
      .offset(y: showButton ? 0 : 20)
    }
    .onAppear {
      withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
        showContent = true
      }
      withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.5)) {
        showCard = true
      }
      withAnimation(.easeOut(duration: 0.7).delay(0.9)) {
        showButton = true
      }
      // Gentle pulse on the icon
      withAnimation(
        .easeInOut(duration: 1.6)
        .repeatForever(autoreverses: true)
        .delay(1.0)
      ) {
        pulseIcon = true
      }
    }
    .onChange(of: requestAuthorizer.isAuthorized) { _, authorized in
      if authorized {
        onContinue?()
      }
    }
    .onReceive(
      NotificationCenter.default.publisher(
        for: UIApplication.didBecomeActiveNotification)
    ) { _ in
      // Check again when user returns from system permission dialog
      if requestAuthorizer.getAuthorizationStatus() == .approved {
        requestAuthorizer.isAuthorized = true
        onContinue?()
      }
    }
  }

  // MARK: - Permission Explanation Card

  private var permissionCard: some View {
    VStack(spacing: 20) {
      // Hourglass icon
      Image(systemName: "hourglass")
        .font(.system(size: 44, weight: .medium))
        .foregroundStyle(
          LinearGradient(
            colors: [themeManager.themeColor, themeManager.themeColor.opacity(0.6)],
            startPoint: .top,
            endPoint: .bottom
          )
        )
        .scaleEffect(pulseIcon ? 1.06 : 1.0)
        .padding(.top, 4)

      // Explanation points
      VStack(alignment: .leading, spacing: 14) {
        permissionRow(
          icon: "app.badge.checkmark",
          text: String(localized: "阻擋讓你分心的 App")
        )
        permissionRow(
          icon: "lock.shield",
          text: String(localized: "你選擇的 App 清單只留在你的裝置上")
        )
        permissionRow(
          icon: "hand.raised",
          text: String(localized: "設定完全由你做主")
        )
      }
    }
    .padding(24)
    .background(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .fill(.ultraThinMaterial.opacity(0.7))
    )
    .overlay(
      RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(themeManager.themeColor.opacity(0.3), lineWidth: 1)
    )
    .padding(.horizontal, 36)
  }

  // MARK: - Permission Row

  private func permissionRow(icon: String, text: String) -> some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(themeManager.themeColor)
        .frame(width: 28, alignment: .center)

      Text(text)
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(.white.opacity(0.8))
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingPermissionPage(onContinue: {})
  }
  .environmentObject(ThemeManager.shared)
  .environmentObject(RequestAuthorizer())
  .preferredColorScheme(.dark)
}
