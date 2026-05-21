import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct OnboardingPhotoGalleryPage: View {
  @EnvironmentObject var themeManager: ThemeManager
  @Environment(\.modelContext) private var modelContext

  let onContinue: () -> Void

  @State private var pickerItem: PhotosPickerItem?
  @State private var imageToCrop: UIImage?
  @State private var pendingCrop: UIImage?
  @State private var pendingOriginal: UIImage?
  @State private var caption: String = ""
  @State private var showContent = false

  var body: some View {
    ZStack(alignment: .top) {
      VStack(spacing: 0) {
        Spacer().frame(height: 64)

        Text(String(localized: "你是為了什麼在努力呢"))
          .font(.system(size: 28, weight: .bold))
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .padding(.bottom, 8)

        Text(String(localized: "一個人？一個目標？"))
          .font(.system(size: 16, weight: .regular))
          .foregroundColor(.white.opacity(0.5))
          .multilineTextAlignment(.center)

        Spacer()

        if let cropped = pendingCrop {
          VStack(spacing: 16) {
            Image(uiImage: cropped)
              .resizable()
              .scaledToFill()
              .aspectRatio(1.585, contentMode: .fit)
              .frame(maxWidth: 300)
              .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            TextField(
              String(localized: "想對他說的話…"),
              text: $caption,
              axis: .vertical
            )
            .font(.system(size: 15))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .lineLimit(1...3)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.08))
            )
            .colorScheme(.dark)

            Button(action: { pendingCrop = nil; pendingOriginal = nil; caption = "" }) {
              Text(String(localized: "重新選擇照片"))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
            }
          }
          .frame(maxWidth: .infinity)
        } else {
          addBlock
        }

        Spacer()

        if pendingCrop != nil {
          Button(action: savePhotoAndContinue) {
            Text(String(localized: "繼續"))
              .font(.system(size: 18, weight: .semibold))
              .foregroundColor(.white)
              .frame(maxWidth: .infinity)
              .frame(height: 58)
              .background(Capsule().fill(themeManager.themeColor))
          }
          .padding(.bottom, 30)
        } else {
          Spacer().frame(height: 88)
        }
      }
      .padding(.horizontal, 24)
      .opacity(showContent ? 1 : 0)
      .offset(y: showContent ? 0 : 12)

      // Skip — top right
      HStack {
        Spacer()
        Button(action: onContinue) {
          Text(String(localized: "略過"))
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
        }
      }
      .padding(.trailing, 16)
      .padding(.top, 8)
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.6).delay(0.15)) { showContent = true }
    }
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      Task { await loadPicked(item) }
    }
    // Embedded as an overlay (not fullScreenCover): a fullScreenCover in this
    // app presents with a zeroed safe area, which pushed the crop top bar under
    // the status bar. Staying in the page hierarchy keeps the safe area intact.
    .overlay {
      if let image = imageToCrop {
        MotivationPhotoCropView(
          image: image,
          onCancel: { imageToCrop = nil },
          onConfirm: { cropped in
            pendingCrop = cropped
            pendingOriginal = imageToCrop
            imageToCrop = nil
          }
        )
      }
    }
  }

  private var addBlock: some View {
    PhotosPicker(selection: $pickerItem, matching: .images) {
      ZStack {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
          .fill(Color.white.opacity(0.05))
          .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
              .stroke(
                Color.white.opacity(0.18),
                style: StrokeStyle(lineWidth: 1.5, dash: [7])
              )
          )
        VStack(spacing: 10) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 42, weight: .light))
            .foregroundColor(themeManager.themeColor)
          Text(String(localized: "新增照片"))
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.white)
        }
      }
      .aspectRatio(1.585, contentMode: .fit)
      .frame(maxWidth: 300)
    }
  }

  private func loadPicked(_ item: PhotosPickerItem) async {
    defer { pickerItem = nil }
    guard let data = try? await item.loadTransferable(type: Data.self),
      let uiImage = UIImage(data: data)
    else { return }
    imageToCrop = uiImage
  }

  private func savePhotoAndContinue() {
    if let cropped = pendingCrop,
      let display = MotivationImageProcessor.makeStorableData(from: cropped)
    {
      let original = pendingOriginal.flatMap {
        MotivationImageProcessor.makeStorableData(
          from: $0,
          maxDimension: MotivationImageProcessor.originalMaxDimension
        )
      }
      let nextOrder = (MotivationPhoto.allSorted(in: modelContext).map(\.sortOrder).max() ?? -1) + 1
      modelContext.insert(
        MotivationPhoto(
          imageData: display,
          originalImageData: original,
          caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
          sortOrder: nextOrder
        )
      )
      try? modelContext.save()
    }
    onContinue()
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingPhotoGalleryPage(onContinue: {})
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
