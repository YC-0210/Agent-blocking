import SwiftData
import SwiftUI

/// A sheet that lets users browse existing modes, switch between them,
/// edit individual modes, or create new ones.
struct SelectModeView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  let profiles: [BlockedProfiles]
  @Binding var selectedIndex: Int
  var onEditProfile: (BlockedProfiles) -> Void
  var onCreateNew: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Header
      HStack {
        Spacer()
        Text(String(localized: "選擇模式"))
          .font(.system(size: 18, weight: .semibold))
        Spacer()
      }
      .overlay(alignment: .trailing) {
        Button(action: { dismiss() }) {
          Image(systemName: "xmark")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: 30, height: 30)
            .background(Color(.tertiarySystemFill))
            .clipShape(Circle())
        }
      }
      .padding(.horizontal, 20)
      .padding(.top, 20)
      .padding(.bottom, 24)

      // Mode list
      VStack(spacing: 12) {
        ForEach(profiles.indices, id: \.self) { index in
          let profile = profiles[index]
          let isSelected = index == selectedIndex

          HStack {
            Text(profile.name)
              .font(.system(size: 17, weight: isSelected ? .semibold : .regular))
              .foregroundColor(.primary)

            Spacer()

            Button {
              onEditProfile(profile)
              dismiss()
            } label: {
              Text(String(localized: "編輯"))
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.primary)
            }
          }
          .padding(.horizontal, 20)
          .padding(.vertical, 16)
          .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .fill(isSelected ? Color(.systemBackground) : Color(.secondarySystemBackground))
          )
          .shadow(color: isSelected ? Color.black.opacity(0.06) : .clear, radius: 4, y: 2)
          .contentShape(Rectangle())
          .onTapGesture {
            selectedIndex = index
            dismiss()
          }
        }

        // Create mode row
        HStack {
          Text(String(localized: "新增模式"))
            .font(.system(size: 17, weight: .regular))
            .foregroundColor(.primary)

          Spacer()

          Image(systemName: "plus")
            .font(.system(size: 15, weight: .medium))
            .foregroundColor(.primary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
          RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color(.secondarySystemBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture {
          onCreateNew()
          dismiss()
        }
      }
      .padding(.horizontal, 20)

      Spacer()

      // Done button — orange
      Button(action: { dismiss() }) {
        Text(String(localized: "完成"))
          .font(.system(size: 17, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 56)
          .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
              .fill(themeManager.themeColor)
          )
      }
      .padding(.horizontal, 20)
      .padding(.bottom, 30)
    }
    .background(Color(.systemGroupedBackground).ignoresSafeArea())
  }
}

#Preview {
  SelectModeView(
    profiles: [
      BlockedProfiles(name: "Deep Work"),
      BlockedProfiles(name: "Gaming"),
    ],
    selectedIndex: .constant(0),
    onEditProfile: { _ in },
    onCreateNew: {}
  )
  .environmentObject(ThemeManager.shared)
}
