import FamilyControls
import SwiftUI

/// The agent owns everyday controls; this screen keeps setup and a direct local exit.
struct AgentFocusView: View {
  @ObservedObject var runtime: AgentFocusRuntime
  @EnvironmentObject private var authorizer: RequestAuthorizer
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @ScaledMetric(relativeTo: .largeTitle) private var headlineSize = 64
  @ScaledMetric(relativeTo: .largeTitle) private var setupHeadlineSize = 52
  @State private var selection = FamilyActivitySelection()
  @State private var showPicker = false
  @State private var maximumMinutes = 45
  @State private var startMinute = 0
  @State private var endMinute = 1440
  @State private var relay = ""
  @State private var code = ""
  @State private var approving = false
  @State private var step = SetupStep.connection

  private enum SetupStep: Int, CaseIterable {
    case connection, apps, limits
    var title: LocalizedStringKey {
      switch self {
      case .connection: "MEET YOUR\nAGENT."
      case .apps: "YOUR APPS.\nYOUR CALL."
      case .limits: "SET THE\nBOUNDARY."
      }
    }
    var description: LocalizedStringKey {
      switch self {
      case .connection: "Paste the address and one-time code your agent gave you."
      case .apps: "Choose which apps and websites your agent can pause."
      case .limits:
        "Sessions must fit inside these hours. Change the maximum separately with your agent."
      }
    }
  }

  private enum Palette {
    static let orange = Color(red: 242 / 255, green: 91 / 255, blue: 54 / 255)
    static let ink = Color(red: 45 / 255, green: 40 / 255, blue: 31 / 255)
    static let paper = Color(red: 1, green: 245 / 255, blue: 230 / 255)
    static let muted = Color(red: 107 / 255, green: 96 / 255, blue: 82 / 255)
    static let rule = Color(red: 220 / 255, green: 206 / 255, blue: 185 / 255)
  }

