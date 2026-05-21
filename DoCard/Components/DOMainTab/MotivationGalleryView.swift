import SwiftData
import SwiftUI

/// Swipeable motivation photo gallery shown in the centerpiece slot of the
/// main tab (replaces `DOCardImageView`). Browse-only: swipe to change photo,
/// pencil (top-right) to open the edit screen. Shows an empty state when the
/// user has not added any photos yet.
struct MotivationGalleryView: View {
  @EnvironmentObject var themeManager: ThemeManager

  @Query(sort: \MotivationPhoto.sortOrder, order: .forward)
  private var photos: [MotivationPhoto]

  @State private var currentIndex = 0
  @State private var showEditor = false

  private let maxCardWidth: CGFloat = 300
  private let aspect: CGFloat = 1.585
  private let corner: CGFloat = 24

  private var currentCaption: String? {
    guard photos.indices.contains(currentIndex) else { return nil }
    let caption = photos[currentIndex].caption
    return caption.isEmpty ? nil : caption
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Group {
        if photos.isEmpty {
          emptyState
        } else {
          galleryContent
        }
      }
      editPencil
    }
    .frame(maxWidth: maxCardWidth)
    .aspectRatio(aspect, contentMode: .fit)
    .frame(maxWidth: .infinity)
    // Speech bubble floats above the photo (overlay → no layout change).
    .overlay(alignment: .top) {
      if !photos.isEmpty, let caption = currentCaption {
        captionBubble(caption)
          .alignmentGuide(.top) { $0.height }
          .animation(.easeInOut(duration: 0.2), value: currentIndex)
      }
    }
    .sheet(isPresented: $showEditor) {
      MotivationGalleryEditView()
        .environmentObject(themeManager)
    }
    .onChange(of: photos.count) { _, count in
      if currentIndex >= count { currentIndex = max(0, count - 1) }
    }
  }

  // MARK: - Gallery

  private var galleryContent: some View {
    ZStack(alignment: .bottom) {
      TabView(selection: $currentIndex) {
        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
          photoCell(photo).tag(index)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .clipShape(RoundedRectangle(cornerRadius: corner))
      .shadow(color: themeManager.themeColor.opacity(0.35), radius: 40)
      .shadow(color: themeManager.themeColor.opacity(0.25), radius: 20)
      .shadow(color: themeManager.themeColor.opacity(0.15), radius: 8)

      if photos.count > 1 {
        dots.padding(.bottom, 8)
      }
    }
  }

  private func photoCell(_ photo: MotivationPhoto) -> some View {
    ZStack {
      if let uiImage = UIImage(data: photo.imageData) {
        // Blurred copy of the same photo fills the letterbox area behind the
        // full image, so nothing is cropped and the card frame stays fixed.
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .clipped()
          .blur(radius: 18)
          .overlay(Color.black.opacity(0.12))
        // Full photo, never cropped.
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Color(.systemGray5)
          .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
      }
    }
  }

  private var dots: some View {
    HStack(spacing: 6) {
      ForEach(photos.indices, id: \.self) { index in
        Circle()
          .fill(index == currentIndex ? Color.white : Color.white.opacity(0.4))
          .frame(width: 6, height: 6)
      }
    }
  }

  // MARK: - Caption bubble

  private func captionBubble(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 13, weight: .medium))
      .foregroundColor(.white)
      .lineLimit(2)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: maxCardWidth - 80)
      .padding(.horizontal, 12)
      .padding(.vertical, 7)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.black.opacity(0.6))
      )
      .overlay(alignment: .bottom) {
        DownTriangle()
          .fill(Color.black.opacity(0.6))
          .frame(width: 12, height: 6)
          .offset(y: 6)
      }
  }

  // MARK: - Empty state

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "photo.on.rectangle.angled")
        .font(.system(size: 32, weight: .light))
        .foregroundColor(.white.opacity(0.5))

      Text(String(localized: "放一張讓你繼續做下去的照片"))
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.white.opacity(0.85))
        .multilineTextAlignment(.center)

      Text(String(localized: "為了誰？為了什麼？讓它每天提醒你。"))
        .font(.system(size: 12))
        .foregroundColor(.white.opacity(0.45))
        .multilineTextAlignment(.center)

      Button(action: { showEditor = true }) {
        Text(String(localized: "新增第一張照片"))
          .font(.system(size: 14, weight: .semibold))
          .foregroundColor(.white)
          .padding(.horizontal, 18)
          .padding(.vertical, 9)
          .background(Capsule().fill(themeManager.themeColor))
      }
      .padding(.top, 4)
    }
    .padding(.horizontal, 16)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      RoundedRectangle(cornerRadius: corner)
        .fill(Color.white.opacity(0.04))
        .overlay(
          RoundedRectangle(cornerRadius: corner)
            .stroke(
              Color.white.opacity(0.12),
              style: StrokeStyle(lineWidth: 1, dash: [6])
            )
        )
    )
  }

  // MARK: - Edit entry

  private var editPencil: some View {
    Button(action: { showEditor = true }) {
      Image(systemName: "pencil")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .frame(width: 34, height: 34)
        .background(Circle().fill(Color.black.opacity(0.4)))
        .frame(width: 44, height: 44)
        .contentShape(Rectangle())
    }
    .padding(6)
  }
}

// MARK: - Bubble tail

private struct DownTriangle: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
