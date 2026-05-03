import FamilyControls
import Foundation
import SwiftData

// MARK: - Schema V1 (1.0.0) — v1.30.1 first App Store release
//
// v1.30.1 shipped with NO migration plan. SwiftData auto-stamped new stores
// as "1.0.0". This inline snapshot must match v1.30.1's runtime @Model classes
// property-for-property so the entity hash aligns with real user stores on
// devices that first installed v1.30.1.
//
// Critical differences from prior (incorrect) AppSchemaV1:
//   • BlockedProfiles has 20 stored properties, not 7
//   • physicalUnblockNFCTagIds is [String]? (array), not a singular String?
//   • enableStrictMode and disableBackgroundStops do NOT exist
//   • schedule: BlockedProfileSchedule? where BlockedProfileSchedule has NO id,
//     NO isNextDay — exactly matching the v1.30.1 struct definition
//   • BlockedProfileSession has forceStarted but NO triggerSource / endReason
//   • No NFCTapEvent, no EmergencyUnlockEvent

enum AppSchemaV1: VersionedSchema {
  static var versionIdentifier = Schema.Version(1, 0, 0)

  static var models: [any PersistentModel.Type] = [
    AppSchemaV1.BlockedProfileSession.self,
    AppSchemaV1.BlockedProfiles.self,
  ]

  // v1.30.1 BlockedProfileSchedule:
  //   • No `id` field (not Identifiable)
  //   • No `isNextDay`
  //   • endType defaults to .cardTap
  // SwiftData flattens this struct into individual SQLite columns on
  // ZBLOCKEDPROFILES (ZSTARTHOUR, ZSTARTMINUTE, ZENDHOUR, ZENDMINUTE,
  // ZENDTYPE, ZUPDATEDAT1, ZNAME1, ZDAYS). Each structural change to this
  // struct shifts the BlockedProfiles entity hash.
  struct BlockedProfileSchedule: Codable, Equatable {
    var name: String = ""
    var days: [Weekday]
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var endType: ScheduleEndType = .cardTap
    var updatedAt: Date = Date()
  }

  @Model
  final class BlockedProfiles {
    @Attribute(.unique) var id: UUID
    var name: String
    var selectedActivity: FamilyActivitySelection
    var createdAt: Date
    var updatedAt: Date
    var blockingStrategyId: String?
    var strategyData: Data?
    var order: Int = 0

    var enableLiveActivity: Bool = false
    var reminderTimeInSeconds: UInt32?
    var enableBreaks: Bool = false
    var breakTimeInMinutes: Int = 15
    var enableAllowMode: Bool = false
    var enableAllowModeDomains: Bool = false
    var enableSafariBlocking: Bool = true

    var physicalUnblockNFCTagIds: [String]? = nil
    var domains: [String]? = nil
    var schedule: AppSchemaV1.BlockedProfileSchedule? = nil
    var customReminderMessage: String?

    @Relationship var sessions: [AppSchemaV1.BlockedProfileSession] = []

    init(
      id: UUID = UUID(),
      name: String = "",
      selectedActivity: FamilyActivitySelection = FamilyActivitySelection(),
      createdAt: Date = Date(),
      updatedAt: Date = Date(),
      blockingStrategyId: String? = nil,
      strategyData: Data? = nil,
      order: Int = 0,
      enableLiveActivity: Bool = false,
      reminderTimeInSeconds: UInt32? = nil,
      enableBreaks: Bool = false,
      breakTimeInMinutes: Int = 15,
      enableAllowMode: Bool = false,
      enableAllowModeDomains: Bool = false,
      enableSafariBlocking: Bool = true,
      physicalUnblockNFCTagIds: [String]? = nil,
      domains: [String]? = nil,
      schedule: AppSchemaV1.BlockedProfileSchedule? = nil,
      customReminderMessage: String? = nil
    ) {
      self.id = id
      self.name = name
      self.selectedActivity = selectedActivity
      self.createdAt = createdAt
      self.updatedAt = updatedAt
      self.blockingStrategyId = blockingStrategyId
      self.strategyData = strategyData
      self.order = order
      self.enableLiveActivity = enableLiveActivity
      self.reminderTimeInSeconds = reminderTimeInSeconds
      self.enableBreaks = enableBreaks
      self.breakTimeInMinutes = breakTimeInMinutes
      self.enableAllowMode = enableAllowMode
      self.enableAllowModeDomains = enableAllowModeDomains
      self.enableSafariBlocking = enableSafariBlocking
      self.physicalUnblockNFCTagIds = physicalUnblockNFCTagIds
      self.domains = domains
      self.schedule = schedule
      self.customReminderMessage = customReminderMessage
    }
  }

  @Model
  final class BlockedProfileSession {
    @Attribute(.unique) var id: String
    var tag: String

    @Relationship var blockedProfile: AppSchemaV1.BlockedProfiles

