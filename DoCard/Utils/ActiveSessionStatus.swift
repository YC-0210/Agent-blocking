import Foundation

/// The single in-app answer to "is a focus session active — and for which profile, and what
/// kind?". Every in-app screen and Shortcuts intent reads an `ActiveSessionStatus` instead of
/// re-deriving the answer from raw session objects.
///
/// `resolve(manual:scheduled:)` is a pure function of plain facts, so the load-bearing rules —
/// **manual/NFC beats scheduled**, and **a scheduled window counts even before it is synced
/// into SwiftData** — are defined in one place and unit-tested with no live app. It reads the
/// existing stores; it does NOT merge them (the App Group snapshots stay the cross-process
/// signaling layer for the widget / extension). See `docs/adr/0002-active-session-status-read-api.md`.
///
/// (Named `ActiveSessionStatus` to avoid colliding with `SessionStatus`, the started/ended
/// lifecycle-event enum in `BlockingStrategy`.)
struct ActiveSessionStatus: Equatable {
  /// What kind of session is currently active.
  enum Kind: Equatable {
    case none
    case manual
    case scheduled
  }

  let kind: Kind
  let activeProfileId: UUID?
  /// Planned timer length, when the active session is a timer session; `nil` for a classic
  /// (card-ends) session or when nothing is active.
  let plannedDurationMinutes: Int?

  var isBlocking: Bool { kind != .none }

  static let none = ActiveSessionStatus(kind: .none, activeProfileId: nil, plannedDurationMinutes: nil)
}

extension ActiveSessionStatus {
  /// The minimal facts about one active session that the answer is derived from — kept plain
  /// (not the SwiftData / App Group types) so the resolver stays pure and testable.
  struct SessionFacts: Equatable {
    let profileId: UUID
    let plannedDurationMinutes: Int?

    init(profileId: UUID, plannedDurationMinutes: Int? = nil) {
      self.profileId = profileId
      self.plannedDurationMinutes = plannedDurationMinutes
    }
  }

  /// Resolve the current status from the available facts. A manual / NFC session takes
  /// precedence over a scheduled one (the existing `activeStrategySharedSession ??
  /// activeScheduleSharedSession` ordering). A scheduled fact suppresses to `.scheduled` even
  /// when no manual session exists — so a scheduled window counts before it is synced into
  /// SwiftData.
  static func resolve(manual: SessionFacts?, scheduled: SessionFacts?) -> ActiveSessionStatus {
    if let manual {
      return ActiveSessionStatus(
        kind: .manual,
        activeProfileId: manual.profileId,
        plannedDurationMinutes: manual.plannedDurationMinutes)
    }
    if let scheduled {
      return ActiveSessionStatus(
        kind: .scheduled,
        activeProfileId: scheduled.profileId,
        plannedDurationMinutes: scheduled.plannedDurationMinutes)
    }
    return .none
  }
}
