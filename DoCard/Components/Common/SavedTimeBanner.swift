import SwiftData
import SwiftUI

struct SavedTimeBanner: View {
  let totalSavedTime: TimeInterval
  let onDismiss: () -> Void

  @State private var isVisible = false

  var body: some View {
    VStack {
      if isVisible {
        HStack(spacing: 0) {
          VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "你已經累積了"))
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.white.opacity(0.9))

            Text(formattedDuration(totalSavedTime))
              .font(.system(size: 28, weight: .bold, design: .rounded))
              .foregroundColor(.white)

            Text(String(localized: "的專注時間"))
              .font(.system(size: 13, weight: .medium))
              .foregroundColor(.white.opacity(0.9))
          }

          Spacer()

          Button {
            withAnimation(.easeOut(duration: 0.3)) {
              isVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              onDismiss()
            }
          } label: {
            Image(systemName: "xmark")
              .font(.system(size: 14, weight: .bold))
              .foregroundColor(.white.opacity(0.7))
              .padding(8)
          }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
          RoundedRectangle(cornerRadius: 14)
            .fill(ThemeManager.shared.themeColor)
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .padding(.horizontal, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
      }

      Spacer()
    }
    .onAppear {
      withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
        isVisible = true
      }
    }
  }

  private func formattedDuration(_ interval: TimeInterval) -> String {
    let totalSeconds = Int(interval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    return "\(hours)h \(minutes)m"
  }
}