    var startTime: Date
    var endTime: Date?
    var breakStartTime: Date?
    var breakEndTime: Date?
    var forceStarted: Bool = false

    init(
      id: String = UUID().uuidString,
      tag: String = "",
      blockedProfile: AppSchemaV1.BlockedProfiles,
      startTime: Date = Date(),
      endTime: Date? = nil,
      breakStartTime: Date? = nil,
      breakEndTime: Date? = nil,
      forceStarted: Bool = false
    ) {
      self.id = id
      self.tag = tag
      self.blockedProfile = blockedProfile
      self.startTime = startTime
      self.endTime = endTime
      self.breakStartTime = breakStartTime
      self.breakEndTime = breakEndTime
      self.forceStarted = forceStarted
    }
  }
}

// MARK: - Schema V2 (1.40.1) — v1.40.1
//
// Changes from V1:
//   BlockedProfiles:
//     • schedule: BlockedProfileSchedule gains `id: UUID` → adds ZID1 column
//     • schedules: [BlockedProfileSchedule] = [] added → ZSCHEDULES blob
//   BlockedProfileSession:
//     • triggerSource: String = "manual" added
//     • endReason: String? added
//   New entities: NFCTapEvent, EmergencyUnlockEvent

enum AppSchemaV2: VersionedSchema {
  static var versionIdentifier = Schema.Version(1, 40, 1)

  static var models: [any PersistentModel.Type] = [
    AppSchemaV2.BlockedProfileSession.self,
    AppSchemaV2.BlockedProfiles.self,
    AppSchemaV2.NFCTapEvent.self,
    AppSchemaV2.EmergencyUnlockEvent.self,
  ]

  // v1.40.1 BlockedProfileSchedule:
  //   • Adds `id: UUID = UUID()` → now Identifiable → adds ZID1 column
  //   • No `isNextDay` yet
  //   • endType still defaults to .cardTap
  struct BlockedProfileSchedule: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var name: String = ""
    var days: [Weekday]
    var startHour: Int
    var startMinute: Int
    var endHour: Int
    var endMinute: Int
    var endType: ScheduleEndType = .cardTap
    var updatedAt: Date = Date()
  }

  @Model
  final class BlockedProfiles {
    @Attribute(.unique) var id: UUID
    var name: String
    var selectedActivity: FamilyActivitySelection
    var createdAt: Date
    var updatedAt: Date
    var blockingStrategyId: String?
    var strategyData: Data?
    var order: Int = 0

    var enableLiveActivity: Bool = false
    var reminderTimeInSeconds: UInt32?
    var enableBreaks: Bool = false
    var breakTimeInMinutes: Int = 15
    var enableAllowMode: Bool = false
    var enableAllowModeDomains: Bool = false
    var enableSafariBlocking: Bool = true

    var physicalUnblockNFCTagIds: [String]? = nil
    var domains: [String]? = nil
    var schedule: AppSchemaV2.BlockedProfileSchedule? = nil
    var schedules: [AppSchemaV2.BlockedProfileSchedule] = []
    var customReminderMessage: String?

    @Relationship var sessions: [AppSchemaV2.BlockedProfileSession] = []

    init(
      id: UUID = UUID(),
      name: String = "",
      selectedActivity: FamilyActivitySelection = FamilyActivitySelection(),
      createdAt: Date = Date(),
      updatedAt: Date = Date(),
      blockingStrategyId: String? = nil,
      strategyData: Data? = nil,
      order: Int = 0,
      enableLiveActivity: Bool = false,
      reminderTimeInSeconds: UInt32? = nil,
      enableBreaks: Bool = false,
      breakTimeInMinutes: Int = 15,
      enableAllowMode: Bool = false,
      enableAllowModeDomains: Bool = false,
      enableSafariBlocking: Bool = true,
      physicalUnblockNFCTagIds: [String]? = nil,
      domains: [String]? = nil,
      schedule: AppSchemaV2.BlockedProfileSchedule? = nil,
      schedules: [AppSchemaV2.BlockedProfileSchedule] = [],
      customReminderMessage: String? = nil
    ) {
      self.id = id
      self.name = name
      self.selectedActivity = selectedActivity
      self.createdAt = createdAt
      self.updatedAt = updatedAt
      self.blockingStrategyId = blockingStrategyId
      self.strategyData = strategyData
      self.order = order
      self.enableLiveActivity = enableLiveActivity
      self.reminderTimeInSeconds = reminderTimeInSeconds
      self.enableBreaks = enableBreaks
      self.breakTimeInMinutes = breakTimeInMinutes
      self.enableAllowMode = enableAllowMode
      self.enableAllowModeDomains = enableAllowModeDomains
      self.enableSafariBlocking = enableSafariBlocking
      self.physicalUnblockNFCTagIds = physicalUnblockNFCTagIds
      self.domains = domains
      self.schedule = schedule
      self.schedules = schedules
      self.customReminderMessage = customReminderMessage
    }
  }

  @Model
  final class BlockedProfileSession {
    @Attribute(.unique) var id: String
    var tag: String

    @Relationship var blockedProfile: AppSchemaV2.BlockedProfiles

    var startTime: Date
    var endTime: Date?
    var breakStartTime: Date?
    var breakEndTime: Date?
    var forceStarted: Bool = false
    var triggerSource: String = "manual"
    var endReason: String?

    init(
      id: String = UUID().uuidString,
      tag: String = "",
      blockedProfile: AppSchemaV2.BlockedProfiles,
      startTime: Date = Date(),
      endTime: Date? = nil,
      breakStartTime: Date? = nil,
      breakEndTime: Date? = nil,
      forceStarted: Bool = false,
      triggerSource: String = "manual",
      endReason: String? = nil
    ) {
      self.id = id
      self.tag = tag
      self.blockedProfile = blockedProfile
      self.startTime = startTime
      self.endTime = endTime
      self.breakStartTime = breakStartTime
      self.breakEndTime = breakEndTime
      self.forceStarted = forceStarted
      self.triggerSource = triggerSource
      self.endReason = endReason
    }
  }

  @Model
  final class NFCTapEvent {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var action: String
    var profileId: UUID
    var profileName: String

    init(
      id: String = UUID().uuidString,
      timestamp: Date = Date(),
      action: String = "",
      profileId: UUID = UUID(),
      profileName: String = ""
    ) {
      self.id = id
      self.timestamp = timestamp
      self.action = action
      self.profileId = profileId
      self.profileName = profileName
    }
  }

  @Model
  final class EmergencyUnlockEvent {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var sessionId: String
    var profileId: UUID
    var sessionDuration: TimeInterval

    init(
      id: String = UUID().uuidString,
      timestamp: Date = Date(),
      sessionId: String = "",
      profileId: UUID = UUID(),
      sessionDuration: TimeInterval = 0
    ) {
      self.id = id
      self.timestamp = timestamp
      self.sessionId = sessionId
      self.profileId = profileId
      self.sessionDuration = sessionDuration
    }
  }
}

