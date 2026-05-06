import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @EnvironmentObject var themeManager: ThemeManager

  @AppStorage("globalEnableLiveActivity") private var enableLiveActivity: Bool = false
  @AppStorage("globalEnableReminder") private var enableReminder: Bool = false
  @AppStorage("askToShareAfterSession") private var askToShareAfterSession: Bool = true

  var body: some View {
    NavigationStack {
      Form {
        Section {
          CustomToggle(
            title: String(localized: "動態島 / 鎖定畫面顯示"),
            description: String(localized: "專注時在動態島和鎖定畫面即時顯示計時與狀態"),
            isOn: $enableLiveActivity
          )

          CustomToggle(
            title: String(localized: "完成後詢問是否分享"),
            description: String(localized: "session 滿 30 分鐘且正常結束時，跳出分享提示"),
            isOn: $askToShareAfterSession
          )

          CustomToggle(
            title: String(localized: "Reminder"),
            description: String(localized: "Sends a reminder to start this profile when its ended"),
            isOn: $enableReminder
          )
        }

        if let doCardURL = URL(string: "https://www.do-card.online/") {
          Section {
            Link(destination: doCardURL) {
              HStack {
                Image(systemName: "creditcard.fill")
                  .foregroundStyle(themeManager.themeColor)
                  .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                  Text(String(localized: "Buy DO Card"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                  Text(String(localized: "Get your physical DO Card"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 8)
            }
          }
        }

        Section {
          NavigationLink {
            LicensesView()
          } label: {
            HStack {
              Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
              Text(String(localized: "Licenses"))
            }
          }
        }
      }
      .navigationTitle(String(localized: "Settings"))
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(String(localized: "Close"))
        }
      }
    }
  }
}

#Preview {
  SettingsView()
    .environmentObject(ThemeManager.shared)
}
