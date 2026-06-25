import SwiftUI

struct CustomToggle: View {
  @EnvironmentObject var themeManager: ThemeManager

  /// Optional leading SF Symbol, so a toggle row can line up with the icon’d
  /// action/navigation rows in Settings. When `nil`, the row renders exactly as
  /// before (backward compatible).
  var systemImage: String? = nil
  /// Tint for the leading icon; defaults to the brand color via `ThemeManager`.
  var iconColor: Color? = nil

  let title: String
  let description: String
  @Binding var isOn: Bool
  var isDisabled: Bool = false
  var errorMessage: String? = nil

  /// Width of the leading icon column — matches the spacing so the description
  /// can align under the title when an icon is present.
  private let iconColumnWidth: CGFloat = 28
  private let iconSpacing: CGFloat = 12

  /// Left inset that aligns the description under the title (past the icon).
  /// Zero when there is no icon, preserving the original layout.
  private var descriptionLeadingInset: CGFloat {
    systemImage == nil ? 0 : iconColumnWidth + iconSpacing
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Toggle(isOn: $isOn) {
        HStack(spacing: iconSpacing) {
          if let systemImage {
            Image(systemName: systemImage)
              .font(.title3)
              .foregroundStyle(iconColor ?? themeManager.themeColor)
              .frame(width: iconColumnWidth)
          }
          Text(title)
        }
      }
      .disabled(isDisabled)
      .tint(themeManager.themeColor)

      Text(description)
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.vertical, 4)
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(nil)
        .padding(.leading, descriptionLeadingInset)
        .padding(.trailing, 80)

      if isDisabled && errorMessage != nil {
        Text(errorMessage!)
          .font(.caption)
          .foregroundColor(.red)
          .padding(.leading, descriptionLeadingInset)
      }
    }
  }
}

#Preview {
  VStack(alignment: .leading, spacing: 16) {
    CustomToggle(
      systemImage: "bell.badge",
      title: "With icon",
      description: "A toggle row with a leading icon, aligned with action rows.",
      isOn: .constant(true)
    )

    CustomToggle(
      title: "Enable Feature",
      description: "No icon — renders exactly as before (backward compatible).",
      isOn: .constant(true)
    )

    CustomToggle(
      title: "Enable Feature",
      description:
        "This is a toggle with a really long description so that it doesn't look so weird and super strange",
      isOn: .constant(false)
    )

    CustomToggle(
      systemImage: "alarm",
      title: "Disabled Toggle",
      description: "This toggle is currently disabled.",
      isOn: .constant(false),
      isDisabled: true
    )
  }
  .padding()
  .environmentObject(ThemeManager.shared)
}
