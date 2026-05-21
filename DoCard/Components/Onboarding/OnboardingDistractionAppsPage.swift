import FamilyControls
import SwiftUI

/// Onboarding step (right after Screen Time authorization): the user picks the
/// apps that most distract them. Those apps are used two ways:
///   1. anonymously tracked over time (usage-time buckets) to show their progress
///   2. pre-loaded into an auto-created Classic-mode profile so they can start a
///      focus session immediately.
///
/// This page also doubles as the disclosure that DO collects anonymous usage data.
struct OnboardingDistractionAppsPage: View {
  @EnvironmentObject var themeManager: ThemeManager

  /// Called with the chosen selection when the user taps continue.
  var onContinue: (FamilyActivitySelection) -> Void

  @State private var selection = FamilyActivitySelection()
  @State private var showPicker = false
  @State private var showContent = false

  private var selectedCount: Int {
    selection.applicationTokens.count
      + selection.categoryTokens.count
      + selection.webDomainTokens.count
  }

  private var hasSelection: Bool { selectedCount > 0 }

  var body: some View {
    VStack(spacing: 0) {
      Text(String(localized: "哪些 App 最常打斷你？"))
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .padding(.top, 40)

      Text(String(localized: "選出最干擾你的 App（建議 3 個）。\nDO 會以匿名的方式記錄它們的使用時間，幫你看見自己的進步。"))
        .font(.system(size: 16, weight: .regular))
        .foregroundColor(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .padding(.horizontal, 36)
        .padding(.top, 12)

      Spacer()

      Button(action: { showPicker = true }) {
        VStack(spacing: 12) {
          Image(systemName: hasSelection ? "checkmark.circle.fill" : "hand.raised.app")
            .font(.system(size: 44, weight: .medium))
            .foregroundStyle(themeManager.themeColor)

          Text(hasSelection
            ? String(localized: "已選擇 \(selectedCount) 個 App")
            : String(localized: "選擇 App"))
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)

          Text(String(localized: "點此開啟選擇器"))
            .font(.system(size: 13))
            .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(.ultraThinMaterial.opacity(0.7))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 24, style: .continuous)
            .stroke(themeManager.themeColor.opacity(0.3), lineWidth: 1)
        )
      }
      .padding(.horizontal, 36)

      Spacer()

      Button(action: { onContinue(selection) }) {
        Text(String(localized: "繼續"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 58)
          .background(
            Capsule().fill(hasSelection ? Color.white : Color.white.opacity(0.3))
          )
      }
      .disabled(!hasSelection)
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
    }
    .opacity(showContent ? 1.0 : 0)
    .onAppear {
      withAnimation(.spring(response: 0.7, dampingFraction: 0.8)) {
        showContent = true
      }
    }
    .familyActivityPicker(isPresented: $showPicker, selection: $selection)
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingDistractionAppsPage(onContinue: { _ in })
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
