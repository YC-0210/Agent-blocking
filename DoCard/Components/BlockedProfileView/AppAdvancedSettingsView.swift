import SwiftUI

struct AppAdvancedSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  @Binding var enableAllowMode: Bool
  @Binding var enableSafariBlocking: Bool
  var isDisabled: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          CustomToggle(
            title: String(localized: "Apps Allow Mode"),
            description: String(localized: "Pick apps to allow and block everything else. This will erase any other selection you've made."),
            isOn: $enableAllowMode,
            isDisabled: isDisabled
          )
        }

        Section {
          CustomToggle(
            title: String(localized: "Block Safari"),
            description: String(localized: "Block Safari websites that are selected in the app selector above. When disabled, Safari will not be limited regardless of the websites you pick."),
            isOn: $enableSafariBlocking,
            isDisabled: isDisabled
          )
        }
      }
      .navigationTitle(String(localized: "Advanced Settings"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Text(String(localized: "Done"))
              .foregroundStyle(themeManager.themeColor)
          }
        }
      }
    }
  }
}

#Preview {
  AppAdvancedSettingsView(
    enableAllowMode: .constant(false),
    enableSafariBlocking: .constant(true),
    isDisabled: false
  )
}
