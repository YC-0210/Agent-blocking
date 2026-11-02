import CryptoKit
import FamilyControls
import SwiftData
import XCTest

@testable import DoCard

final class AccessClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date
  init(_ date: Date) { value = date }
  var now: Date {
    get {
      lock.lock()
      defer { lock.unlock() }
      return value
    }
    set {
      lock.lock()
      defer { lock.unlock() }
      value = newValue
    }
  }
}

final class AccessScanner: NFCScannerUtil {
  override func scan(profileName: String, isUnlocking: Bool = false) {}
  func read() {
    onTagScanned?(NFCResult(id: "paired", payload: "docard", DateScanned: SharedData.currentDate))
  }
}

@MainActor
final class AccessFixture {
  let name = "AccessFixture.\(UUID().uuidString)"
  let defaults: UserDefaults
  let key = SymmetricKey(size: .bits256)
  let clock = AccessClock(Date(timeIntervalSince1970: 1_793_581_200))
  let calendar: Calendar
  let container: ModelContainer
  let context: ModelContext
  let profile: BlockedProfiles
  var plans: [AppBlockerUtil.Plan?] = []
  let scanner = AccessScanner()
  var uses = 3
  lazy var blocker = AppBlockerUtil(write: { [weak self] plan in self?.plans.append(plan) })
  lazy var manager = StrategyManager(
    appBlocker: blocker,
    makeStrategy: { [unowned self] _ in ManualBlockingStrategy(appBlocker: self.blocker) },
    makeNFCScanner: { [unowned self] in self.scanner },
    systemEffect: { _ in }, readEmergencyUses: { [unowned self] in self.uses },
    writeEmergencyUses: { [unowned self] in self.uses = $0 })

  init(storeURL: URL? = nil) throws {
    defaults = UserDefaults(suiteName: name)!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "Asia/Taipei")!
    calendar = cal
    clock.now = cal.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
    let schema = Schema(versionedSchema: AppSchemaV5.self)
    let configuration: ModelConfiguration
    if let storeURL {
      configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
    } else {
      configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    }
    container = try ModelContainer(for: schema, configurations: configuration)
    context = ModelContext(container)
    context.autosaveEnabled = false
    profile = BlockedProfiles(
      name: "Work", blockingStrategyId: ManualBlockingStrategy.id,
      enableAllowMode: true, domains: ["example.test"],
      schedules: [
        BlockedProfileSchedule(
          days: [.monday], startHour: 9, startMinute: 0, endHour: 17, endMinute: 0)
      ])
    context.insert(profile)
    try context.save()
  }
  var runtime: SharedData.Runtime {
    let clock = clock
    return SharedData.Runtime(
      defaults: defaults, signingKey: key, now: { clock.now }, calendar: calendar)
  }
  func paid(until seconds: TimeInterval = 1800) {
    SharedData.subscriptionGrants = [
      SubscriptionGrant(
        productID: SubscriptionProduct.monthly,
        purchasedAt: clock.now.addingTimeInterval(-60),
        expiresAt: clock.now.addingTimeInterval(seconds))
    ]
  }
  func publish() { BlockedProfiles.updateSnapshot(for: profile) }
  func cleanup() {
    manager.stopTimer()
    defaults.removePersistentDomain(forName: name)
  }
}

@MainActor
final class SubscriptionLifecycleTests: XCTestCase {
  private func fixture(_ body: (AccessFixture) throws -> Void) throws {
    let f = try AccessFixture()
    defer { f.cleanup() }
    try SharedData.$runtime.withValue(f.runtime) {
      f.publish()
      try body(f)
    }
  }

