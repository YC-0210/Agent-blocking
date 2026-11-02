import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import SwiftData

@Model
class BlockedProfiles {
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

  var schedules: [BlockedProfileSchedule] = []

  /// Legacy property — kept for SwiftData migration from single-schedule to multi-schedule.
  /// After migration, this is always nil. Do not use directly; use `schedules` instead.
  var schedule: BlockedProfileSchedule? = nil

  var customReminderMessage: String?

  @Relationship var sessions: [BlockedProfileSession] = []

  var activeScheduleTimerActivities: [DeviceActivityName] {
    return DeviceActivityCenterUtil.getActiveScheduleTimerActivities(for: self)
  }

  var hasActiveSchedules: Bool {
    return schedules.contains(where: { $0.isActive })
  }

  var scheduleIsOutOfSync: Bool {
    return hasActiveSchedules
      && DeviceActivityCenterUtil.getActiveScheduleTimerActivities(for: self).isEmpty
  }

  init(
    id: UUID = UUID(),
    name: String,
    selectedActivity: FamilyActivitySelection = FamilyActivitySelection(),
    createdAt: Date = Date(),
    updatedAt: Date = Date(),
    blockingStrategyId: String = NFCBlockingStrategy.id,
    strategyData: Data? = nil,
    enableLiveActivity: Bool = false,
    reminderTimeInSeconds: UInt32? = nil,
    customReminderMessage: String? = nil,
    enableBreaks: Bool = false,
    breakTimeInMinutes: Int = 15,
    enableAllowMode: Bool = false,
    enableAllowModeDomains: Bool = false,
    enableSafariBlocking: Bool = true,
    order: Int = 0,
    domains: [String]? = nil,
    physicalUnblockNFCTagIds: [String]? = nil,
    schedules: [BlockedProfileSchedule] = []
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
    self.customReminderMessage = customReminderMessage
    self.enableLiveActivity = enableLiveActivity
    self.enableBreaks = enableBreaks
    self.breakTimeInMinutes = breakTimeInMinutes
    self.enableAllowMode = enableAllowMode
    self.enableAllowModeDomains = enableAllowModeDomains
    self.enableSafariBlocking = enableSafariBlocking
    self.domains = domains

    self.physicalUnblockNFCTagIds = physicalUnblockNFCTagIds
    self.schedules = schedules
  }

  func showStopButton(elapsedTime: TimeInterval) -> Bool {
    guard let strategyData = self.strategyData else { return true }
    let timerData = StrategyTimerData.toStrategyTimerData(from: strategyData)

    // If hideStopButton is false, always show the stop button
    if !timerData.hideStopButton {
      return true
    }

    let durationInSeconds = Double(timerData.durationInMinutes * 60)
    return elapsedTime >= durationInSeconds
  }

