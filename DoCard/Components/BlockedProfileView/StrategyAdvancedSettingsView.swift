import SwiftUI

struct StrategyAdvancedSettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  @Binding var enableBreaks: Bool
  @Binding var breakTimeInMinutes: Int
  var isDisabled: Bool

  var body: some View {
    NavigationStack {
      Form {
        Section(String(localized: "Breaks")) {
          CustomToggle(
            title: String(localized: "Allow Timed Breaks"),
            description: String(localized: "Take a single break during your session. The break will automatically end after the selected duration."),
            isOn: $enableBreaks,
            isDisabled: isDisabled
          )

          if enableBreaks {
            Picker(String(localized: "Break Duration"), selection: $breakTimeInMinutes) {
              Text(String(localized: "5 minutes")).tag(5)
              Text(String(localized: "10 minutes")).tag(10)
              Text(String(localized: "15 minutes")).tag(15)
              Text(String(localized: "30 minutes")).tag(30)
            }
            .disabled(isDisabled)
          }
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
    enableBreaks: .constant(false),
    breakTimeInMinutes: .constant(15),
    isDisabled: false
  )
}
