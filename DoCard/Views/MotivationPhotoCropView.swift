import SwiftUI
import UIKit

/// Instagram-style crop screen shown after the user picks a photo. The photo
/// can be pinch-zoomed and dragged behind a fixed-aspect crop window; "使用"
/// renders the visible window to a new image at the card's aspect ratio.
///
/// The root is a plain VStack (not a GeometryReader): a root GeometryReader in
/// a fullScreenCover fills the whole screen and zeroes the safe area, which is
/// what pushed the top bar under the status bar before. The width needed for
/// the crop window is read by a GeometryReader in the background instead.
struct MotivationPhotoCropView: View {
  let image: UIImage
  var targetAspect: CGFloat = 1.585
  let onCancel: () -> Void
  let onConfirm: (UIImage) -> Void

  @State private var scale: CGFloat = 1
  @State private var lastScale: CGFloat = 1
  @State private var offset: CGSize = .zero
  @State private var lastOffset: CGSize = .zero
  @State private var contentWidth: CGFloat = 0

  private var cropW: CGFloat { max(0, contentWidth - 32) }
  private var cropH: CGFloat { cropW / targetAspect }
  private var base: CGSize {
    let imgAspect = image.size.width / max(image.size.height, 1)
    if imgAspect > targetAspect {
      return CGSize(width: cropH * imgAspect, height: cropH)
    } else {
      return CGSize(width: cropW, height: cropW / imgAspect)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack {
        Button(action: onCancel) {
          Text(String(localized: "取消"))
            .font(.system(size: 17))
            .foregroundColor(.white)
        }
        Spacer()
        Button(action: confirm) {
          Text(String(localized: "使用"))
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
        }
      }
      .padding(.horizontal, 20)
      .padding(.vertical, 12)

      Spacer(minLength: 0)

      if cropW > 0 {
        Image(uiImage: image)
          .resizable()
          .frame(width: base.width * scale, height: base.height * scale)
          .offset(offset)
          .frame(width: cropW, height: cropH)
          .clipShape(RoundedRectangle(cornerRadius: 24))
          .overlay(
            RoundedRectangle(cornerRadius: 24)
              .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
          )
          .contentShape(Rectangle())
          .gesture(
            DragGesture()
              .onChanged { value in
                let proposed = CGSize(
                  width: lastOffset.width + value.translation.width,
                  height: lastOffset.height + value.translation.height
                )
                offset = clamp(proposed)
              }
              .onEnded { _ in lastOffset = offset }
          )
          .simultaneousGesture(
            MagnificationGesture()
              .onChanged { value in
                scale = min(5, max(1, lastScale * value))
                offset = clamp(offset)
              }
              .onEnded { _ in
                lastScale = scale
                lastOffset = offset
              }
          )
      }

      Spacer(minLength: 0)

      Text(String(localized: "縮放、拖動以調整顯示範圍"))
        .font(.footnote)
        .foregroundColor(.white.opacity(0.6))
        .padding(.bottom, 12)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      GeometryReader { geo in
        Color.black
          .onAppear { contentWidth = geo.size.width }
          .onChange(of: geo.size.width) { _, newWidth in contentWidth = newWidth }
      }
      .ignoresSafeArea()
    )
  }

  /// Keeps the (possibly zoomed) image covering the crop window so no empty
  /// area can show.
  private func clamp(_ proposed: CGSize) -> CGSize {
    let w = base.width * scale
    let h = base.height * scale
    let maxX = max(0, (w - cropW) / 2)
    let maxY = max(0, (h - cropH) / 2)
    return CGSize(
      width: min(maxX, max(-maxX, proposed.width)),
      height: min(maxY, max(-maxY, proposed.height))
    )
  }

  @MainActor
  private func confirm() {
    guard cropW > 0 else { return }
    let content = Image(uiImage: image)
      .resizable()
      .frame(width: base.width * scale, height: base.height * scale)
      .offset(offset)
      .frame(width: cropW, height: cropH)
      .clipped()

    let renderer = ImageRenderer(content: content)
    renderer.scale = max(1, 1600 / cropW)
    if let result = renderer.uiImage {
      onConfirm(result)
    } else {
      onConfirm(image)
    }
  }
}
