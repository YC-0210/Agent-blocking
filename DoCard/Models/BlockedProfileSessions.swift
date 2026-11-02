import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "app.docard", category: "BlockedProfileSession")

@Model
class BlockedProfileSession {
  @Attribute(.unique) var id: String
  var tag: String

  @Relationship var blockedProfile: BlockedProfiles

  var startTime: Date
  var endTime: Date?

  var breakStartTime: Date?
  var breakEndTime: Date?

  var forceStarted: Bool = false

  /// How the session was initiated.
  /// Values: "manual" | "scheduled" | "shortcut" | "deeplink"
  var triggerSource: String = "manual"

  /// How the session ended. nil = still active.
  /// Values: "card_tap" | "timer_expired" | "emergency_unlock" | nil
  var endReason: String?

  var isActive: Bool {
    return endTime == nil
  }

  var isBreakAvailable: Bool {
    return blockedProfile.enableBreaks == true
      && breakEndTime == nil
  }

  var isBreakActive: Bool {
    return blockedProfile.enableBreaks == true
      && breakStartTime != nil
      && breakEndTime == nil
  }

  var duration: TimeInterval {
    let end = endTime ?? Date()
    return end.timeIntervalSince(startTime)
  }

  init(
    tag: String,
    blockedProfile: BlockedProfiles,
    forceStarted: Bool = false,
    triggerSource: String = "manual"
  ) {
    self.id = UUID().uuidString
    self.tag = tag
    self.blockedProfile = blockedProfile
    self.startTime = SharedData.currentDate
    self.forceStarted = forceStarted
    self.triggerSource = triggerSource

    // Add this session to the profile's sessions array
    blockedProfile.sessions.append(self)
  }

  func startBreak() {
    let breakStartTime = Date()

    SharedData.setBreakStartTime(date: breakStartTime)
    self.breakStartTime = breakStartTime
  }

  func endBreak() {
    let breakEndTime = Date()

    SharedData.setBreakEndTime(date: breakEndTime)
    self.breakEndTime = breakEndTime
  }

  func endSession() {
    let endTime = SharedData.currentDate

    // Set the end time in shared data in case its being saved
    SharedData.setEndTime(date: endTime)
    self.endTime = endTime

    SharedData.flushActiveStrategySession()
  }

  func endSessionFully(
    in context: ModelContext,
    endReason: String,
    onSaveError: ((Error) -> Void)? = nil
  ) {
    let hasExistingEndReason = !(self.endReason?.isEmpty ?? true)
    if hasExistingEndReason {
      if self.endReason != endReason {
        logger.warning(
          "endSessionFully preserving existing endReason '\(self.endReason ?? "", privacy: .public)' instead of overwriting with '\(endReason, privacy: .public)' for session '\(self.id, privacy: .private)'"
        )
      }
    } else if !endReason.isEmpty {
      self.endReason = endReason
    }

    let resolvedEndReason = self.endReason ?? endReason
    endSession()

    if self.triggerSource == "scheduled" {
      // endSessionFully writes endTime/endReason directly to SwiftData.
      // Use flush here instead of endActiveScheduleSharedSession(): sending a completed
      // schedule snapshot back through syncScheduleSessions would overwrite SwiftData
      // breakStartTime/breakEndTime with stale nil values because v2.0.4 only syncs break
      // state through the strategy slot, not the schedule slot.
      SharedData.flushActiveScheduleSession()
      SharedData.writeCardTapSuppressionFlags(
        for: BlockedProfiles.getSnapshot(for: self.blockedProfile),
        triggerSource: self.triggerSource,
        endReason: self.endReason
      )
      logger.info(
        "endSessionFully: cleared schedule slot for scheduled session '\(self.id, privacy: .private)' (endReason: '\((resolvedEndReason.isEmpty ? "card_tap" : resolvedEndReason), privacy: .public)')"
      )
    }

    do {
      try context.save()
    } catch {
      logger.error("Failed to save ended session '\(self.id, privacy: .private)': \(error.localizedDescription)")
      logger.info(
        "PHASE_B_RETRY: initial save failed, retrying after rollback for session '\(self.id, privacy: .private)'"
      )
      context.rollback()

      if !resolvedEndReason.isEmpty {
        self.endReason = resolvedEndReason
      }
      endSession()

      do {
        try context.save()
      } catch {
        logger.warning(
          "PHASE_B_RETRY: retry save also failed for session '\(self.id, privacy: .private)': \(error.localizedDescription)"
        )
        onSaveError?(error)
      }
    }
  }

