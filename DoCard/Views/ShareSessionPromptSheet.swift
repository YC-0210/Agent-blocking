import SwiftUI

/// Bottom-sheet prompt shown after a session ends (≥ 30 min, normal completion, toggle on).
/// "分享" advances to the full-screen `FocusShareCardView`. "稍後" dismisses for this session only.
struct ShareSessionPromptSheet: View {
  @EnvironmentObject var themeManager: ThemeManager

  let profileName: String
  let duration: TimeInterval
  let onShare: () -> Void
  let onLater: () -> Void

  @State private var thumbnail: UIImage?

  var body: some View {
    VStack(spacing: 24) {
      Text(String(localized: "分享你的專注"))
        .font(.title3.weight(.bold))
        .padding(.top, 28)

      // Thumbnail preview — transparent PNG laid over a dark backdrop for legibility.
      // The real exported image stays transparent.
      Group {
        if let image = thumbnail {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
        } else {
          ProgressView()
        }
      }
      .frame(maxHeight: 280)
      .background(
        RoundedRectangle(cornerRadius: 20)
          .fill(Color(white: 0.08))
      )
      .clipShape(RoundedRectangle(cornerRadius: 20))
      .padding(.horizontal, 32)

      VStack(spacing: 10) {
        Button(action: onShare) {
          Text(String(localized: "分享"))
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(themeManager.themeColor)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }

        Button(action: onLater) {
          Text(String(localized: "稍後"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
      }
      .padding(.horizontal, 32)
      .padding(.bottom, 16)
    }
    .onAppear {
      if thumbnail == nil {
        thumbnail = FocusShareCardGenerator.render(
          profileName: profileName,
          duration: duration
        )
      }
    }
  }
}

#Preview {
  Color.gray
    .sheet(isPresented: .constant(true)) {
      ShareSessionPromptSheet(
        profileName: "國文複習",
        duration: 5025,
        onShare: {},
        onLater: {}
      )
      .presentationDetents([.height(520)])
      .environmentObject(ThemeManager.shared)
    }
}
