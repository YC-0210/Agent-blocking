import SwiftUI

// MARK: - Root

struct WhatsNewView: View {
  let onGoToGallery: () -> Void
  let onDismiss: () -> Void

  var body: some View {
    VStack(spacing: 0) {

      // ── Header ───────────────────────────────────────────────
      VStack(spacing: 8) {
        Text(String(localized: "最新版本"))
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

      // ── Card ──────────────────────────────────────────────────
      VStack(spacing: 14) {
        WhatsNewCard(
          icon: "photo.on.rectangle.angled",
          title: String(localized: "你為了什麼在堅持呢？"),
          description: String(localized: "主畫面現在能放進對你有意義的照片——家人、目標、想守護的人。每次打開 App，先想起你為何開始，就更不容易半途放棄。"),
          buttonLabel: String(localized: "去放第一張照片"),
          onButton: onGoToGallery
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
    onGoToGallery: {},
    onDismiss: {}
  )
  .preferredColorScheme(.dark)
}