  func toSnapshot(plannedDurationMinutes: Int? = nil) -> SharedData.SessionSnapshot {
    return SharedData.SessionSnapshot(
      id: id,
      tag: tag,
      blockedProfileId: blockedProfile.id,
      startTime: startTime,
      endTime: endTime,
      breakStartTime: breakStartTime,
      breakEndTime: breakEndTime,
      forceStarted: forceStarted,
      triggerSource: triggerSource,
      endReason: endReason,
      plannedDurationMinutes: plannedDurationMinutes
    )
  }

  static func mostRecentActiveSession(in context: ModelContext)
    -> BlockedProfileSession?
  {
    var descriptor = FetchDescriptor<BlockedProfileSession>(
      predicate: #Predicate { $0.endTime == nil },
      sortBy: [SortDescriptor(\.startTime, order: .reverse)]
    )
    descriptor.fetchLimit = 1

    return try? context.fetch(descriptor).first
  }

  static func createSession(
    in context: ModelContext,
    withTag tag: String,
    withProfile profile: BlockedProfiles,
    forceStart: Bool = false,
    triggerSource: String = "manual",
    plannedDurationMinutes: Int? = nil
  ) -> BlockedProfileSession {
    let newSession = BlockedProfileSession(
      tag: tag,
      blockedProfile: profile,
      forceStarted: forceStart,
      triggerSource: triggerSource
    )

    SharedData.createActiveStrategySharedSession(
      for: newSession.toSnapshot(plannedDurationMinutes: plannedDurationMinutes)
    )

    context.insert(newSession)
    return newSession
  }

  static func upsertSessionFromSnapshot(
    in context: ModelContext,
    withSnapshot snapshot: SharedData.SessionSnapshot
  ) {
    let profileID = snapshot.blockedProfileId

    guard let existingProfile = try? BlockedProfiles.findProfile(byID: profileID, in: context)
    else {
      logger.error("Profile not found when creating session from snapshot")
      return
    }

    // Try to find an existing session by id
    if let existingSession = try? findSession(byID: snapshot.id, in: context) {
      // Delayed active snapshots cannot reopen history. A timer completion must also
      // preserve the user's recorded Emergency Unlock time, not just its reason.
      if existingSession.endTime != nil
        && (snapshot.endTime == nil || existingSession.endReason == "emergency_unlock")
      {
        return
      }
      existingSession.tag = snapshot.tag
      // startTime is intentionally NOT overwritten: the SwiftData record's startTime is the
      // authoritative value set at session creation. Overwriting it with a snapshot from
      // App Group UserDefaults can corrupt elapsedTime display when the extension's UserDefaults
      // sync lags behind an Emergency Unlock (the stale snapshot still carries the old startTime).
      existingSession.endTime = snapshot.endTime
      existingSession.breakStartTime = snapshot.breakStartTime
      existingSession.breakEndTime = snapshot.breakEndTime
      existingSession.forceStarted = snapshot.forceStarted
      existingSession.triggerSource = snapshot.triggerSource
      // Protect emergency_unlock audit trail: once set, it must not be overwritten by a
      // timer-expiry snapshot that arrives late from the DeviceActivity extension.
      if existingSession.endReason != "emergency_unlock" {
        existingSession.endReason = snapshot.endReason
      }

      // manually save to ensure changes are persisted
      do {
        try context.save()
      } catch {
        logger.error("Failed to save updated session from snapshot: \(error.localizedDescription)")
      }
      return
    }

    // Create new session from snapshot
    let newSession = BlockedProfileSession(
      tag: snapshot.tag,
      blockedProfile: existingProfile,
      forceStarted: snapshot.forceStarted,
      triggerSource: snapshot.triggerSource
    )
    // Override auto-generated values with snapshot-provided ones
    newSession.id = snapshot.id
    newSession.startTime = snapshot.startTime
    newSession.endTime = snapshot.endTime
    newSession.breakStartTime = snapshot.breakStartTime
    newSession.breakEndTime = snapshot.breakEndTime
    newSession.endReason = snapshot.endReason

    // Let auto-save handle inserts
    context.insert(newSession)
  }

  static func findSession(
    byID id: String,
    in context: ModelContext
  ) throws -> BlockedProfileSession? {
    let descriptor = FetchDescriptor<BlockedProfileSession>(
      predicate: #Predicate { $0.id == id }
    )
    return try context.fetch(descriptor).first
  }

  static func recentInactiveSessions(
    in context: ModelContext,
    limit: Int = 50
  ) -> [BlockedProfileSession] {
    var descriptor = FetchDescriptor<BlockedProfileSession>(
      predicate: #Predicate { $0.endTime != nil },
      sortBy: [SortDescriptor(\.endTime, order: .reverse)]
    )
    descriptor.fetchLimit = limit

    return (try? context.fetch(descriptor)) ?? []
  }
}
