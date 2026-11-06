import FamilyControls
import SwiftUI

/// The agent owns everyday controls; this screen keeps setup and a direct local exit.
struct AgentFocusView: View {
  @ObservedObject var runtime: AgentFocusRuntime
  @EnvironmentObject private var authorizer: RequestAuthorizer
  @Environment(\.locale) private var locale
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
  @State private var editSelection = FamilyActivitySelection()
  @State private var editModeID = ""
  @State private var showSelectionEditor = false
  @State private var selectionError = false
  @State private var step = SetupStep.connection

  private enum SetupStep: Int, CaseIterable {
    case connection, apps, limits
    var title: String {
      switch self {
      case .connection: String(localized: "MEET YOUR\nAGENT.", table: "AgentFocus")
      case .apps: String(localized: "YOUR APPS.\nYOUR CALL.", table: "AgentFocus")
      case .limits: String(localized: "SET THE\nBOUNDARY.", table: "AgentFocus")
      }
    }
    var description: String {
      switch self {
      case .connection:
        String(
          localized: "Paste the address and one-time code your agent gave you.", table: "AgentFocus"
        )
      case .apps:
        String(
          localized: "Choose which apps and websites your agent can pause.", table: "AgentFocus")
      case .limits:
        String(
          localized:
            "Sessions must fit inside these hours. Change the maximum separately with your agent.",
          table: "AgentFocus")
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
      .sheet(isPresented: $showSelectionEditor) {
        NavigationStack {
          FamilyActivityPicker(selection: $editSelection)
            .navigationTitle(String(localized: "Choose apps and websites", table: "AgentFocus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
              ToolbarItem(placement: .cancellationAction) {
                Button(String(localized: "Cancel", table: "AgentFocus")) {
                  showSelectionEditor = false
                }
              }
              ToolbarItem(placement: .confirmationAction) {
                Button(String(localized: "Save", table: "AgentFocus")) {
                  if runtime.saveSelection(editSelection, expectedModeID: editModeID) {
                    showSelectionEditor = false
                  } else {
                    selectionError = true
                  }
                }
                .disabled(
                  editSelection.applicationTokens.isEmpty
                    && editSelection.categoryTokens.isEmpty && editSelection.webDomainTokens.isEmpty
                )
                .accessibilityIdentifier("agent-focus-save-apps")
              }
            }
            .alert(
              String(localized: "App selection unavailable", table: "AgentFocus"),
              isPresented: $selectionError
            ) {
              Button("OK", role: .cancel) {}
            } message: {
              Text(
                String(
                  localized:
                    "End any active session and reopen the app selector. Check Screen Time access and choose at least one app, category or website.",
                  table: "AgentFocus"))
            }
        }
      }
      .alert(
        String(localized: "App selection unavailable", table: "AgentFocus"),
        isPresented: Binding(
          get: { selectionError && !showSelectionEditor },
          set: { selectionError = $0 })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text(
          String(
            localized:
              "End any active session and reopen the app selector. Check Screen Time access and choose at least one app, category or website.",
            table: "AgentFocus"))
      }
      .onAppear { loadInvitation() }
      .onChange(of: runtime.setupCode) { _, _ in loadInvitation() }
      .onChange(of: runtime.setupRelay) { _, _ in loadInvitation() }
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
        ? runtime.connectionPending
          ? String(localized: "Connection pending", table: "AgentFocus")
          : String(localized: "Agent paired", table: "AgentFocus")
        : String(localized: "One-time setup", table: "AgentFocus"),
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
        headline(
          uncertain
            ? String(localized: "CHECKING\nSTATUS.", table: "AgentFocus")
            : focusing
              ? String(localized: "FOCUS\nIS ON.", table: "AgentFocus")
              : String(localized: "MAKE\nROOM.", table: "AgentFocus")
        )
        .accessibilityIdentifier("agent-focus-heading")
        Text(
          uncertain
            ? String(
              localized:
                "Your session status is being checked. Emergency Unlock is available below.",
              table: "AgentFocus")
            : focusing
              ? String(
                localized: "A boundary you chose.\nSpace to get it done.", table: "AgentFocus")
              : String(
                localized: "Your agent is ready.\nBegin your next session in chat.",
                table: "AgentFocus")
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
        Text(
          uncertain
            ? String(localized: "PHONE STATUS", table: "AgentFocus")
            : focusing
              ? String(localized: "IN PROGRESS", table: "AgentFocus")
              : String(localized: "YOUR NEXT CHAPTER", table: "AgentFocus")
        )
        .font(.caption.monospaced()).tracking(1.5).foregroundStyle(Palette.muted)
        Text(
          uncertain
            ? applying
              ? String(localized: "Applying your request.", table: "AgentFocus")
              : String(localized: "Waiting for a current status.", table: "AgentFocus")
            : focusing
              ? String(localized: "Space for what matters.", table: "AgentFocus")
              : String(localized: "Start with your agent.", table: "AgentFocus")
        )
        .font(.title3.weight(.semibold))
        if let end {
          if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
              Text(String(localized: "Scheduled end", table: "AgentFocus"))
              Text(end, format: .dateTime.hour().minute()).monospacedDigit()
            }
            .font(.subheadline).foregroundStyle(Palette.muted)
          } else {
            LabeledContent(String(localized: "Scheduled end", table: "AgentFocus")) {
              Text(end, format: .dateTime.hour().minute()).monospacedDigit()
            }
            .font(.subheadline).foregroundStyle(Palette.muted)
          }
        } else if !uncertain {
          Text(String(localized: "No active session.", table: "AgentFocus")).font(.subheadline)
            .foregroundStyle(Palette.muted)
        }
        if !uncertain && !focusing {
          Button {
            do {
              let saved = try runtime.editableSelection()
              editSelection = saved.selection
              editModeID = saved.modeID
              selectionError = false
              showSelectionEditor = true
            } catch {
              selectionError = true
            }
          } label: {
            Label(
              String(localized: "Choose apps and websites", table: "AgentFocus"),
              systemImage: "apps.iphone"
            )
            .frame(minHeight: 44)
          }
          .accessibilityIdentifier("agent-focus-edit-apps")
        }
        Rectangle().fill(Palette.rule).frame(height: 1).accessibilityHidden(true)
        emergencyButton
        Text(String(localized: "Ends this session. Your agent stays paired.", table: "AgentFocus"))
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
        Text(String(localized: "Step \(step.rawValue + 1) of 3", table: "AgentFocus")).font(
          .caption)
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
              Text(
                approving
                  ? String(localized: "Connecting…", table: "AgentFocus")
                  : String(localized: "Approve and connect", table: "AgentFocus"))
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
              Text(String(localized: "Continue", table: "AgentFocus"))
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
            Label(String(localized: "Back", table: "AgentFocus"), systemImage: "arrow.left")
          }
          .font(.subheadline).disabled(approving)
          .accessibilityIdentifier("agent-focus-back")
        }
        runtimeMessage
      }
      .padding(24).background(Palette.paper, in: RoundedRectangle(cornerRadius: 22))
      Text(
        String(localized: "One-time setup. Your agent handles the everyday.", table: "AgentFocus")
      )
      .font(.footnote).lineSpacing(3)
      emergencyButton
      Text(String(localized: "Emergency Unlock is always available here.", table: "AgentFocus"))
        .font(.footnote)
    }
    .padding(.horizontal, 26).padding(.bottom, 36)
  }

  private var connectionFields: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(String(localized: "Relay address", table: "AgentFocus")).font(
        .subheadline.weight(.medium))
      TextField("https://…", text: $relay)
        .keyboardType(.URL).textContentType(.URL)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .submitLabel(.next).accessibilityIdentifier("agent-focus-relay")
      Divider().overlay(Palette.rule)
      Text(String(localized: "One-time pairing code", table: "AgentFocus")).font(
        .subheadline.weight(.medium)
      ).padding(.top, 8)
      SecureField(String(localized: "Code from your agent", table: "AgentFocus"), text: $code)
        .textInputAutocapitalization(.never).autocorrectionDisabled()
        .submitLabel(.done).accessibilityIdentifier("agent-focus-code")
      Divider().overlay(Palette.rule)
      Text(String(localized: "Only connect to an agent you asked to pair.", table: "AgentFocus"))
        .font(.footnote).foregroundStyle(Palette.muted).padding(.top, 8)
    }
  }

  private var appFields: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(String(localized: "Screen Time access", table: "AgentFocus")).font(
        .subheadline.weight(.medium))
      Button {
        authorizer.requestAuthorization()
      } label: {
        Label(
          authorizer.isAuthorized
            ? String(localized: "Screen Time authorized", table: "AgentFocus")
            : String(localized: "Allow Screen Time access", table: "AgentFocus"),
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
          Text(String(localized: "Choose apps and websites", table: "AgentFocus"))
          Spacer()
          Image(systemName: "arrow.up.right")
        }
        .frame(minHeight: 44)
      }
      .accessibilityIdentifier("agent-focus-choose-apps")
      Text(
        String(
          localized:
            "\(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, \(selection.webDomainTokens.count) websites selected",
          table: "AgentFocus")
      )
      .font(.footnote).foregroundStyle(Palette.muted)
      if authorizer.isAuthorized && !hasSelection {
        Text(
          String(
            localized: "Choose at least one app, category or website to continue.",
            table: "AgentFocus")
        )
        .font(.footnote).foregroundStyle(Palette.muted)
      }
    }
    .font(.subheadline)
  }

  private var limitFields: some View {
    VStack(alignment: .leading, spacing: 20) {
      Stepper(
        String(localized: "Maximum session: \(maximumMinutes) minutes", table: "AgentFocus"),
        value: $maximumMinutes,
        in: 15...1440, step: 15)
      Divider().overlay(Palette.rule)
      Stepper(
        String(localized: "Allowed from: \(time(startMinute))", table: "AgentFocus"),
        value: $startMinute,
        in: 0...1425, step: 15)
      Stepper(
        String(localized: "Allowed until: \(time(endMinute))", table: "AgentFocus"),
        value: $endMinute,
        in: 15...1440, step: 15)
      Text(
        String(
          localized:
            "Hours use \(TimeZone.current.identifier). Sessions must finish within these hours.",
          table: "AgentFocus")
      )
      .font(.footnote).foregroundStyle(Palette.muted)
      if startMinute >= endMinute {
        Text(
          String(localized: "Choose a closing time after the opening time.", table: "AgentFocus")
        )
        .font(.footnote).foregroundStyle(Palette.ink)
      }
      if !authorizer.isAuthorized {
        Text(
          String(
            localized: "Screen Time access is required. Go back to allow access.",
            table: "AgentFocus")
        )
        .font(.footnote).foregroundStyle(Palette.ink)
      }
      Text(
        String(
          localized:
            "Emergency Unlock ends the current session. Your agent can request another within your approved limits.",
          table: "AgentFocus")
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
          Text(String(localized: "Emergency Unlock", table: "AgentFocus")).font(
            .footnote.weight(.semibold)
          )
          .fixedSize(horizontal: false, vertical: true)
        }
      } else {
        HStack(spacing: 12) {
          Image(systemName: "lock.open")
          Text(String(localized: "Emergency Unlock", table: "AgentFocus")).fontWeight(.medium)
          Spacer(minLength: 4)
          Image(systemName: "arrow.up.right")
        }
      }
    }
    .buttonStyle(BoldPrimaryStyle())
    .accessibilityIdentifier("agent-focus-emergency-unlock")
  }

  private func headline(_ text: String, isSetup: Bool = false) -> some View {
    Text(text)
      .font(
        dynamicTypeSize.isAccessibilitySize
          ? .system(.largeTitle, weight: .black)
          : .system(size: isSetup ? setupHeadlineSize : headlineSize, weight: .black)
      )
      .tracking(locale.language.languageCode?.identifier == "zh" ? 0 : -3)
      .lineSpacing(locale.language.languageCode?.identifier == "zh" ? 4 : -4)
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
