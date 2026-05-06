import Photos
import SwiftUI

/// Full-screen preview/share page presented after the user taps "分享" in the prompt sheet.
/// Renders a 1080×1920 transparent PNG of the just-completed session and offers two actions:
/// "儲存到相簿" (saves to Photos) and "分享至…" (iOS share sheet). Swipe down to dismiss.
struct FocusShareCardView: View {
  @EnvironmentObject var themeManager: ThemeManager

  let profileName: String
  let duration: TimeInterval

  @State private var renderedImage: UIImage?
  @State private var savedToPhotosToast = false
  @State private var saveErrorMessage: String?

  var body: some View {
    VStack(spacing: 28) {
      // Drag indicator (visual cue that the page swipes down)
      Capsule()
        .fill(Color.white.opacity(0.25))
        .frame(width: 40, height: 5)
        .padding(.top, 12)

      Spacer(minLength: 0)

      // Card preview — transparent PNG laid over a dark backdrop so the white text is legible.
      // The exported image stays transparent; the dark card here is preview-only.
      if let image = renderedImage {
        Image(uiImage: image)
          .resizable()
          .scaledToFit()
          .background(
            RoundedRectangle(cornerRadius: 28)
              .fill(Color(white: 0.08))
          )
          .clipShape(RoundedRectangle(cornerRadius: 28))
          .padding(.horizontal, 32)
          .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
      } else {
        ProgressView()
          .frame(maxWidth: .infinity, minHeight: 420)
      }

      Spacer(minLength: 0)

      // Buttons
      VStack(spacing: 12) {
        Button(action: saveToPhotos) {
          Label(
            String(localized: "儲存到相簿"),
            systemImage: "square.and.arrow.down"
          )
          .font(.headline)
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(themeManager.themeColor)
          .clipShape(RoundedRectangle(cornerRadius: 14))
        }

        Button(action: shareImage) {
          Label(
            String(localized: "分享至…"),
            systemImage: "square.and.arrow.up"
          )
          .font(.headline)
          .foregroundStyle(themeManager.themeColor)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 16)
          .background(
            RoundedRectangle(cornerRadius: 14)
              .stroke(themeManager.themeColor, lineWidth: 1.5)
          )
        }
      }
      .padding(.horizontal, 32)
      .padding(.bottom, 24)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.black.ignoresSafeArea())
    .overlay(alignment: .top) {
      if savedToPhotosToast {
        Text(String(localized: "已儲存到相簿"))
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 10)
          .background(Capsule().fill(Color.black.opacity(0.85)))
          .overlay(Capsule().stroke(Color.white.opacity(0.15)))
          .padding(.top, 60)
          .transition(.move(edge: .top).combined(with: .opacity))
      }
    }
    .alert(
      String(localized: "無法儲存"),
      isPresented: Binding(
        get: { saveErrorMessage != nil },
        set: { if !$0 { saveErrorMessage = nil } }
      )
    ) {
      Button(String(localized: "OK"), role: .cancel) { saveErrorMessage = nil }
    } message: {
      Text(saveErrorMessage ?? "")
    }
    .onAppear {
      if renderedImage == nil {
        renderedImage = FocusShareCardGenerator.render(
          profileName: profileName,
          duration: duration
        )
      }
    }
  }

  // MARK: - Save to Photos

  private func saveToPhotos() {
    guard let image = renderedImage else { return }

    PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
      DispatchQueue.main.async {
        switch status {
        case .authorized, .limited:
          performSave(image: image)
        case .denied, .restricted:
          saveErrorMessage = String(
            localized: "請到「設定」開啟相簿存取權限，才能儲存卡片。"
          )
        case .notDetermined:
          // Re-prompt path; the OS sheet is what we just asked for, so this should not occur.
          saveErrorMessage = String(localized: "請允許相簿存取權限後再試一次。")
        @unknown default:
          saveErrorMessage = String(localized: "無法儲存到相簿，請稍後再試。")
        }
      }
    }
  }

  private func performSave(image: UIImage) {
    PHPhotoLibrary.shared().performChanges({
      // Convert to PNG data and create asset to preserve transparency.
      if let pngData = image.pngData() {
        let request = PHAssetCreationRequest.forAsset()
        request.addResource(with: .photo, data: pngData, options: nil)
      } else {
        PHAssetChangeRequest.creationRequestForAsset(from: image)
      }
    }) { success, error in
      DispatchQueue.main.async {
        if success {
          showSavedToast()
        } else {
          saveErrorMessage = error?.localizedDescription
            ?? String(localized: "無法儲存到相簿，請稍後再試。")
        }
      }
    }
  }

  private func showSavedToast() {
    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
      savedToPhotosToast = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
      withAnimation(.easeOut(duration: 0.25)) {
        savedToPhotosToast = false
      }
    }
  }

  // MARK: - Share via UIActivityViewController

  private func shareImage() {
    guard let image = renderedImage,
      let pngData = image.pngData()
    else { return }

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("DOFocusCard.png")
    try? pngData.write(to: tempURL)

    let activityVC = UIActivityViewController(
      activityItems: [tempURL],
      applicationActivities: nil
    )

    guard let windowScene = UIApplication.shared.connectedScenes
      .compactMap({ $0 as? UIWindowScene }).first,
      let rootVC = windowScene.windows.first?.rootViewController
    else { return }

    var presenter = rootVC
    while let next = presenter.presentedViewController {
      presenter = next
    }

    activityVC.popoverPresentationController?.sourceView = presenter.view
    presenter.present(activityVC, animated: true)
  }
}

#Preview {
  FocusShareCardView(
    profileName: "國文複習",
    duration: 5025
  )
  .environmentObject(ThemeManager.shared)
}
