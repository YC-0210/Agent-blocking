import SwiftUI

// MARK: - Root

struct CoFocusOnboardingView: View {
  let onDismiss: () -> Void

  @State private var currentPage = 0

  private struct StepData {
    let icon: String
    let subtitle: LocalizedStringKey
    let description: LocalizedStringKey
    let isKey: Bool
  }

  private let steps: [StepData] = [
    StepData(
      icon: "person.badge.plus",
      subtitle: "一個人先建立，並拿到代碼",
      description: "設定暱稱後，會拿到一組 6 位數字。",
      isKey: false
    ),
    StepData(
      icon: "paperplane.fill",
      subtitle: "把代碼傳給對方",
      description: "對方在 App 輸入你的代碼，加入配對。",
      isKey: false
    ),
    StepData(
      icon: "creditcard.fill",
      subtitle: "兩個人都刷一下 DO Card",
      description: "輸完代碼還沒開始，你們各自刷卡，才算正式啟動噢。",
      isKey: true
    ),
  ]

  var body: some View {
    VStack(spacing: 0) {

      // ── Header ──────────────────────────────────────────
      Text(String(localized: "共同專注怎麼用？"))
        .font(.title2.weight(.bold))
        .padding(.top, 36)
        .padding(.bottom, 4)

      // ── Steps (swipeable) ────────────────────────────────
      TabView(selection: $currentPage) {
        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
          StepPage(
            stepNumber: index + 1,
            icon: step.icon,
            subtitle: step.subtitle,
            description: step.description,
            isKey: step.isKey
          )
          .tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .always))
      .indexViewStyle(.page(backgroundDisplayMode: .always))

      // ── Confirm button (appears on last step) ─────────────
      Button(action: onDismiss) {
        Text(String(localized: "了解，來試試"))
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(ThemeManager.shared.themeColor)
          .foregroundStyle(.white)
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.horizontal, 24)
      .padding(.bottom, 32)
      .opacity(currentPage == steps.count - 1 ? 1 : 0)
      .animation(.easeInOut(duration: 0.2), value: currentPage)
    }
  }
}

// MARK: - Step page

private struct StepPage: View {
  let stepNumber: Int
  let icon: String
  let subtitle: LocalizedStringKey
  let description: LocalizedStringKey
  let isKey: Bool

  var body: some View {
    VStack(spacing: 20) {
      Spacer()

      // Step badge
      Text("Step \(stepNumber)")
        .font(.caption.weight(.semibold))
        .foregroundStyle(ThemeManager.shared.themeColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(ThemeManager.shared.themeColor.opacity(0.15))
        .clipShape(Capsule())

      // Icon — key step uses accent colour for extra emphasis
      Image(systemName: icon)
        .font(.system(size: 60))
        .foregroundStyle(isKey ? ThemeManager.shared.themeColor : .primary)

      // Text
      VStack(spacing: 8) {
        Text(subtitle)
          .font(.title3.weight(.semibold))
          .multilineTextAlignment(.center)

        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal, 8)
      }

      Spacer()
      Spacer()  // extra bottom space so dots don't overlap text
    }
    .padding(.horizontal, 32)
  }
}

// MARK: - Preview

#Preview {
  CoFocusOnboardingView(onDismiss: {})
    .preferredColorScheme(.dark)
}