  var body: some View {
    NavigationStack {
      GeometryReader { geometry in
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            brand.padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 28)
            if runtime.configured {
              TimelineView(.periodic(from: .now, by: 1)) { context in
                home(at: context.date, minimumHeight: max(0, geometry.size.height - 76))
              }
            } else {
              setup
            }
          }
          .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(alignment: .bottom) {
          if runtime.configured {
            Palette.paper.frame(height: geometry.safeAreaInsets.bottom)
              .offset(y: geometry.safeAreaInsets.bottom)
          }
        }
        .background(Palette.orange.ignoresSafeArea())
      }
      .foregroundStyle(Palette.ink)
      .tint(Palette.ink)
      .toolbar(.hidden, for: .navigationBar)
      .familyActivityPicker(isPresented: $showPicker, selection: $selection)
      .onAppear { loadInvitation() }
      .onChange(of: runtime.setupCode) { _, _ in loadInvitation() }
      .onChange(of: runtime.setupRelay) { _, _ in loadInvitation() }
    }
    .sheet(item: $runtime.appReview) { review in
      AgentAppGroupsView(runtime: runtime, initialGroupID: review.groupID)
    }
    .preferredColorScheme(.light)
  }

  private var brand: some View {
    ViewThatFits(in: .horizontal) {
      HStack {
        wordmark
        Spacer(minLength: 16)
        connectionLabel
      }
      VStack(alignment: .leading, spacing: 12) {
        wordmark
        connectionLabel
      }
    }
  }

  private var wordmark: some View {
    HStack(alignment: .firstTextBaseline, spacing: 7) {
      Text("do /").font(.system(.title2, design: .rounded, weight: .heavy))
      Text("focus").font(.subheadline)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("DO Focus")
    .accessibilityIdentifier("agent-focus-brand")
  }

  private var connectionLabel: some View {
    Label(
      runtime.configured
        ? runtime.connectionPending ? "Connection pending" : "Agent paired"
        : "One-time setup",
      systemImage: runtime.connectionPending ? "wifi.exclamationmark" : "circle.fill"
    )
    .font(.caption)
  }

  private func home(at now: Date, minimumHeight: CGFloat) -> some View {
    let status = runtime.focusStatus
    let end = status?.session.map { Date(timeIntervalSince1970: $0.endAt / 1000) }
    let applying = status?.applicationPending == true
    let uncertain = status == nil || applying || (end.map { $0 <= now } ?? false)
    let focusing = end != nil && !uncertain
    return VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 24) {
        headline(uncertain ? "CHECKING\nSTATUS." : focusing ? "FOCUS\nIS ON." : "MAKE\nROOM.")
          .accessibilityIdentifier("agent-focus-heading")
        Text(
          uncertain
            ? "Your session status is being checked. Emergency Unlock is available below."
            : focusing
              ? "A boundary you chose.\nSpace to get it done."
              : "Your agent is ready.\nBegin your next session in chat."
        )
        .font(.subheadline).lineSpacing(4)
        .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.horizontal, 26).padding(.top, 14).padding(.bottom, 54)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(alignment: .trailing) {
        Circle().trim(from: 0.15, to: 0.88)
          .stroke(Palette.paper.opacity(0.5), lineWidth: 26)
          .frame(width: 150, height: 150).rotationEffect(.degrees(-30))
          .offset(x: 82, y: 75).accessibilityHidden(true)
      }
      .clipped()
      Spacer(minLength: 24)
      VStack(alignment: .leading, spacing: 18) {
        Text(uncertain ? "PHONE STATUS" : focusing ? "IN PROGRESS" : "YOUR NEXT CHAPTER")
          .font(.caption.monospaced()).tracking(1.5).foregroundStyle(Palette.muted)
        Text(
          uncertain
            ? applying ? "Applying your request." : "Waiting for a current status."
            : focusing ? "Space for what matters." : "Start with your agent."
        )
        .font(.title3.weight(.semibold))
        if let end {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
              Text("Scheduled end")
              Text(end, format: .dateTime.hour().minute()).monospacedDigit()
            }
            .font(.subheadline).foregroundStyle(Palette.muted)
          } else {
            LabeledContent("Scheduled end") {
              Text(end, format: .dateTime.hour().minute()).monospacedDigit()
            }
            .font(.subheadline).foregroundStyle(Palette.muted)
          }
        } else if !uncertain {
          Text("No active session.").font(.subheadline).foregroundStyle(Palette.muted)
        }
        Rectangle().fill(Palette.rule).frame(height: 1).accessibilityHidden(true)
        Button {
          runtime.presentAppReview()
        } label: {
          Label(
            focusing ? "Review this session’s apps" : "Review app groups",
            systemImage: "square.grid.2x2"
          )
          .frame(minHeight: 44)
        }
        .accessibilityIdentifier("agent-focus-review-apps")
        emergencyButton
        Text("Ends this session. Your agent stays paired.")
          .font(.footnote).foregroundStyle(Palette.muted)
        runtimeMessage
      }
      .padding(26).padding(.bottom, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        Palette.paper, in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
    }
    .frame(minHeight: minimumHeight, alignment: .topLeading)
  }

  private var setup: some View {
    VStack(alignment: .leading, spacing: 24) {
      HStack(spacing: 5) {
        ForEach(SetupStep.allCases, id: \.rawValue) { item in
          Rectangle().fill(item.rawValue <= step.rawValue ? Palette.ink : Palette.ink.opacity(0.25))
            .frame(width: 30, height: 3)
        }
        Spacer()
        Text("Step \(step.rawValue + 1) of 3").font(.caption)
      }.accessibilityElement(children: .combine)
      headline(step.title, isSetup: true)
      Text(step.description).font(.subheadline).lineSpacing(4)
      VStack(alignment: .leading, spacing: 22) {
        switch step {
        case .connection: connectionFields
        case .apps: appFields
        case .limits: limitFields
        }
        if step == .limits {
          Button(action: approve) {
            HStack {
              Text(approving ? "Connecting…" : "Approve and connect")
              Spacer()
              if approving {
                ProgressView().tint(Palette.paper)
              } else {
                Image(systemName: "arrow.right")
              }
            }
          }
          .buttonStyle(BoldPrimaryStyle())
          .disabled(approving || !canApprove)
          .accessibilityIdentifier("agent-focus-connect")
        } else {
          Button {
            if let next = SetupStep(rawValue: step.rawValue + 1) { step = next }
          } label: {
            HStack {
              Text("Continue")
              Spacer()
              Image(systemName: "arrow.right")
            }
          }
          .buttonStyle(BoldPrimaryStyle())
          .disabled(!canContinue)
          .accessibilityIdentifier("agent-focus-continue")
        }
        if step != .connection {
          Button {
            if let previous = SetupStep(rawValue: step.rawValue - 1) { step = previous }
          } label: {
            Label("Back", systemImage: "arrow.left")
          }
          .font(.subheadline).disabled(approving)
          .accessibilityIdentifier("agent-focus-back")
        }
        runtimeMessage
      }
      .padding(24).background(Palette.paper, in: RoundedRectangle(cornerRadius: 22))
      Text("One-time setup. Your agent handles the everyday.")
        .font(.footnote).lineSpacing(3)
      emergencyButton
      Text("Emergency Unlock is always available here.").font(.footnote)
    }
    .padding(.horizontal, 26).padding(.bottom, 36)
  }

  private var connectionFields: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Relay address").font(.subheadline.weight(.medium))
      TextField("https://…", text: $relay)
        .keyboardType(.URL).textContentType(.URL)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .submitLabel(.next).accessibilityIdentifier("agent-focus-relay")
      Divider().overlay(Palette.rule)
      Text("One-time pairing code").font(.subheadline.weight(.medium)).padding(.top, 8)
      SecureField("Code from your agent", text: $code)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .submitLabel(.done).accessibilityIdentifier("agent-focus-code")
      Divider().overlay(Palette.rule)
      Text("Only connect to an agent you asked to pair.")
        .font(.footnote).foregroundStyle(Palette.muted).padding(.top, 8)
    }
  }

  private var appFields: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text("Screen Time access").font(.subheadline.weight(.medium))
      Button {
        authorizer.requestAuthorization()
      } label: {
        Label(
          authorizer.isAuthorized ? "Screen Time authorized" : "Allow Screen Time access",
          systemImage: authorizer.isAuthorized ? "checkmark.circle" : "lock.shield"
        )
        .frame(minHeight: 44, alignment: .leading)
      }
      .disabled(authorizer.isAuthorized)
      .accessibilityIdentifier("agent-focus-authorize")
      Divider().overlay(Palette.rule)
      Button {
        showPicker = true
      } label: {
        HStack {
          Text("Choose apps and websites")
          Spacer()
          Image(systemName: "arrow.up.right")
        }
        .frame(minHeight: 44)
      }
      .accessibilityIdentifier("agent-focus-choose-apps")
      Text(
        "\(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, \(selection.webDomainTokens.count) websites selected"
      )
      .font(.footnote).foregroundStyle(Palette.muted)
      if authorizer.isAuthorized && !hasSelection {
        Text("Choose at least one app, category or website to continue.")
          .font(.footnote).foregroundStyle(Palette.muted)
      }
    }
    .font(.subheadline)
  }

  private var limitFields: some View {
    VStack(alignment: .leading, spacing: 20) {
      Stepper(
        "Maximum session: \(maximumMinutes) minutes", value: $maximumMinutes,
        in: 15...1440, step: 15)
      Divider().overlay(Palette.rule)
      Stepper(
        "Allowed from: \(time(startMinute))", value: $startMinute,
        in: 0...1425, step: 15)
      Stepper(
        "Allowed until: \(time(endMinute))", value: $endMinute,
        in: 15...1440, step: 15)
      Text("Hours use \(TimeZone.current.identifier). Sessions must finish within these hours.")
        .font(.footnote).foregroundStyle(Palette.muted)
      if startMinute >= endMinute {
        Text("Choose a closing time after the opening time.")
          .font(.footnote).foregroundStyle(Palette.ink)
      }
      if !authorizer.isAuthorized {
        Text("Screen Time access is required. Go back to allow access.")
          .font(.footnote).foregroundStyle(Palette.ink)
      }
      Text(
        "Emergency Unlock ends the current session. Your agent can request another within your approved limits."
      )
      .font(.footnote).foregroundStyle(Palette.muted)
    }
    .font(.subheadline)
  }

  @ViewBuilder private var runtimeMessage: some View {
    if !runtime.message.isEmpty {
      Text(runtime.message).font(.footnote).lineSpacing(3).foregroundStyle(Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("agent-focus-message")
    }
  }

  private var emergencyButton: some View {
    Button(action: runtime.emergencyUnlock) {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 10) {
          Image(systemName: "lock.open").accessibilityHidden(true)
          Text("Emergency Unlock").font(.footnote.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(spacing: 12) {
          Image(systemName: "lock.open")
          Text("Emergency Unlock").fontWeight(.medium)
          Spacer(minLength: 4)
          Image(systemName: "arrow.up.right")
        }
      }
    }
    .buttonStyle(BoldPrimaryStyle())
    .accessibilityIdentifier("agent-focus-emergency-unlock")
  }

  private func headline(_ text: LocalizedStringKey, isSetup: Bool = false) -> some View {
    Text(text)
      .font(
        dynamicTypeSize.isAccessibilitySize
          ? .system(.largeTitle, weight: .black)
          : .system(size: isSetup ? setupHeadlineSize : headlineSize, weight: .black)
      )
      .tracking(-3).lineSpacing(-4)
      .fixedSize(horizontal: false, vertical: true)
      .accessibilityAddTraits(.isHeader)
  }

  private var hasSelection: Bool {
    !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
      || !selection.webDomainTokens.isEmpty
  }
  private var validInvitation: Bool {
    guard let parts = URLComponents(string: relay.trimmingCharacters(in: .whitespacesAndNewlines))
    else { return false }
    return parts.scheme?.lowercased() == "https" && parts.host?.isEmpty == false
      && parts.user == nil && parts.password == nil && parts.query == nil
      && parts.fragment == nil && (parts.path.isEmpty || parts.path == "/")
      && !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  private var canContinue: Bool {
    step == .connection ? validInvitation : authorizer.isAuthorized && hasSelection
  }
  private var canApprove: Bool {
    validInvitation && authorizer.isAuthorized && hasSelection && startMinute < endMinute
  }
  private func loadInvitation() {
    relay = runtime.setupRelay
    code = runtime.setupCode
    step = .connection
  }
  private func approve() {
    guard canApprove, !approving else { return }
    approving = true
    Task {
      await runtime.approve(
        relay: relay.trimmingCharacters(in: .whitespacesAndNewlines),
        code: code.trimmingCharacters(in: .whitespacesAndNewlines), selection: selection,
        maximumMinutes: maximumMinutes, startMinute: startMinute, endMinute: endMinute)
      approving = false
    }
  }
  private func time(_ minutes: Int) -> String {
    String(format: "%02d:%02d", minutes / 60, minutes % 60)
  }
}

private struct BoldPrimaryStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.subheadline)
      .foregroundStyle(Color(red: 1, green: 245 / 255, blue: 230 / 255))
      .padding(.horizontal, 18).padding(.vertical, 17)
      .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
      .background(
        Color(red: 45 / 255, green: 40 / 255, blue: 31 / 255), in: RoundedRectangle(cornerRadius: 9)
      )
      .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.8 : 1)
  }
}

