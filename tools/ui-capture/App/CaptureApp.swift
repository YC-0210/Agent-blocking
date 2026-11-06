import Combine
import FamilyControls
import SwiftUI

// Screenshot-only fixtures. No native effects, credentials or networking.
enum Entitlements { static let premiumAppLimit = 50 }
enum ThemeManager { static let accentColor = Color(red: 1, green: 107.0 / 255, blue: 53.0 / 255) }
@MainActor final class RequestAuthorizer: ObservableObject {
  @Published var isAuthorized = ProcessInfo.processInfo.arguments.contains("authorized")
  func requestAuthorization() { isAuthorized = true }
}
@MainActor final class AgentFocusRuntime: ObservableObject {
  @Published var configured: Bool
  @Published var message = ""
  @Published var setupRelay = ""
  @Published var setupCode = ""
  struct Status {
    struct Session { let endAt: Double }
    var session: Session?
    var applicationPending = false
    var appGroups: [AgentAppGroup] = []
    var activeAppGroupID: String? = nil
  }
  @Published var focusStatus: Status?
  @Published var connectionPending = false
  struct AppReview: Identifiable {
    let id = UUID()
    let groupID: String?
  }
  @Published var appReview: AppReview?
  func presentAppReview(groupID: String? = nil) { appReview = AppReview(groupID: groupID) }
  func savedAppSelection(groupID: String) throws -> FamilyActivitySelection {
    FamilyActivitySelection()
  }
  func editableSelection() throws -> (
    selection: FamilyActivitySelection, modeID: String, pairingID: String
  ) {
    (FamilyActivitySelection(), "fixture-mode", "fixture")
  }
  func saveSelection(
    _ selection: FamilyActivitySelection, pairingID: String, expectedModeID: String
  ) async -> Bool { true }
  init() {
    let args = ProcessInfo.processInfo.arguments
    setupRelay = args.contains("invitation") ? "https://focus.example.com" : ""
    setupCode = args.contains("invitation") ? "screenshot-code" : ""
    configured =
      args.contains("connected") || args.contains("pending") || args.contains("ended")
      || args.contains("unlock-failed")
    if args.contains("pending") {
      message =
        String(
          localized: "Waiting to sync with your agent. Emergency Unlock works here.",
          table: "AgentFocus")
    } else if args.contains("ended") {
      message = String(
        localized: "Agent session ended. Your agent remains connected.", table: "AgentFocus")
    } else if args.contains("unlock-failed") {
      message = String(
        localized:
          "Agent shields cleared. Could not save the session ending; reopen DO Card to retry.",
        table: "AgentFocus")
    } else if args.contains("push-failed") {
      configured = true
      message = String(
        localized: "Push registration failed. Open DO Card to receive pending commands.",
        table: "AgentFocus")
    } else if args.contains("setup-error") {
      message =
        "Setup failed: The operation couldn’t be completed. Check access, app selection, relay and pairing code."
    } else {
      message =
        configured
        ? String(localized: "Connected. Return to your agent to manage focus.", table: "AgentFocus")
        : ""
    }
    if configured {
      focusStatus = Status(
        session: args.contains("connected") || args.contains("pending")
          ? Status.Session(endAt: Date().addingTimeInterval(1200).timeIntervalSince1970 * 1000)
          : nil)
    }
    if args.contains("unknown") {
      configured = true
      focusStatus = nil
    }
    if args.contains("applying") {
      configured = true
      focusStatus = Status(
        session: .init(endAt: Date().addingTimeInterval(1200).timeIntervalSince1970 * 1000),
        applicationPending: true)
    }
    connectionPending = args.contains("pending")
  }
  func approve(
    relay: String, code: String, selection: FamilyActivitySelection, maximumMinutes: Int,
    startMinute: Int, endMinute: Int
  ) async {}
  func emergencyUnlock() {
    focusStatus = Status(session: nil)
    message = String(
      localized: "Agent session ended. Your agent remains connected.", table: "AgentFocus")
  }
}
@main struct CaptureApp: App {
  @StateObject private var runtime = AgentFocusRuntime()
  @StateObject private var authorizer = RequestAuthorizer()
  @State private var showSetupAlert = ProcessInfo.processInfo.arguments.contains("setup-alert")
  var body: some Scene {
    WindowGroup {
      AgentFocusView(runtime: runtime).environmentObject(authorizer)
        .alert(
          String(localized: "Agent setup unavailable", table: "AgentFocus"),
          isPresented: $showSetupAlert
        ) {
          Button("OK", role: .cancel) {}
        } message: {
          Text(
            String(
              localized: "End existing sessions and disable scheduled modes before agent setup.",
              table: "AgentFocus"))
        }
        .preferredColorScheme(.light)
    }
  }
}
