import SwiftUI
import UIKit
import UserNotifications

@main
struct AgentBlockingApp: App {
  @UIApplicationDelegateAdaptor(AgentFocusAppDelegate.self) private var agentDelegate
  @StateObject private var runtime = AgentFocusRuntime.shared
  @StateObject private var authorizer = RequestAuthorizer()
  @Environment(\.scenePhase) private var scenePhase
  @State private var setupError = false
  @State private var alertsDisabled = false
  @Environment(\.openURL) private var openURL

  var body: some Scene {
    WindowGroup {
      AgentFocusView(runtime: runtime)
        .environmentObject(authorizer)
        .safeAreaInset(edge: .bottom) {
          VStack(spacing: 8) {
            if runtime.configured && alertsDisabled {
              Button {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                  openURL(url)
                }
              } label: {
                Label(
                  String(
                    localized: "Enable notification alerts for remote commands", table: "AgentFocus"
                  ),
                  systemImage: "bell.slash"
                )
                .multilineTextAlignment(.center)
              }
            }
            if let url = URL(
              string:
                "https://github.com/YC-0210/Agent-blocking/blob/codex/agent-blocking-release/AgentBlocking/PRIVACY.md"
            ) {
              Link(String(localized: "Privacy Policy", table: "AgentFocus"), destination: url)
            }
          }
          .font(.footnote)
          .padding(8)
          .frame(maxWidth: .infinity)
          .background(.regularMaterial)
        }
        .onOpenURL { url in
          guard url.scheme == AgentFocusDevice.urlScheme else { return }
          setupError = !runtime.openSetup(url)
        }
        .alert(
          String(localized: "Agent setup unavailable", table: "AgentFocus"),
          isPresented: $setupError
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(runtime.message)
        }
        .task(id: scenePhase) {
          guard scenePhase == .active else { return }
          while !Task.isCancelled {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            alertsDisabled = settings.alertSetting != .enabled
            await runtime.sync()
            do { try await Task.sleep(for: .seconds(10)) } catch { break }
          }
        }
    }
  }
}
