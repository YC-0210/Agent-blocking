import Foundation

/// The single owner of the schedule-**suppression storage contract**.
///
/// A *suppression flag* is a short-lived, HMAC-signed App Group value that tells every
/// process (app, DeviceActivity extension, widget) NOT to re-apply a scheduled block for the
/// rest of the current window — because the user just ended that window deliberately
/// (Emergency Unlock, or a card tap that stopped a scheduled session).
///
/// Before this type, the two key prefixes and the `"<prefix><activityId>"` key shape were
/// copied verbatim into three processes, and the read / cleanup loops were re-implemented per
/// caller (any drift could re-lock a device right after an unlock, or fail to suppress at
/// all). `SuppressionRegistry` collapses that to one interface the three processes cross: it
/// owns the **prefixes**, the **activity-id shape**, and the **read / write / cleanup** of the
/// flags. It signs through `SharedData`'s existing HMAC helpers, so suppression flags use the
/// very same tamper protection as every other shared value.
///
/// Scope, by design: this type owns only the *storage* of the flags. The scheduling-clock
/// logic — which schedule window is open right now and when it ends — deliberately stays in
/// `SharedData`, which owns `ProfileSnapshot` and the calendar math. Keep them separate; see
/// `docs/adr/0001-suppression-registry.md`.
enum SuppressionRegistry {
  /// Why a scheduled window is suppressed. Each reason has its own key namespace so the
  /// source of a suppression stays legible in storage and logs.
  enum Reason {
    /// The user spent an Emergency Unlock to end the scheduled session early.
    case emergencyUnlock
    /// The user tapped their card to stop a scheduled session.
    case cardTap

    /// The key-prefix namespace for this reason. Callers should never build keys by hand —
    /// go through `suppress` / `isSuppressed`. Exposed only so tests can inspect storage.
    var prefix: String {
      switch self {
      case .emergencyUnlock: return "emergencyUnlockedSchedule_"
      case .cardTap: return "cardTapSuppressedSchedule_"
      }
    }
  }

  /// Every reason, used when reading or cleaning without caring which one set the flag.
  private static let allReasons: [Reason] = [.emergencyUnlock, .cardTap]

  /// The App Group the flags live in. Used only to enumerate keys in `cleanupExpired`;
  /// per-key writes / reads / removes go through `SharedData`, which owns the same suite.
  private static let appGroupSuiteName = "group.DO.version3"

  /// The canonical identifier for one schedule's daily window. This is the **single**
  /// definition of the `"<profile>.<schedule>_<weekday>"` shape — the DeviceActivity extension
  /// passes its `DeviceActivityName.rawValue` (built identically in
  /// `ScheduleTimerActivity.getDeviceActivityName(from:scheduleId:weekday:)`) straight through
  /// `isSuppressed`, so the two can never drift.
  static func activityId(profileId: UUID, scheduleId: UUID, weekday: Weekday) -> String {
    "\(profileId.uuidString).\(scheduleId.uuidString)_\(weekday.rawValue)"
  }

  /// Write a suppression flag for `activityId`, valid until `windowEnd`. Signed and flushed
  /// for cross-process visibility via `SharedData`.
  static func suppress(activityId: String, reason: Reason, until windowEnd: Date) {
    SharedData.writeSignedDouble(
      windowEnd.timeIntervalSince1970,
      forKey: reason.prefix + activityId
    )
  }

  /// Whether `activityId` is currently suppressed by **any** reason. Self-healing: a flag whose
  /// window has already ended is removed as a side effect and treated as not suppressing.
  static func isSuppressed(activityId: String, now: Date = Date()) -> Bool {
    for reason in allReasons {
      let key = reason.prefix + activityId
      guard let windowEndTimestamp = SharedData.readVerifiedDouble(forKey: key) else { continue }

      if now < Date(timeIntervalSince1970: windowEndTimestamp) {
        return true
      }

      SharedData.removeSignedValue(forKey: key)
    }
    return false
  }

  /// Remove every suppression flag whose window has already ended. Sweeps flags that were
  /// written but never read back, so `isSuppressed`'s read-time cleanup never fired for them.
  static func cleanupExpired(
    now: Date = Date(),
    suite: UserDefaults? = UserDefaults(suiteName: appGroupSuiteName)
  ) {
    guard let suite else { return }
    let prefixes = allReasons.map(\.prefix)

    for key in suite.dictionaryRepresentation().keys
    where prefixes.contains(where: { key.hasPrefix($0) }) {
      guard
        let data = suite.object(forKey: key) as? Data,
        let windowEndTimestamp = try? JSONDecoder().decode(Double.self, from: data)
      else {
        // Not a decodable timestamp (e.g. a `.hmac` companion or corrupt value) — drop it
        // along with its signature.
        SharedData.removeSignedValue(forKey: key)
        continue
      }

      if now >= Date(timeIntervalSince1970: windowEndTimestamp) {
        SharedData.removeSignedValue(forKey: key)
      }
    }
  }
}
