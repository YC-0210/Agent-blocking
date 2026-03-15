import FamilyControls
import SwiftUI

/// Shows "Mode: [Name]" with chevron + "Blocking X app(s)".
/// Tapping "Mode: X" opens the Select Mode sheet.
struct DOProfileInfoView: View {
  let profile: BlockedProfiles
  let isBlocking: Bool
  var onModeTapped: (() -> Void)? = nil

  private var appCountText: String {
    FamilyActivityUtil.formatAppCount(profile.selectedActivity)
  }

  var body: some View {
    VStack(spacing: 6) {
      // Mode label — tappable to open Select Mode sheet
      Button {
        if !isBlocking {
          onModeTapped?()
        }
      } label: {
        HStack(spacing: 6) {
          Text(String(localized: "模式：\(profile.name)"))
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(.white)
          if !isBlocking {
            Image(systemName: "chevron.down")
              .font(.system(size: 12, weight: .medium))
              .foregroundColor(.white.opacity(0.5))
          }
        }
      }
      .disabled(isBlocking)

      Text(String(localized: "已封鎖 \(appCountText)"))
        .font(.system(size: 15))
        .foregroundColor(.white.opacity(0.4))
    }
  }
}

#Preview {
  DOProfileInfoView(
    profile: BlockedProfiles(name: "Deep Work"),
    isBlocking: false,
    onModeTapped: {}
  )
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color.black)
  .preferredColorScheme(.dark)
}
