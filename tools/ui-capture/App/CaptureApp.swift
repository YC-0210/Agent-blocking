import Combine
import FamilyControls
import SwiftUI

// Screenshot-only fixtures. No native effects, credentials or networking.
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
  }
  @Published var focusStatus: Status?
  @Published var connectionPending = false
  init() {
    let args = ProcessInfo.processInfo.arguments
    setupRelay = args.contains("invitation") ? "https://focus.example.com" : ""
    setupCode = args.contains("invitation") ? "screenshot-code" : ""
    configured =
      args.contains("connected") || args.contains("pending") || args.contains("ended")
      || args.contains("unlock-failed")
    if args.contains("pending") {
      message =
        "Waiting to sync with your agent. Emergency Unlock works here."
    } else if args.contains("ended") {
      message = "Agent session ended. Your agent remains connected."
    } else if args.contains("unlock-failed") {
      message = "Agent shields cleared. Could not save the session ending; reopen DO Card to retry."
    } else if args.contains("push-failed") {
      configured = true
      message = "Push registration failed. Open DO Card to receive pending commands."
    } else if args.contains("setup-error") {
      message =
        "Setup failed: The operation couldn’t be completed. Check access, app selection, relay and pairing code."
    } else {
      message = configured ? "Connected. Return to your agent to manage focus." : ""
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
    message = "Agent session ended. Your agent remains connected."
  }
}
@main struct CaptureApp: App {
  @StateObject private var runtime = AgentFocusRuntime()
  @StateObject private var authorizer = RequestAuthorizer()
  @State private var showSetupAlert = ProcessInfo.processInfo.arguments.contains("setup-alert")
  var body: some Scene {
    WindowGroup {
      AgentFocusView(runtime: runtime).environmentObject(authorizer)
        .alert("Agent setup unavailable", isPresented: $showSetupAlert) {
          Button("OK", role: .cancel) {}
        } message: {
          Text("End existing sessions and disable scheduled modes before agent setup.")
        }
        .preferredColorScheme(.light)
    }
  }
}
