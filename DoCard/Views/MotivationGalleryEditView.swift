import PhotosUI
import SwiftData
import SwiftUI

struct MotivationGalleryEditView: View {
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  @Query(sort: \MotivationPhoto.sortOrder, order: .forward)
  private var photos: [MotivationPhoto]

  @State private var pickerItem: PhotosPickerItem?
  @State private var photoToDelete: MotivationPhoto?

  private var atLimit: Bool { photos.count >= MotivationPhoto.maxCount }

  private var deleteAlertPresented: Binding<Bool> {
    Binding(
      get: { photoToDelete != nil },
      set: { if !$0 { photoToDelete = nil } }
    )
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(photos) { photo in
            MotivationPhotoRow(photo: photo) {
              photoToDelete = photo
            }
          }
          .onMove(perform: move)
        } header: {
          Text(String(localized: "照片 \(photos.count)/\(MotivationPhoto.maxCount)"))
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))

        Section {
          if atLimit {
            Label(String(localized: "已達最多 5 張"), systemImage: "checkmark.circle")
              .foregroundStyle(.secondary)
          } else {
            PhotosPicker(selection: $pickerItem, matching: .images) {
              Label(String(localized: "新增照片"), systemImage: "plus.circle.fill")
                .foregroundStyle(themeManager.themeColor)
            }
          }
        }
        .listRowBackground(Color(.systemGray6).opacity(0.08))
      }
      .scrollContentBackground(.hidden)
      .background(Color.black.ignoresSafeArea())
      .navigationTitle(String(localized: "我的動力"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          if !photos.isEmpty { EditButton() }
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button(String(localized: "完成")) { dismiss() }
            .fontWeight(.semibold)
        }
      }
      .onChange(of: pickerItem) { _, item in
        guard let item else { return }
        Task { await importPhoto(item) }
      }
      .alert(
        String(localized: "確定要移除這張照片嗎？"),
        isPresented: deleteAlertPresented,
        presenting: photoToDelete
      ) { photo in
        Button(String(localized: "移除"), role: .destructive) { delete(photo) }
        Button(String(localized: "取消"), role: .cancel) {}
      }
    }
  }

  // MARK: - Mutations

  private func importPhoto(_ item: PhotosPickerItem) async {
    defer { pickerItem = nil }
    guard photos.count < MotivationPhoto.maxCount,
      let data = try? await item.loadTransferable(type: Data.self),
      let uiImage = UIImage(data: data),
      let storable = MotivationImageProcessor.makeStorableData(from: uiImage)
    else { return }

    let nextOrder = (photos.map(\.sortOrder).max() ?? -1) + 1
    modelContext.insert(MotivationPhoto(imageData: storable, sortOrder: nextOrder))
    try? modelContext.save()
  }

  private func move(from source: IndexSet, to destination: Int) {
    var reordered = photos
    reordered.move(fromOffsets: source, toOffset: destination)
    for (index, photo) in reordered.enumerated() {
      photo.sortOrder = index
    }
    try? modelContext.save()
  }

  private func delete(_ photo: MotivationPhoto) {
    modelContext.delete(photo)
    let remaining = photos.filter { $0.id != photo.id }
    for (index, item) in remaining.enumerated() {
      item.sortOrder = index
    }
    try? modelContext.save()
  }
}

// MARK: - Row

private struct MotivationPhotoRow: View {
  @Bindable var photo: MotivationPhoto
  let onDelete: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      if let uiImage = UIImage(data: photo.imageData) {
        Image(uiImage: uiImage)
          .resizable()
          .scaledToFill()
          .frame(width: 56, height: 56)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      } else {
        RoundedRectangle(cornerRadius: 8)
          .fill(Color(.systemGray5))
          .frame(width: 56, height: 56)
          .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
      }

      TextField(
        String(localized: "寫下這張照片對你的意義…"),
        text: $photo.caption,
        axis: .vertical
      )
      .font(.subheadline)
      .lineLimit(1...3)

      Button(role: .destructive, action: onDelete) {
        Image(systemName: "trash")
          .foregroundStyle(.red)
      }
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 4)
  }
}