// MARK: - Schema V3 (2.0.2) — v2.0.2
//
// Changes from V2:
//   BlockedProfileSchedule (affects the flattened `schedule` column group):
//     • isNextDay: Bool = false added → ZISNEXTDAY column on BlockedProfiles
//     • endType default changed from .cardTap → .specificTime
//   No other structural changes to @Model classes.

enum AppSchemaV3: VersionedSchema {
  static var versionIdentifier = Schema.Version(2, 0, 2)

  static var models: [any PersistentModel.Type] = [
    BlockedProfileSession.self,
    BlockedProfiles.self,
    NFCTapEvent.self,
    EmergencyUnlockEvent.self,
  ]
}

// MARK: - Migration Plan
//
// SwiftData prohibits migration stages between schema versions with identical
// entity checksums. Since v2.0.3 has no structural model changes from v2.0.2,
// AppSchemaV3 (2.0.2) serves as the final schema node. All stores end up
// stamped "2.0.2" regardless of marketing version — this is intentional.
//
// Migration paths:
//   v1.30.1 (stamp "1.0.0") → V1→V2→V3 → stamp "2.0.2" ✓
//   v1.40.1 (stamp "1.40.1") → V2→V3 → stamp "2.0.2" ✓
//   v2.0.2  (stamp "2.0.2")  → no migration → stamp "2.0.2" ✓
//   fresh install             → stamp "2.0.2" ✓

enum AppMigrationPlan: SchemaMigrationPlan {
  static var schemas: [any VersionedSchema.Type] = [
    AppSchemaV1.self,
    AppSchemaV2.self,
    AppSchemaV3.self,
  ]

  // V1 → V2 (v1.30.1 → v1.40.1): lightweight
  //   BlockedProfiles: schedule gains id (ZID1), schedules array added (ZSCHEDULES)
  //   BlockedProfileSession: triggerSource ("manual"), endReason (nil)
  //   New entities: NFCTapEvent, EmergencyUnlockEvent
  static let migrateV1toV2 = MigrationStage.lightweight(
    fromVersion: AppSchemaV1.self,
    toVersion: AppSchemaV2.self
  )

  // V2 → V3 (v1.40.1 → v2.0.2): lightweight
  //   BlockedProfileSchedule.schedule: isNextDay added (ZISNEXTDAY, false)
  static let migrateV2toV3 = MigrationStage.lightweight(
    fromVersion: AppSchemaV2.self,
    toVersion: AppSchemaV3.self
  )

  static var stages: [MigrationStage] = [
    migrateV1toV2,
    migrateV2toV3,
  ]
}
