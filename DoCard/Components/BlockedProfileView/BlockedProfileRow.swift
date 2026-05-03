import FamilyControls
import SwiftUI

struct ProfileRow: View {
  let profile: BlockedProfiles

  var formattedUpdateTime: String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .short
    return formatter.localizedString(for: profile.updatedAt, relativeTo: Date())
  }

  var selectedItemsText: String {
    FamilyActivityUtil.formatAppCount(profile.selectedActivity)
  }

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 12) {
        Text(profile.name)
          .font(.headline)

        HStack(spacing: 4) {
          Image(systemName: "clock")
          Text(String(localized: "Updated \(formattedUpdateTime)"))
        }
        .foregroundStyle(.secondary)
        .font(.caption)
      }

      Spacer()

      HStack(spacing: 4) {
        Image(systemName: "list.bullet.circle.fill")
        Text(selectedItemsText)
      }
      .foregroundStyle(.secondary)
      .font(.subheadline)
    }
  }
}

#Preview {
  let previewProfile = BlockedProfiles(
    name: "⌛ School Hours",
    selectedActivity: FamilyActivitySelection(),
    createdAt: Date(),
    updatedAt: Date().addingTimeInterval(-3600)
  )

  return ProfileRow(profile: previewProfile)
    .padding()
}
