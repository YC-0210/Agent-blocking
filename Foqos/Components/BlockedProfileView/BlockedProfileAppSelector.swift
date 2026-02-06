import FamilyControls
import SwiftUI

struct BlockedProfileAppSelector: View {
  @EnvironmentObject var themeManager: ThemeManager

  var selection: FamilyActivitySelection
  var buttonAction: () -> Void
  var allowMode: Bool = false
  var disabled: Bool = false
  var disabledText: String?

  private var title: String {
    return allowMode ? "Allowed" : "Blocked"
  }

  private var catAndAppCount: Int {
    return FamilyActivityUtil.countSelectedActivities(selection, allowMode: allowMode)
  }

  private var countDisplayText: String {
    return FamilyActivityUtil.getCountDisplayText(selection, allowMode: allowMode)
  }

  private var shouldShowWarning: Bool {
    return FamilyActivityUtil.shouldShowAllowModeWarning(selection, allowMode: allowMode)
  }

  private var buttonText: String {
    return allowMode
      ? String(localized: "Select Apps to Allow")
      : String(localized: "Select Apps to Restrict")
  }

  var body: some View {

    Button(action: buttonAction) {
      HStack {
        Text(buttonText)
          .foregroundStyle(themeManager.themeColor)
        Spacer()
        Image(systemName: "chevron.right")
          .foregroundStyle(.gray)
      }
    }
    .disabled(disabled)

    if let disabledText = disabledText, disabled {
      Text(disabledText)
        .foregroundStyle(.red)
        .padding(.top, 4)
        .font(.caption)
    } else if catAndAppCount == 0 {
      Text(String(localized: "No apps selected"))
        .foregroundStyle(.gray)
    } else {
      VStack(alignment: .leading, spacing: 4) {
        Text("\(countDisplayText) \(String(localized: "selected"))")
          .font(.footnote)
          .foregroundStyle(.gray)

        if shouldShowWarning {
          Text(String(localized: "⚠️ Allow mode: Categories expand to individual apps (50 limit applies)"))
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.top, 4)
        }
      }
      .padding(.top, 4)
    }

  }
}

#Preview {
  BlockedProfileAppSelector(
    selection: FamilyActivitySelection(),
    buttonAction: {},
    disabled: true,
    disabledText: "Disable the current session to edit apps for blocking"
  )

  BlockedProfileAppSelector(
    selection: FamilyActivitySelection(),
    buttonAction: {},
    allowMode: true,
    disabled: true,
    disabledText: "Disable the current session to edit apps for blocking"
  )
}