  static func fetchProfiles(in context: ModelContext) throws
    -> [BlockedProfiles]
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [
        SortDescriptor(\.order, order: .forward), SortDescriptor(\.createdAt, order: .reverse),
      ]
    )
    return try context.fetch(descriptor)
  }

  static func findProfile(byID id: UUID, in context: ModelContext) throws
    -> BlockedProfiles?
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      predicate: #Predicate { $0.id == id }
    )
    return try context.fetch(descriptor).first
  }

  static func fetchMostRecentlyUpdatedProfile(in context: ModelContext) throws
    -> BlockedProfiles?
  {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
    )
    return try context.fetch(descriptor).first
  }

  @discardableResult
  static func updateProfile(
    _ profile: BlockedProfiles,
    in context: ModelContext,
    name: String? = nil,
    selection: FamilyActivitySelection? = nil,
    blockingStrategyId: String? = nil,
    strategyData: Data? = nil,
    enableLiveActivity: Bool? = nil,
    reminderTime: UInt32? = nil,
    customReminderMessage: String? = nil,
    enableBreaks: Bool? = nil,
    breakTimeInMinutes: Int? = nil,
    enableAllowMode: Bool? = nil,
    enableAllowModeDomains: Bool? = nil,
    enableSafariBlocking: Bool? = nil,
    order: Int? = nil,
    domains: [String]? = nil,
    physicalUnblockNFCTagIds: [String]? = nil,
    schedules: [BlockedProfileSchedule]? = nil
  ) throws -> BlockedProfiles {
    guard SelectionRules.canSave(appCount: (selection ?? profile.selectedActivity).applicationTokens.count,
      hasAccess: SharedData.effectiveSubscriptionTier == .premium) else {
      throw NSError(domain: "SubscriptionAccess", code: 1,
        userInfo: [NSLocalizedDescriptionKey: String(localized: "An active subscription and a selection of at most 50 apps are required.")])
    }

    if let newName = name {
      profile.name = newName
    }

    if let newSelection = selection {
      profile.selectedActivity = newSelection
    }

    if let newStrategyId = blockingStrategyId {
      profile.blockingStrategyId = newStrategyId
    }

    if let newStrategyData = strategyData {
      profile.strategyData = newStrategyData
    }

    if let newEnableLiveActivity = enableLiveActivity {
      profile.enableLiveActivity = newEnableLiveActivity
    }

    if let newEnableBreaks = enableBreaks {
      profile.enableBreaks = newEnableBreaks
    }

    if let newBreakTimeInMinutes = breakTimeInMinutes {
      profile.breakTimeInMinutes = newBreakTimeInMinutes
    }

    if let newEnableAllowMode = enableAllowMode {
      profile.enableAllowMode = newEnableAllowMode
    }

    if let newEnableAllowModeDomains = enableAllowModeDomains {
      profile.enableAllowModeDomains = newEnableAllowModeDomains
    }

    if let newEnableSafariBlocking = enableSafariBlocking {
      profile.enableSafariBlocking = newEnableSafariBlocking
    }

    if let newOrder = order {
      profile.order = newOrder
    }

    if let newDomains = domains {
      profile.domains = newDomains
    }

    if let newSchedules = schedules {
      profile.schedules = newSchedules
    }

    // Values can be nil when removed
    profile.physicalUnblockNFCTagIds = physicalUnblockNFCTagIds

    profile.reminderTimeInSeconds = reminderTime
    profile.customReminderMessage = customReminderMessage
    profile.updatedAt = Date()

    // Update the snapshot
    updateSnapshot(for: profile)

    try context.save()

    return profile
  }

  static func deleteProfile(
    _ profile: BlockedProfiles,
    in context: ModelContext
  ) throws {
    // First end any active sessions
    for session in profile.sessions {
      if session.endTime == nil {
        session.endSession()
      }
    }

    // Remove all sessions first
    for session in profile.sessions {
      context.delete(session)
    }

    // Delete the snapshot
    deleteSnapshot(for: profile)

    // Remove the schedule restrictions
    DeviceActivityCenterUtil.removeScheduleTimerActivities(for: profile)

    // Then delete the profile
    context.delete(profile)
    // Defer context saving as the reference to the profile might be used
  }

  static func getProfileDeepLink(_ profile: BlockedProfiles) -> String {
    return "https://do-card.online/profile/" + profile.id.uuidString
  }

  static func getSnapshot(for profile: BlockedProfiles) -> SharedData.ProfileSnapshot {
    return SharedData.ProfileSnapshot(
      id: profile.id,
      name: profile.name,
      selectedActivity: profile.selectedActivity,
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt,
      blockingStrategyId: profile.blockingStrategyId,
      strategyData: profile.strategyData,
      order: profile.order,
      enableLiveActivity: profile.enableLiveActivity,
      reminderTimeInSeconds: profile.reminderTimeInSeconds,
      customReminderMessage: profile.customReminderMessage,
      enableBreaks: profile.enableBreaks,
      breakTimeInMinutes: profile.breakTimeInMinutes,
      enableAllowMode: profile.enableAllowMode,
      enableAllowModeDomains: profile.enableAllowModeDomains,
      enableSafariBlocking: profile.enableSafariBlocking,
      domains: profile.domains,
      physicalUnblockNFCTagIds: profile.physicalUnblockNFCTagIds,
      schedules: profile.schedules
    )
  }

  // Create a codable/equatable snapshot suitable for UserDefaults
  static func updateSnapshot(for profile: BlockedProfiles) {
    let snapshot = getSnapshot(for: profile)
    SharedData.setSnapshot(snapshot, for: profile.id.uuidString)
  }

  static func deleteSnapshot(for profile: BlockedProfiles) {
    SharedData.removeSnapshot(for: profile.id.uuidString)
  }

  static func reorderProfiles(
    _ profiles: [BlockedProfiles],
    in context: ModelContext
  ) throws {
    for (index, profile) in profiles.enumerated() {
      profile.order = index
    }
    try context.save()
  }

  static func getNextOrder(in context: ModelContext) -> Int {
    let descriptor = FetchDescriptor<BlockedProfiles>(
      sortBy: [SortDescriptor(\.order, order: .reverse)]
    )
    guard let lastProfile = try? context.fetch(descriptor).first else {
      return 0
    }
    return lastProfile.order + 1
  }

  static func createProfile(
    in context: ModelContext,
    name: String,
    selection: FamilyActivitySelection = FamilyActivitySelection(),
    blockingStrategyId: String = NFCBlockingStrategy.id,
    strategyData: Data? = nil,
    enableLiveActivity: Bool = false,
    reminderTimeInSeconds: UInt32? = nil,
    customReminderMessage: String = "",
    enableBreaks: Bool = false,
    breakTimeInMinutes: Int = 15,
    enableAllowMode: Bool = false,
    enableAllowModeDomains: Bool = false,
    enableSafariBlocking: Bool = true,
    domains: [String]? = nil,
    physicalUnblockNFCTagIds: [String]? = nil,
    schedules: [BlockedProfileSchedule] = []
  ) throws -> BlockedProfiles {
    guard SelectionRules.canSave(appCount: selection.applicationTokens.count,
      hasAccess: SharedData.effectiveSubscriptionTier == .premium) else {
      throw NSError(domain: "SubscriptionAccess", code: 1,
        userInfo: [NSLocalizedDescriptionKey: String(localized: "An active subscription and a selection of at most 50 apps are required.")])
    }

    let profileOrder = getNextOrder(in: context)

    let profile = BlockedProfiles(
      name: name,
      selectedActivity: selection,
      blockingStrategyId: blockingStrategyId,
      strategyData: strategyData,
      enableLiveActivity: enableLiveActivity,
      reminderTimeInSeconds: reminderTimeInSeconds,
      customReminderMessage: customReminderMessage,
      enableBreaks: enableBreaks,
      breakTimeInMinutes: breakTimeInMinutes,
      enableAllowMode: enableAllowMode,
      enableAllowModeDomains: enableAllowModeDomains,
      enableSafariBlocking: enableSafariBlocking,
      order: profileOrder,
      domains: domains,
      physicalUnblockNFCTagIds: physicalUnblockNFCTagIds
    )

    if !schedules.isEmpty {
      profile.schedules = schedules
    }

    // Create the snapshot so extensions can read it immediately
    updateSnapshot(for: profile)

    context.insert(profile)
    try context.save()
    return profile
  }

  static func cloneProfile(
    _ source: BlockedProfiles,
    in context: ModelContext,
    newName: String
  ) throws -> BlockedProfiles {
    guard SelectionRules.canSave(appCount: source.selectedActivity.applicationTokens.count,
      hasAccess: SharedData.effectiveSubscriptionTier == .premium) else {
      throw NSError(domain: "SubscriptionAccess", code: 1,
        userInfo: [NSLocalizedDescriptionKey: String(localized: "An active subscription and a selection of at most 50 apps are required.")])
    }

    let nextOrder = getNextOrder(in: context)
    let cloned = BlockedProfiles(
      name: newName,
      selectedActivity: source.selectedActivity,
      blockingStrategyId: source.blockingStrategyId ?? NFCBlockingStrategy.id,
      strategyData: source.strategyData,
      enableLiveActivity: source.enableLiveActivity,
      reminderTimeInSeconds: source.reminderTimeInSeconds,
      customReminderMessage: source.customReminderMessage,
      enableBreaks: source.enableBreaks,
      breakTimeInMinutes: source.breakTimeInMinutes,
      enableAllowMode: source.enableAllowMode,
      enableAllowModeDomains: source.enableAllowModeDomains,
      enableSafariBlocking: source.enableSafariBlocking,
      order: nextOrder,
      domains: source.domains,
      physicalUnblockNFCTagIds: source.physicalUnblockNFCTagIds,
      schedules: source.schedules
    )

    context.insert(cloned)
    try context.save()
    return cloned
  }

  static func addSchedule(
    to profile: BlockedProfiles,
    in context: ModelContext,
    schedule: BlockedProfileSchedule
  ) throws {
    var updated = profile.schedules
    updated.append(schedule)
    try updateProfile(profile, in: context, schedules: updated)
  }

  static func updateSchedule(
    in profile: BlockedProfiles,
    context: ModelContext,
    schedule: BlockedProfileSchedule
  ) throws {
    var updated = profile.schedules
    if let index = updated.firstIndex(where: { $0.id == schedule.id }) {
      updated[index] = schedule
    } else {
      updated.append(schedule)
    }
    try updateProfile(profile, in: context, schedules: updated)
  }

  static func removeSchedule(
    from profile: BlockedProfiles,
    in context: ModelContext,
    scheduleId: UUID
  ) throws {
    let updated = profile.schedules.filter { $0.id != scheduleId }
    try updateProfile(profile, in: context, schedules: updated)
  }

  static func addDomain(to profile: BlockedProfiles, context: ModelContext, domain: String) throws {
    guard let domains = profile.domains else {
      return
    }

    if domains.contains(domain) {
      return
    }

    let newDomains = domains + [domain]
    try updateProfile(profile, in: context, domains: newDomains)
  }

  static func removeDomain(from profile: BlockedProfiles, context: ModelContext, domain: String)
    throws
  {
    guard let domains = profile.domains else {
      return
    }

    let newDomains = domains.filter { $0 != domain }
    try updateProfile(profile, in: context, domains: newDomains)
  }

  // MARK: - Migration: single schedule → multi-schedule

  /// Migrates profiles that have data in the legacy `schedule` property into the new `schedules` array.
  /// Safe to call multiple times — only migrates profiles that still have legacy data.
  static func migrateSchedulesToArray(in context: ModelContext) {
    guard let profiles = try? fetchProfiles(in: context) else { return }
    var didMigrate = false

    for profile in profiles {
      if let legacySchedule = profile.schedule {
        // Ensure the legacy schedule gets an id if it didn't have one
        var migrated = legacySchedule
        if migrated.id == UUID(uuidString: "00000000-0000-0000-0000-000000000000") {
          migrated.id = UUID()
        }
        profile.schedules.append(migrated)
        profile.schedule = nil
        didMigrate = true
      }
    }

    if didMigrate {
      try? context.save()
    }
  }
}
