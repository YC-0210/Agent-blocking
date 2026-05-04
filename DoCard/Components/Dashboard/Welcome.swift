import SwiftUI

struct Welcome: View {
  @EnvironmentObject var themeManager: ThemeManager
  let onTap: () -> Void

  var body: some View {
    Button(action: onTap) {
      VStack(alignment: .leading, spacing: 12) {
        // Top row with category and icon
        HStack {
          Text(String(localized: "輕觸卡片，守護你的專注時間"))
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundColor(.primary)

          Spacer()

          Image(systemName: "hourglass")
            .font(.body)
            .foregroundColor(.white)
            .padding(8)
            .background(
              Circle()
                .fill(themeManager.themeColor.opacity(0.8))
            )
        }

        Spacer()
          .frame(height: 10)

        // Title and subtitle
        Text(String(localized: "歡迎來到 DO"))
          .font(.title)
          .fontWeight(.bold)
          .foregroundColor(.primary)

        Text(String(localized: "點這裡建立你的第一個專注模式，用 DO Card 開始展開行動"))
        .font(.subheadline)
        .foregroundColor(.secondary)
        .lineLimit(3)
      }
      .padding(20)
      .frame(maxWidth: .infinity, minHeight: 150)
      .background(
        RoundedRectangle(cornerRadius: 24)
          .fill(Color(UIColor.systemBackground))
          .overlay(
            GeometryReader { geometry in
              ZStack {
                // Theme color circle blob
                Circle()
                  .fill(themeManager.themeColor.opacity(0.5))
                  .frame(width: geometry.size.width * 0.5)
                  .position(
                    x: geometry.size.width * 0.9,
                    y: geometry.size.height / 2
                  )
                  .blur(radius: 15)
              }
            }
          )
          .overlay(
            RoundedRectangle(cornerRadius: 24)
              .fill(.ultraThinMaterial.opacity(0.7))
          )
          .clipShape(RoundedRectangle(cornerRadius: 24))
      )
    }
    .buttonStyle(ScaleButtonStyle())
  }
}

struct ScaleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
      .animation(.spring(response: 0.3), value: configuration.isPressed)
  }
}

#Preview {
  ZStack {
    Color.gray.opacity(0.1).ignoresSafeArea()

    Welcome(onTap: {
      print("Card tapped")
    })
    .padding(.horizontal)
    .environmentObject(ThemeManager.shared)
  }
}