  func testI2UnpaidAppStartCreatesNoSession() throws {
    try fixture { f in
      f.manager.forceStartSession(context: f.context, profile: f.profile)
      XCTAssertNil(f.manager.activeSession)
      XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfileSession>()), 0)
      XCTAssertFalse(f.plans.contains { $0 != nil })
    }
  }

  func testI2UnpaidBackgroundStartCreatesNoSession() throws {
    try fixture { f in
      f.manager.startSessionFromBackground(f.profile.id, context: f.context)
      XCTAssertNil(f.manager.activeSession)
      XCTAssertNil(SharedData.activeStrategySharedSession)
      XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfileSession>()), 0)
    }
  }

  func testI2UnpaidScheduleCreatesNoSession() throws {
    try fixture { f in
      ScheduleTimerActivity(appBlocker: f.blocker).start(
        for: BlockedProfiles.getSnapshot(for: f.profile))
      XCTAssertNil(SharedData.activeScheduleSharedSession)
      XCTAssertFalse(f.plans.contains { $0 != nil })
    }
  }
  func testI1NewSharedReaderSeesTheSameVerifiedDeadline() throws {
    try fixture { f in
      f.paid()
      let second = SharedData.Runtime(
        defaults: UserDefaults(suiteName: f.name)!, signingKey: f.key,
        now: { f.clock.now }, calendar: f.calendar)
      SharedData.$runtime.withValue(second) {
        XCTAssertEqual(SharedData.effectiveSubscriptionTier, .premium)
        XCTAssertEqual(SharedData.subscriptionAccessEnd, f.clock.now.addingTimeInterval(1800))
        f.clock.now = f.clock.now.addingTimeInterval(1800)
        XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free)
      }
    }
  }

  func testI1CorruptSnapshotDoesNotFallBackToPremiumFlag() throws {
    try fixture { f in
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free)
      f.paid()
      SharedData.subscriptionTier = .premium
      SharedData.subscriptionExpirationDate = f.clock.now.addingTimeInterval(86400)
      f.defaults.set(Data("damaged".utf8), forKey: "subscriptionGrants")
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free)
      XCTAssertNil(SharedData.subscriptionAccessEnd)
    }
  }

  func testI2UnpaidDeepLinkAndDirectNFCStartCreateNoSession() throws {
    try fixture { f in
      f.manager.toggleSessionFromDeeplink(
        f.profile.id.uuidString, url: URL(string: "docard://start")!, context: f.context)
      _ = NFCBlockingStrategy(
        nfcScanner: f.scanner, appBlocker: f.blocker
      )
      .startBlocking(context: f.context, profile: f.profile, forceStart: false)
      XCTAssertNil(SharedData.activeStrategySharedSession)
      XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfileSession>()), 0)
      XCTAssertFalse(f.plans.contains { $0 != nil })
    }
  }

  func testI3NFCCompletionAfterExpiryCannotStart() throws {
    try fixture { f in
      f.paid()
      f.manager.startSessionWithNFCScan(context: f.context, profile: f.profile)
      XCTAssertTrue(f.manager.isNFCScanInProgress)
      f.clock.now = f.clock.now.addingTimeInterval(1800)
      f.scanner.read()
      XCTAssertNil(f.manager.activeSession)
      XCTAssertFalse(f.manager.isNFCScanInProgress)
      XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfileSession>()), 0)
      XCTAssertFalse(f.plans.contains { $0 != nil })
    }
  }

  func testI3SelectionSaveRechecksAccessAndPreservesData() throws {
    try fixture { f in
      f.paid()
      try BlockedProfiles.updateProfile(f.profile, in: f.context, name: "Saved work")
      f.clock.now = f.clock.now.addingTimeInterval(1800)
      XCTAssertThrowsError(
        try BlockedProfiles.updateProfile(
          f.profile, in: f.context,
          name: "Must not save", domains: ["changed.test"]))
      XCTAssertThrowsError(try BlockedProfiles.createProfile(in: f.context, name: "Denied"))
      XCTAssertThrowsError(
        try BlockedProfiles.cloneProfile(f.profile, in: f.context, newName: "Denied copy"))
      XCTAssertEqual(f.profile.name, "Saved work")
      XCTAssertEqual(f.profile.domains, ["example.test"])
      XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfiles>()), 1)
    }
  }

  func testI4ExpiryEndsManualAndScheduledSessionsOnlyOnce() throws {
    for scheduled in [false, true] {
      try fixture { f in
        f.paid()
        if scheduled {
          ScheduleTimerActivity(appBlocker: f.blocker).start(
            for: BlockedProfiles.getSnapshot(for: f.profile))
          f.manager.loadActiveSession(context: f.context)
        } else {
          f.manager.forceStartSession(context: f.context, profile: f.profile)
        }
        let row = try XCTUnwrap(f.manager.activeSession)
        f.clock.now = f.clock.now.addingTimeInterval(2400)
        f.manager.reconcileSubscription(context: f.context)
        let actualEnd = f.clock.now
        XCTAssertEqual(row.endTime, actualEnd)
        XCTAssertEqual(row.endReason, "subscription_access_ended")
        f.clock.now = f.clock.now.addingTimeInterval(60)
        f.manager.reconcileSubscription(context: f.context)
        XCTAssertEqual(row.endTime, actualEnd)
        XCTAssertNil(f.manager.activeSession)
        XCTAssertNil(SharedData.activeStrategySharedSession)
        XCTAssertNil(SharedData.activeScheduleSharedSession)
        XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfileSession>()), 1)
        XCTAssertEqual(f.uses, 3)
        XCTAssertNil(try XCTUnwrap(f.plans.last))
        XCTAssertEqual(f.profile.schedules.count, 1)
        XCTAssertEqual(f.profile.domains, ["example.test"])
      }
    }
  }

  func testI5LateSnapshotAndScheduleCallbackCannotReblock() throws {
    try fixture { f in
      f.paid()
      let activity = ScheduleTimerActivity(appBlocker: f.blocker)
      activity.start(for: BlockedProfiles.getSnapshot(for: f.profile))
      let stale = try XCTUnwrap(SharedData.activeScheduleSharedSession)
      f.manager.loadActiveSession(context: f.context)
      let row = try XCTUnwrap(f.manager.activeSession)
      f.clock.now = f.clock.now.addingTimeInterval(2400)
      f.manager.reconcileSubscription(context: f.context)
      let actualEnd = row.endTime
      f.plans = []
      f.clock.now = f.clock.now.addingTimeInterval(300)
      SharedData.activeScheduleSharedSession = stale
      activity.start(for: BlockedProfiles.getSnapshot(for: f.profile))
      f.manager.loadActiveSession(context: f.context)
      XCTAssertEqual(row.endTime, actualEnd)
      XCTAssertEqual(row.endReason, "subscription_access_ended")
      XCTAssertNil(f.manager.activeSession)
      XCTAssertFalse(f.plans.contains { $0 != nil })
      XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfileSession>()), 1)
    }
  }

  func testI6RenewalResumesOnlyEligibleSchedules() throws {
    for mode in ["enabled", "outside", "disabled", "manual-stop"] {
      try fixture { f in
        if mode == "outside" { f.clock.now = f.clock.now.addingTimeInterval(10 * 3600) }
        if mode == "disabled" { f.profile.schedules[0].days = [] }
        f.publish()
        if mode == "manual-stop" {
          SharedData.writeCardTapSuppressionFlags(
            for: BlockedProfiles.getSnapshot(for: f.profile), triggerSource: "scheduled",
            endReason: "card_tap")
        }
        f.manager.reconcileSubscription(context: f.context)
        f.paid(until: 3600)
        f.manager.reconcileSubscription(context: f.context)
        XCTAssertEqual(SharedData.activeScheduleSharedSession != nil, mode == "enabled", mode)
        XCTAssertEqual(f.plans.contains { $0 != nil }, mode == "enabled", mode)
      }
    }
  }

  func testI6StaleExpiryEventAfterRenewalDoesNotStopAccess() throws {
    try fixture { f in
      f.paid()
      f.manager.forceStartSession(context: f.context, profile: f.profile)
      let id = f.manager.activeSession?.id
      f.clock.now = f.clock.now.addingTimeInterval(1800)
      f.paid(until: 3600)
      XCTAssertFalse(SubscriptionExpiry.enforce(blocker: f.blocker))
      XCTAssertEqual(f.manager.activeSession?.id, id)
      XCTAssertTrue(f.manager.isBlocking)
    }
  }

  func testI6EndedManualSessionRequiresNewCardTapAfterRenewal() throws {
    try fixture { f in
      f.profile.schedules = []
      f.publish()
      f.paid()
      f.manager.forceStartSession(context: f.context, profile: f.profile)
      let oldID = try XCTUnwrap(f.manager.activeSession?.id)
      f.clock.now = f.clock.now.addingTimeInterval(1800)
      f.manager.reconcileSubscription(context: f.context)
      f.paid(until: 3600)
      f.manager.reconcileSubscription(context: f.context)
      XCTAssertNil(f.manager.activeSession)
      XCTAssertNil(SharedData.activeStrategySharedSession)
      f.manager.startSessionWithNFCScan(context: f.context, profile: f.profile)
      f.scanner.read()
      XCTAssertTrue(f.manager.isBlocking)
      XCTAssertNotEqual(f.manager.activeSession?.id, oldID)
    }
  }

  func testI8ActualRemovalTimeBreakAndRenewedSessionReachReports() throws {
    try fixture { f in
      f.paid()
      f.manager.forceStartSession(context: f.context, profile: f.profile)
      let row = try XCTUnwrap(f.manager.activeSession)
      let originalID = row.id
      row.breakStartTime = f.clock.now.addingTimeInterval(600)
      row.breakEndTime = f.clock.now.addingTimeInterval(1200)
      SharedData.setBreakStartTime(date: row.breakStartTime!)
      SharedData.setBreakEndTime(date: row.breakEndTime!)
      f.clock.now = f.clock.now.addingTimeInterval(2400)
      f.manager.reconcileSubscription(context: f.context)
      XCTAssertEqual(row.endTime, f.clock.now)
      XCTAssertEqual(row.endReason, "subscription_access_ended")
      let report = ReportViewModel(calendar: f.calendar, now: { f.clock.now })
      report.load(context: f.context, isPremium: true)
      XCTAssertEqual(report.totalBlockDuration, 1800)
      XCTAssertEqual(report.sessionCount, 1)
      f.clock.now = f.clock.now.addingTimeInterval(1200)
      f.paid(until: 3600)
      f.manager.reconcileSubscription(context: f.context)
      f.manager.loadActiveSession(context: f.context)
      XCTAssertNotEqual(f.manager.activeSession?.id, originalID)
      XCTAssertEqual(f.manager.activeSession?.triggerSource, "scheduled")
      XCTAssertEqual(try f.context.fetchCount(FetchDescriptor<BlockedProfileSession>()), 2)
      XCTAssertEqual(f.profile.domains, ["example.test"])
    }
  }

  func testB6ProductionWriterReceivesChangedModeAndExpiryClear() throws {
    try fixture { f in
      f.paid()
      f.blocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: f.profile))
      f.profile.enableAllowMode = false
      f.profile.enableSafariBlocking = false
      f.profile.domains = ["new.test"]
      f.blocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: f.profile))
      XCTAssertEqual(f.plans.count, 2)
      XCTAssertEqual(f.plans[0]?.allowOnlyApps, true)
      XCTAssertEqual(f.plans[1]?.allowOnlyApps, false)
      XCTAssertEqual(f.plans[1]?.browserEnabled, false)
      XCTAssertEqual(f.plans[1]?.customDomains, ["new.test"])
      f.clock.now = f.clock.now.addingTimeInterval(1800)
      f.blocker.activateRestrictions(for: BlockedProfiles.getSnapshot(for: f.profile))
      XCTAssertEqual(f.plans.count, 3)
      XCTAssertNil(f.plans[2])
    }
  }

  func testI8ExpiryHistoryAndSettingsSurviveFileStoreReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "AccessReopen-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("history.store")
    var sessionID = ""
    var endedAt = Date.distantPast
    do {
      let f = try AccessFixture(storeURL: url)
      defer { f.cleanup() }
      try SharedData.$runtime.withValue(f.runtime) {
        f.paid()
        f.publish()
        f.manager.forceStartSession(context: f.context, profile: f.profile)
        sessionID = try XCTUnwrap(f.manager.activeSession?.id)
        f.clock.now = f.clock.now.addingTimeInterval(2400)
        endedAt = f.clock.now
        f.manager.reconcileSubscription(context: f.context)
        try f.context.save()
      }
    }
    let reopened = try AppModelStore.open(
      configuration: ModelConfiguration(
        schema: Schema(versionedSchema: AppSchemaV5.self), url: url, cloudKitDatabase: .none))
    let rows = try reopened.mainContext.fetch(FetchDescriptor<BlockedProfileSession>())
    let row = try XCTUnwrap(rows.first)
    XCTAssertEqual(rows.count, 1)
    XCTAssertEqual(row.id, sessionID)
    XCTAssertEqual(row.endTime, endedAt)
    XCTAssertEqual(row.endReason, "subscription_access_ended")
    XCTAssertEqual(row.blockedProfile.name, "Work")
    XCTAssertEqual(row.blockedProfile.domains, ["example.test"])
    XCTAssertEqual(row.blockedProfile.schedules.count, 1)
    XCTAssertEqual(row.blockedProfile.sessions.map(\.id), [sessionID])
  }

  func testI5LateCardCallbackCannotChangeExpiryHistoryOrClearRenewedBlocking() throws {
    try fixture { f in
      f.paid()
      f.manager.forceStartSession(context: f.context, profile: f.profile)
      let row = try XCTUnwrap(f.manager.activeSession)
      let strategy = NFCBlockingStrategy(
        nfcScanner: f.scanner, appBlocker: f.blocker)
      _ = strategy.stopBlocking(context: f.context, session: row)
      f.clock.now = f.clock.now.addingTimeInterval(2400)
      f.manager.reconcileSubscription(context: f.context)
      let actualEnd = row.endTime
      f.paid(until: 3600)
      f.manager.reconcileSubscription(context: f.context)
      f.manager.loadActiveSession(context: f.context)
      let renewedID = try XCTUnwrap(f.manager.activeSession?.id)
      f.plans = []
      f.clock.now = f.clock.now.addingTimeInterval(60)
      f.scanner.read()
      XCTAssertEqual(row.endTime, actualEnd)
      XCTAssertEqual(row.endReason, "subscription_access_ended")
      XCTAssertEqual(f.manager.activeSession?.id, renewedID)
      XCTAssertTrue(f.plans.isEmpty)
    }
  }

  func testA5ExpiryMonitorCoversTheDayAndPreservesDeadlineTimezone() throws {
    let f = try AccessFixture()
    defer { f.cleanup() }
    for (hour, minute, second, startHour, startMinute, startSecond) in [
      (14, 0, 0, 14, 0, 1), (0, 0, 0, 0, 0, 1), (23, 59, 59, 0, 0, 0),
    ] {
      let end = f.calendar.date(
        from: DateComponents(
          year: 2026, month: 12, day: 1, hour: hour, minute: minute, second: second))!
      let schedule = SubscriptionExpiry.monitorSchedule(until: end, calendar: f.calendar)
      XCTAssertTrue(schedule.repeats)
      XCTAssertEqual(schedule.intervalStart.hour, startHour)
      XCTAssertEqual(schedule.intervalStart.minute, startMinute)
      XCTAssertEqual(schedule.intervalStart.second, startSecond)
      XCTAssertEqual(schedule.intervalEnd.hour, hour)
      XCTAssertEqual(schedule.intervalEnd.minute, minute)
      XCTAssertEqual(schedule.intervalEnd.second, second)
      XCTAssertEqual(schedule.intervalEnd.timeZone, f.calendar.timeZone)
      XCTAssertNil(schedule.intervalStart.year)
      XCTAssertNil(schedule.intervalEnd.year)
    }
  }

  func testI8ScheduledExpiryPreservesSavedBreaks() throws {
    for openBreak in [false, true] {
      for backgroundCleanup in [false, true] {
        try fixture { f in
          f.paid()
          ScheduleTimerActivity(appBlocker: f.blocker).start(
            for: BlockedProfiles.getSnapshot(for: f.profile))
          f.manager.loadActiveSession(context: f.context)
          let row = try XCTUnwrap(f.manager.activeSession)
          let breakStart = f.clock.now.addingTimeInterval(600)
          let breakEnd = openBreak ? nil : f.clock.now.addingTimeInterval(1200)
          row.breakStartTime = breakStart
          row.breakEndTime = breakEnd
          try f.context.save()
          f.clock.now = f.clock.now.addingTimeInterval(2400)
          let removalTime = f.clock.now
          if backgroundCleanup {
            XCTAssertTrue(SubscriptionExpiry.enforce(blocker: f.blocker))
            f.clock.now = f.clock.now.addingTimeInterval(300)
          }
          f.manager.reconcileSubscription(context: f.context)
          XCTAssertEqual(row.breakStartTime, breakStart)
          XCTAssertEqual(row.breakEndTime, breakEnd ?? removalTime)
          XCTAssertEqual(row.endTime, removalTime)
          let report = ReportViewModel(calendar: f.calendar, now: { f.clock.now })
          report.load(context: f.context, isPremium: true)
          XCTAssertEqual(report.totalBlockDuration, openBreak ? 600 : 1800)
          f.manager.reconcileSubscription(context: f.context)
          XCTAssertEqual(row.breakStartTime, breakStart)
          XCTAssertEqual(row.breakEndTime, breakEnd ?? removalTime)
          XCTAssertEqual(row.endTime, removalTime)
        }
      }
    }
  }

  func testI1UnsignedGrantIsRejectedWithoutLegacyFallback() throws {
    try fixture { f in
      SharedData.subscriptionTier = .premium
      SharedData.subscriptionExpirationDate = f.clock.now.addingTimeInterval(86400)
      let grant = SubscriptionGrant(
        productID: SubscriptionProduct.monthly, purchasedAt: f.clock.now,
        expiresAt: f.clock.now.addingTimeInterval(3600))
      f.defaults.set(try JSONEncoder().encode([grant]), forKey: "subscriptionGrants")
      XCTAssertEqual(SharedData.effectiveSubscriptionTier, .free)
      XCTAssertNil(SharedData.subscriptionAccessEnd)
      XCTAssertNil(f.defaults.data(forKey: "subscriptionGrants.hmac"))
    }
  }

}