/// Selection labels are rendered by iOS on this device, never exported to chat.
private struct AgentAppGroupsView: View {
  @ObservedObject var runtime: AgentFocusRuntime
  let initialGroupID: String?
  @Environment(\.dismiss) private var dismiss
  @State private var groupID: String?
  @State private var name = ""
  @State private var selection = FamilyActivitySelection()
  @State private var picker = false
  @State private var saving = false
  @State private var error = ""
  private var active: Bool {
    runtime.focusStatus?.session != nil || runtime.focusStatus?.applicationPending == true
  }
  private var known: Bool { runtime.focusStatus != nil }
  private var hasSelection: Bool {
    !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
      || !selection.webDomainTokens.isEmpty
  }

  var body: some View {
    NavigationStack {
      Form {
        overviewSection
        appSelectionSection
        if !active {
          Section {
            TextField("Group name", text: $name).disabled(!known || saving)
            Text(
              "Saving shares the group name you type with your paired agent and relay. Actual app names, icons and selection tokens stay on this iPhone. Use a generic name such as Deep Work."
            )
            .font(.footnote)
            Button(saving ? "Saving…" : "Save group and share name") {
              saving = true
              error = ""
              Task {
                do {
                  groupID = try await runtime.saveAppGroup(
                    id: groupID, name: name, selection: selection)
                  error =
                    runtime.connectionPending
                    ? "Saved on this phone. Reopen DO Card online to sync, then refresh groups in chat."
                    : "Saved. Return to chat and refresh groups before starting."
                } catch {
                  self.error =
                    "Could not save. Check the name, selection and that no session is active."
                }
                saving = false
              }
            }.disabled(
              !known || saving || !hasSelection
                || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || name.utf16.count > 40)
          } header: {
            Text("Chat name")
          }
        } else {
          Text(
            "App groups cannot change during a session. End this session before editing future groups."
          )
        }
        if !error.isEmpty { Section { Text(error) } }
        Section { Button("Emergency Unlock", action: runtime.emergencyUnlock) }
      }
      .navigationTitle("Session apps")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Emergency Unlock", action: runtime.emergencyUnlock)
        }
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .familyActivityPicker(isPresented: $picker, selection: $selection)
      .onAppear { load(runtime.focusStatus?.activeAppGroupID ?? initialGroupID ?? "default") }
      .onChange(of: runtime.focusStatus?.activeAppGroupID) { _, id in
        if let id { load(id) }
      }
    }
  }

  private var overviewSection: some View {
    Section {
      if let status = runtime.focusStatus {
        if status.applicationPending {
          Text(
            "Applying the session. These are the requested apps; blocking is not yet confirmed."
          )
        } else if let session = status.session {
          Text(
            Date().timeIntervalSince1970 * 1000 < session.endAt
              ? "These are the apps selected for this session."
              : "The session deadline has passed. Checking release status.")
        } else {
          Text("No active session. Choose a saved group to review or edit.")
        }
      } else {
        Text("Status unavailable. Editing is disabled. Emergency Unlock is still available.")
      }
      if !active {
        ForEach(runtime.focusStatus?.appGroups ?? []) { group in
          Button {
            load(group.id)
          } label: {
            HStack {
              Text(group.name)
              Spacer()
              if groupID == group.id { Image(systemName: "checkmark") }
            }
          }.disabled(!known || saving)
        }
        Button("Create app group") {
          groupID = nil
          name = ""
          selection = FamilyActivitySelection()
          error = ""
        }.disabled(!known || saving || (runtime.focusStatus?.appGroups.count ?? 8) >= 8)
      }
    } header: {
      Text(active ? "This session" : "Saved groups")
    }
  }

  private var appSelectionSection: some View {
    Section {
      ForEach(Array(selection.applicationTokens), id: \.self) { Label($0) }
      ForEach(Array(selection.categoryTokens), id: \.self) { Label($0) }
      ForEach(Array(selection.webDomainTokens), id: \.self) { Label($0) }
      if !hasSelection { Text("No selection loaded.") }
      if !active {
        Button("Choose apps and websites") { picker = true }.disabled(!known || saving)
      }
    } header: {
      Text("Apps, categories and websites")
    } footer: {
      Text(
        "Names and icons are displayed privately by iOS. Selecting a category can include more apps than those listed individually."
      )
    }
  }

  private func load(_ id: String) {
    do {
      selection = try runtime.savedAppSelection(groupID: id)
      groupID = id
      name = runtime.focusStatus?.appGroups.first(where: { $0.id == id })?.name ?? "Saved apps"
      error = ""
    } catch {
      selection = FamilyActivitySelection()
      groupID = nil
      name = ""
      self.error = "This group is unavailable. Refresh the phone status and try again."
    }
  }
}
