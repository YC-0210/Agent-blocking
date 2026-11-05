import FamilyControls
import SwiftUI

struct AgentFocusView: View {
  @ObservedObject var runtime: AgentFocusRuntime
  @EnvironmentObject private var subscriptionManager: SubscriptionManager
  @EnvironmentObject private var authorizer: RequestAuthorizer
  @State private var selection = FamilyActivitySelection()
  @State private var showPicker = false
  @State private var maximumMinutes = 45
  @State private var startMinute = 0
  @State private var endMinute = 1440
  @State private var relay = ""
  @State private var code = ""
  @State private var approving = false
  @State private var showBilling = false

  var body: some View {
    NavigationStack {
      Group {
        if runtime.configured {
          VStack(spacing: 28) {
            Spacer()
            Image(systemName: "sparkles").font(.system(size: 48)).foregroundStyle(
              ThemeManager.accentColor)
            Text("Manage focus with your agent.").font(.title2)
            Text(runtime.message).font(.footnote).foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
            emergencyButton
            Spacer()
          }.padding(28)
        } else {
          Form {
            Section("Connect your agent") {
              TextField("HTTPS relay address", text: $relay)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
              SecureField("One-time pairing code", text: $code)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
              Text(
                "Use the address and code provided by Codex. Only approve a connection you requested."
              )
              .font(.footnote)
            }
            Section("Approve focus limits") {
              Button(
                authorizer.isAuthorized ? "Screen Time authorized" : "Allow Screen Time access"
              ) {
                authorizer.requestAuthorization()
              }.disabled(authorizer.isAuthorized)
              Button("Choose apps and websites") { showPicker = true }
              Text(
                "\(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, \(selection.webDomainTokens.count) websites selected"
              )
              .font(.footnote)
              Stepper(
                "Maximum session: \(maximumMinutes) minutes", value: $maximumMinutes, in: 15...1440,
                step: 15)
              Stepper(
                "Allowed from: \(time(startMinute))", value: $startMinute, in: 0...1425, step: 15)
              Stepper(
                "Allowed until: \(time(endMinute))", value: $endMinute, in: 15...1440, step: 15)
              Text(
                "Hours use \(TimeZone.current.identifier). Sessions must finish within these hours. Your agent cannot increase these limits."
              )
              .font(.footnote)
              Text(
                "Emergency Unlock ends this session. Your connected agent can start another session within these limits."
              )
              .font(.footnote)
              Button(approving ? "Connecting…" : "Approve and connect") {
                approving = true
                Task {
                  await runtime.approve(
                    relay: relay, code: code, selection: selection,
                    maximumMinutes: maximumMinutes, startMinute: startMinute, endMinute: endMinute)
                  approving = false
                }
              }.disabled(
                approving || !authorizer.isAuthorized || startMinute >= endMinute
                  || !subscriptionManager.isPremium)
              if !subscriptionManager.isPremium {
                Text(
                  "An active DO Card subscription is required to start agent focus. Emergency Unlock is always available."
                )
                Button("Subscription options") { showBilling = true }
              }
            }
            if !runtime.message.isEmpty { Text(runtime.message).foregroundStyle(.secondary) }
            Section { emergencyButton }
          }
          .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        }
      }
      .navigationTitle("Agent Focus")
      .sheet(isPresented: $showBilling) { PaywallView() }
      .onAppear {
        relay = runtime.setupRelay
        code = runtime.setupCode
      }
      .onChange(of: runtime.setupCode) { _, value in
        relay = runtime.setupRelay
        code = value
      }
    }
  }

  private var emergencyButton: some View {
    Button("Emergency Unlock", role: .destructive) { runtime.emergencyUnlock() }
      .buttonStyle(.borderedProminent)
      .accessibilityIdentifier("agent-focus-emergency-unlock")
  }
  private func time(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }
}
