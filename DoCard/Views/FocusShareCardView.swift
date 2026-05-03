import SwiftUI

/// Sheet presented after a focus session > 1 hour completes normally.
/// Shows a preview of the transparent PNG sticker and offers share / dismiss.
struct FocusShareCardView: View {
  @EnvironmentObject var themeManager: ThemeManager

  let profileName: String
  let duration: TimeInterval
  let onDismiss: () -> Void

  @State private var renderedImage: UIImage?

  var body: some View {
    VStack(spacing: 32) {
      Spacer()

      // MARK: - Sticker preview
      if let image = renderedImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 420)
          .background(
            RoundedRectangle(cornerRadius: 20)
              .fill(Color.black.opacity(0.85))
          )
          .clipShape(RoundedRectangle(cornerRadius: 20))
          .padding(.horizontal, 32)
      } else {
        ProgressView()
          .frame(height: 420)
      }

      // MARK: - Buttons
      VStack(spacing: 14) {
        Button(action: shareImage) {
          HStack {
            Image(systemName: "square.and.arrow.up")
            Text(String(localized: "儲存 / 分享"))
          }
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 14)
          .background(themeManager.themeColor)
          .clipShape(RoundedRectangle(cornerRadius: 14))
        }

        Button(action: onDismiss) {
          Text(String(localized: "略過"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 32)

      Spacer()
    }
    .onAppear {
      renderedImage = FocusShareCardGenerator.render(
        profileName: profileName,
        duration: duration
      )
    }
  }

  // MARK: - Share via UIActivityViewController

  private func shareImage() {
    guard let image = renderedImage,
          let pngData = image.pngData()
    else { return }

    // Write to a temp file so the share sheet sends a .png (not JPEG)
    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("DOFocusCard.png")
    try? pngData.write(to: tempURL)

    let activityVC = UIActivityViewController(
      activityItems: [tempURL],
      applicationActivities: nil
    )

    // Present from the top-most scene
    guard let windowScene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).first,
          let rootVC = windowScene.windows.first?.rootViewController
    else { return }

    // Walk to the top-most presented controller
    var presenter = rootVC
    while let next = presenter.presentedViewController {
      presenter = next
    }

    // iPad popover anchor
    activityVC.popoverPresentationController?.sourceView = presenter.view

    presenter.present(activityVC, animated: true)
  }
}

#Preview {
  FocusShareCardView(
    profileName: "深度工作",
    duration: 5025,
    onDismiss: {}
  )
  .environmentObject(ThemeManager.shared)
}
