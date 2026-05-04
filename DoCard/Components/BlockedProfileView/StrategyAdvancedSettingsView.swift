import SwiftUI

struct StrategyAdvancedSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  var isDisabled: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Text(String(localized: "目前沒有額外設定"))
            .foregroundStyle(.secondary)
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
  StrategyAdvancedSettingsView(
    isDisabled: false
  )
}
