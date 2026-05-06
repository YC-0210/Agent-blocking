import Foundation

/// Snapshot of a just-ended session, captured at end-time and handed to the share prompt UI.
/// Decoupled from the SwiftData @Model so the UI does not depend on a live managed object
/// (avoids context lifecycle issues if the session is later refetched or context invalidates).
struct ShareableSession: Identifiable, Equatable {
  let id = UUID()
  let profileName: String
  let duration: TimeInterval
}
