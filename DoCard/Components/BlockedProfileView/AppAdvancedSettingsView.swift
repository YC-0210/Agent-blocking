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
            title: String(localized: "允許模式"),
            description: String(localized: "選擇要允許的 App，其餘全部阻擋。這將清除你目前的所有選擇。"),
            isOn: $enableAllowMode,
            isDisabled: isDisabled
          )
        }

        Section {
          CustomToggle(
            title: String(localized: "阻擋 Safari"),
            description: String(localized: "阻擋上方選擇的 Safari 網站。關閉後，無論選擇什麼網站都不會被阻擋。"),
            isOn: $enableSafariBlocking,
            isDisabled: isDisabled
          )
        }
      }
      .navigationTitle(String(localized: "進階設定"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button(action: { dismiss() }) {
            Text(String(localized: "完成"))
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
