import SwiftUI

// MARK: - Root

struct WhatsNewView: View {
  let onGoToSettings: () -> Void
  let onGoToCoFocus: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {

      // ── Header ───────────────────────────────────────────────
      VStack(spacing: 8) {
        Text("2.0.6")
          .font(.caption.weight(.semibold))
          .foregroundStyle(ThemeManager.shared.themeColor)
          .padding(.horizontal, 10)
          .padding(.vertical, 4)
          .background(ThemeManager.shared.themeColor.opacity(0.15))
          .clipShape(Capsule())

        Text(String(localized: "新功能來了"))
          .font(.title2.weight(.bold))
      }
      .frame(maxWidth: .infinity)
      .padding(.top, 36)
      .padding(.bottom, 28)

      // ── Cards ─────────────────────────────────────────────────
      VStack(spacing: 14) {
        WhatsNewCard(
          icon: "globe",
          title: String(localized: "同步封鎖 Chrome"),
          description: String(localized: "專注開始時，Chrome 瀏覽器網站也一起同步封鎖，也會隨著手機一同解除鎖定"),
          buttonLabel: String(localized: "去設定連接"),
          onButton: onGoToSettings
        )

        WhatsNewCard(
          icon: "person.2.fill",
          title: String(localized: "找你的朋友一起專注吧"),
          description: String(localized: "把代碼傳給朋友，兩個人各自刷卡，就能一起開始專注。"),
          buttonLabel: String(localized: "去看看"),
          onButton: onGoToCoFocus
        )
      }
      .padding(.horizontal, 20)

      Spacer()

      // ── Dismiss ───────────────────────────────────────────────
      Button(action: onDismiss) {
        Text(String(localized: "先這樣"))
          .font(.subheadline)
          .foregroundStyle(.tertiary)
          .padding(.vertical, 20)
      }
      .buttonStyle(.plain)
    }
  }
}

// MARK: - Card

private struct WhatsNewCard: View {
  let icon: String
  let title: String
  let description: String
  let buttonLabel: String
  let onButton: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.title3)
          .foregroundStyle(ThemeManager.shared.themeColor)
          .frame(width: 28, alignment: .center)
        Text(title)
          .font(.headline)
      }

      Text(description)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Button(action: onButton) {
        Text(buttonLabel + " →")
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(ThemeManager.shared.themeColor)
      }
      .buttonStyle(.plain)
    }
    .padding(18)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.ultraThinMaterial)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
  }
}

// MARK: - Preview

#Preview {
  WhatsNewView(
    onGoToSettings: {},
    onGoToCoFocus: {},
    onDismiss: {}
  )
  .preferredColorScheme(.dark)
}
