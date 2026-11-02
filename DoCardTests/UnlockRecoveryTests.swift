import CryptoKit
import Foundation
import SwiftData
import XCTest

@testable import DoCard

private final class RecoveryClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date

  init(_ value: Date) { self.value = value }

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

private final class RecordingBlocker: AppBlockerUtil {
  enum Request: Equatable {
    case block(UUID)
    case unblock
  }

  var requests: [Request] = []
  var onUnblock: (() -> Void)?

  override func activateRestrictions(for profile: SharedData.ProfileSnapshot) {
    requests.append(.block(profile.id))
  }

  override func deactivateRestrictions() {
    requests.append(.unblock)
    onUnblock?()
  }
}

/// Only the hardware read is replaced. Pair validation and callback delivery are production code.
private final class ScriptedScanner: NFCScannerUtil {
  var scans = 0
  var invalidations: [String?] = []

  override func scan(profileName: String, isUnlocking: Bool = false) { scans += 1 }

  func read(id: String = "paired-card") {
    deliverReadResult(
      NFCResult(id: id, payload: "valid-do-card-payload", DateScanned: SharedData.currentDate),
      expectedIds: expectedTagIds,
      invalidate: { self.invalidations.append($0) })
  }

  func cancel() { onCancel?() }
}

@MainActor
private final class RecoveryFixture {
  let suiteName = "UnlockRecoveryTests.\(UUID().uuidString)"
  let defaults: UserDefaults
  let clock: RecoveryClock
  let calendar: Calendar
  let key = SymmetricKey(size: .bits256)
  let container: ModelContainer
  let context: ModelContext
  let blocker = RecordingBlocker()
  let scanner = ScriptedScanner()
  let profile: BlockedProfiles
  var emergencyUses = 3
  var manager: StrategyManager!

  init() throws {
    defaults = UserDefaults(suiteName: suiteName)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Taipei")!
    self.calendar = calendar
    clock = RecoveryClock(
      calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!)
    let schema = Schema([
      BlockedProfiles.self, BlockedProfileSession.self, NFCTapEvent.self, EmergencyUnlockEvent.self,
    ])
    container = try ModelContainer(
      for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    context = ModelContext(container)
    context.autosaveEnabled = false
    profile = BlockedProfiles(
      name: "Recovery fixture", enableAllowMode: true, physicalUnblockNFCTagIds: ["paired-card"],
      schedules: [
        BlockedProfileSchedule(
          days: [.monday], startHour: 9, startMinute: 0, endHour: 10, endMinute: 0)
      ])
    context.insert(profile)
    manager = makeManager()
  }

  var runtime: SharedData.Runtime {
    let clock = clock
    return SharedData.Runtime(
      defaults: defaults, signingKey: key, now: { clock.now }, calendar: calendar)
  }

  func date(day: Int = 2, hour: Int, minute: Int = 0) -> Date {
    calendar.date(
      from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
  }

  func makeManager() -> StrategyManager {
    StrategyManager(
      appBlocker: blocker,
      makeStrategy: { [unowned self] id in
        if id == ManualBlockingStrategy.id {
          return ManualBlockingStrategy(appBlocker: self.blocker)
        }
        return NFCBlockingStrategy(
          nfcScanner: self.scanner, appBlocker: self.blocker)
      },
      makeNFCScanner: { [unowned self] in self.scanner },
      systemEffect: { _ in },
      readEmergencyUses: { [unowned self] in self.emergencyUses },
      writeEmergencyUses: { [unowned self] in self.emergencyUses = $0 })
  }

  var activity: ScheduleTimerActivity {
    ScheduleTimerActivity(appBlocker: blocker)
  }

  @discardableResult
  func startScheduled() throws -> BlockedProfileSession {
    BlockedProfiles.updateSnapshot(for: profile)
    SharedData.createSessionForSchedular(for: profile.id)
    manager.loadActiveSession(context: context)
    try context.save()
    blocker.requests = []
    return try XCTUnwrap(manager.activeSession)
  }

  func unlockByCard() {
    manager.toggleBlocking(context: context, activeProfile: profile)
    scanner.read()
  }

  func cleanup() {
    manager.stopTimer()
    defaults.removePersistentDomain(forName: suiteName)
  }
}

@MainActor
final class UnlockRecoveryTests: XCTestCase {
  private func withFixture(_ body: (RecoveryFixture) throws -> Void) throws {
    let fixture = try RecoveryFixture()
    defer { fixture.cleanup() }
    try SharedData.$runtime.withValue(fixture.runtime) {
      SharedData.subscriptionGrants = [SubscriptionGrant(productID: SubscriptionProduct.monthly,
        purchasedAt: fixture.date(day: 1, hour: 0), expiresAt: fixture.date(day: 10, hour: 0))]
      try body(fixture)
    }
  }

  func testU5ManualCardStartAndStopSavesHistory() throws {
    try withFixture { fixture in
      fixture.profile.schedules = []
      fixture.manager.startSessionWithNFCScan(context: fixture.context, profile: fixture.profile)
      XCTAssertEqual(fixture.scanner.scans, 1)
      XCTAssertNil(fixture.manager.activeSession)
      fixture.scanner.read()
      let session = try XCTUnwrap(fixture.manager.activeSession)
      XCTAssertEqual(fixture.blocker.requests, [.block(fixture.profile.id)])
      XCTAssertEqual(session.triggerSource, "manual")
      fixture.clock.now = fixture.date(hour: 9, minute: 5)
      fixture.manager.toggleBlocking(context: fixture.context, activeProfile: fixture.profile)
      XCTAssertTrue(session.isActive)
      fixture.scanner.read()
      try fixture.context.save()
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
      XCTAssertEqual(fixture.blocker.requests.last, .unblock)
      let reopened = ModelContext(fixture.container)
      let rows = try reopened.fetch(FetchDescriptor<BlockedProfileSession>())
      XCTAssertEqual(rows.count, 1)
      XCTAssertEqual(rows.first?.endReason, "card_tap")
      XCTAssertEqual(rows.first?.endTime, fixture.clock.now)
    }
  }

  func testU1CardUnlockEndsScheduledSession() throws {
    try withFixture { fixture in
      let session = try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      fixture.unlockByCard()

      XCTAssertEqual(session.endReason, "card_tap")
      XCTAssertEqual(session.endTime, fixture.clock.now)
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertFalse(fixture.manager.isBlocking)
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
      XCTAssertNil(SharedData.getActiveScheduleSharedSession())
    }
  }

  func testU2EmergencyUnlockEndsScheduledSessionOnce() throws {
    try withFixture { fixture in
      let session = try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      fixture.manager.emergencyUnblock(context: fixture.context)

      XCTAssertEqual(session.endReason, "emergency_unlock")
      XCTAssertEqual(session.endTime, fixture.clock.now)
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertFalse(fixture.manager.isBlocking)
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
      XCTAssertEqual(fixture.emergencyUses, 2)
      let events = try fixture.context.fetch(FetchDescriptor<EmergencyUnlockEvent>())
      XCTAssertEqual(events.count, 1)
      XCTAssertEqual(events.first?.sessionId, session.id)
    }
  }

  func testU3CancelKeepsSessionActiveAndAllowsRetry() throws {
    try withFixture { fixture in
      let session = try fixture.startScheduled()
      fixture.manager.toggleBlocking(context: fixture.context, activeProfile: fixture.profile)
      fixture.scanner.cancel()
      XCTAssertTrue(session.isActive)
      XCTAssertTrue(fixture.manager.isBlocking)
      XCTAssertTrue(fixture.blocker.requests.isEmpty)
      fixture.unlockByCard()
      XCTAssertEqual(fixture.scanner.scans, 2)
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertFalse(fixture.manager.isBlocking)
    }
  }

  func testU4WrongCardKeepsSessionActiveThenValidCardUnlocks() throws {
    try withFixture { fixture in
      let session = try fixture.startScheduled()
      fixture.manager.toggleBlocking(context: fixture.context, activeProfile: fixture.profile)
      fixture.scanner.read(id: "wrong-card")
      XCTAssertTrue(session.isActive)
      XCTAssertTrue(fixture.manager.isBlocking)
      XCTAssertTrue(fixture.blocker.requests.isEmpty)
      XCTAssertEqual(fixture.scanner.invalidations.count, 1)
      XCTAssertNotNil(fixture.scanner.invalidations.first ?? nil)
      fixture.unlockByCard()
      XCTAssertEqual(fixture.scanner.scans, 2)
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertFalse(fixture.manager.isBlocking)
    }
  }

  private enum UnlockMethod {
    case card
    case emergency
  }

  private func unlock(_ fixture: RecoveryFixture, using method: UnlockMethod) {
    switch method {
    case .card: fixture.unlockByCard()
    case .emergency: fixture.manager.emergencyUnblock(context: fixture.context)
    }
  }

  private func checkForegroundRecovery(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      unlock(fixture, using: method)
      fixture.manager.loadActiveSession(context: fixture.context)
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
      XCTAssertNil(SharedData.getActiveScheduleSharedSession())
    }
  }

  private func checkRepeatedStartEvent(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      unlock(fixture, using: method)
      fixture.activity.start(for: BlockedProfiles.getSnapshot(for: fixture.profile))
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertNil(SharedData.getActiveScheduleSharedSession())
    }
  }

  private func checkRecreatedCoordinator(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      unlock(fixture, using: method)
      let reopenedDefaults = UserDefaults(suiteName: fixture.suiteName)!
      let clock = fixture.clock
      let reopenedRuntime = SharedData.Runtime(
        defaults: reopenedDefaults, signingKey: fixture.key, now: { clock.now },
        calendar: fixture.calendar)
      let reopenedContext = ModelContext(fixture.container)
      reopenedContext.autosaveEnabled = false
      let newManager = fixture.makeManager()
      SharedData.$runtime.withValue(reopenedRuntime) {
        newManager.loadActiveSession(context: reopenedContext)
        XCTAssertFalse(newManager.activeSessionStatus.isBlocking)
        XCTAssertNil(SharedData.getActiveScheduleSharedSession())
      }
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertEqual(try reopenedContext.fetch(FetchDescriptor<BlockedProfileSession>()).count, 1)
    }
  }

  private func checkOvernightRecovery(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      fixture.profile.schedules = [
        BlockedProfileSchedule(
          days: [.monday], startHour: 22, startMinute: 40, endHour: 6, endMinute: 0, isNextDay: true
        )
      ]
      fixture.clock.now = fixture.date(hour: 22, minute: 40)
      try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 23, minute: 30)
      unlock(fixture, using: method)
      fixture.clock.now = fixture.date(day: 3, hour: 0, minute: 10)
      fixture.manager.loadActiveSession(context: fixture.context)
      fixture.activity.start(for: BlockedProfiles.getSnapshot(for: fixture.profile))
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
      XCTAssertNil(SharedData.getActiveScheduleSharedSession())
    }
  }

  private func checkProtectionBeforeStopCallback(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      var checkedDuringStop = false
      fixture.blocker.onUnblock = {
        MainActor.assumeIsolated {
          checkedDuringStop = true
          XCTAssertFalse(
            SharedData.isScheduleCurrentlyActiveAndUnsuppressed(
              profile: BlockedProfiles.getSnapshot(for: fixture.profile)),
            "R5: the user's stop must be recorded before recovery can run")
          // Re-enter the real schedule-start handler while the stop path is still executing.
          fixture.activity.start(for: BlockedProfiles.getSnapshot(for: fixture.profile))
        }
      }
      defer { fixture.blocker.onUnblock = nil }
      unlock(fixture, using: method)
      XCTAssertTrue(checkedDuringStop)
      XCTAssertEqual(
        fixture.blocker.requests, [.unblock], "R5: no block request during stop callbacks")
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
    }
  }

  private func checkRepeatedRecovery(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      let session = try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      unlock(fixture, using: method)
      let originalEnd = session.endTime
      for minute in 31...35 {
        fixture.clock.now = fixture.date(hour: 9, minute: minute)
        fixture.manager.loadActiveSession(context: fixture.context)
        fixture.manager.restoreScheduledSessionIfNeeded()
        fixture.activity.start(for: BlockedProfiles.getSnapshot(for: fixture.profile))
      }
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertEqual(session.endTime, originalEnd)
      XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<BlockedProfileSession>()).count, 1)
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
    }
  }

  func testR7RepeatedEmergencyUnlockDoesNotSpendAnotherUse() throws {
    try withFixture { fixture in
      try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      fixture.manager.emergencyUnblock(context: fixture.context)
      fixture.manager.emergencyUnblock(context: fixture.context)
      fixture.manager.emergencyUnblock(context: fixture.context)
      XCTAssertEqual(fixture.emergencyUses, 2)
      XCTAssertEqual(try fixture.context.fetch(FetchDescriptor<EmergencyUnlockEvent>()).count, 1)
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
    }
  }

  private func checkNextWindow(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      let ended = try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      unlock(fixture, using: method)
      fixture.blocker.requests = []
      fixture.clock.now = fixture.date(day: 9, hour: 9)
      fixture.activity.start(for: BlockedProfiles.getSnapshot(for: fixture.profile))
      fixture.manager.loadActiveSession(context: fixture.context)
      XCTAssertTrue(fixture.blocker.requests.contains(.block(fixture.profile.id)))
      XCTAssertFalse(fixture.blocker.requests.contains(.unblock))
      let active = try XCTUnwrap(fixture.manager.activeSession)
      XCTAssertNotEqual(active.id, ended.id)
      XCTAssertEqual(active.startTime, fixture.clock.now)
      XCTAssertEqual(active.triggerSource, "scheduled")
      XCTAssertTrue(fixture.manager.activeSessionStatus.isBlocking)
    }
  }

  func testR9StillActiveSessionRestoresBlocking() throws {
    try withFixture { fixture in
      let session = try fixture.startScheduled()
      let originalStart = session.startTime
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      let newManager = fixture.makeManager()
      newManager.loadActiveSession(context: ModelContext(fixture.container))
      XCTAssertEqual(fixture.blocker.requests, [.block(fixture.profile.id)])
      XCTAssertEqual(newManager.activeSession?.id, session.id)
      XCTAssertEqual(newManager.activeSession?.startTime, originalStart)
      XCTAssertTrue(newManager.activeSessionStatus.isBlocking)
    }
  }

  func testR10ExpiredFixedTimeSessionDoesNotReblock() throws {
    try withFixture { fixture in
      let session = try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 10, minute: 10)
      fixture.manager.loadActiveSession(context: fixture.context)
      XCTAssertEqual(fixture.blocker.requests, [.unblock])
      XCTAssertFalse(session.isActive)
      XCTAssertFalse(fixture.manager.activeSessionStatus.isBlocking)
      XCTAssertNil(SharedData.getActiveScheduleSharedSession())
    }
  }

  private func checkManualOwnership(timer: Bool, differentProfile: Bool) throws {
    try withFixture { fixture in
      fixture.profile.blockingStrategyId =
        timer ? NFCTimerBlockingStrategy.id : NFCBlockingStrategy.id
      BlockedProfiles.updateSnapshot(for: fixture.profile)
      let session = BlockedProfileSession.createSession(
        in: fixture.context, withTag: fixture.profile.blockingStrategyId!,
        withProfile: fixture.profile,
        triggerSource: "manual", plannedDurationMinutes: timer ? 60 : nil)
      fixture.manager.activeSession = session
      try fixture.context.save()
      let originalStart = session.startTime
      let scheduledProfile: BlockedProfiles
      if differentProfile {
        scheduledProfile = BlockedProfiles(
          name: "Other scheduled profile", enableAllowMode: true,
          schedules: fixture.profile.schedules)
        fixture.context.insert(scheduledProfile)
        BlockedProfiles.updateSnapshot(for: scheduledProfile)
      } else {
        scheduledProfile = fixture.profile
      }
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      fixture.activity.start(for: BlockedProfiles.getSnapshot(for: scheduledProfile))
      fixture.manager.restoreScheduledSessionIfNeeded()
      XCTAssertTrue(
        fixture.blocker.requests.isEmpty, "Schedule must not take over the manual session")
      XCTAssertNil(SharedData.getActiveScheduleSharedSession())
      fixture.manager.loadActiveSession(context: fixture.context)
      XCTAssertEqual(fixture.blocker.requests, [.block(fixture.profile.id)])
      XCTAssertEqual(fixture.manager.activeSession?.id, session.id)
      XCTAssertEqual(fixture.manager.activeSession?.startTime, originalStart)
      XCTAssertEqual(SharedData.getActiveStrategySharedSession()?.id, session.id)
    }
  }

  private func checkExplicitRestart(_ method: UnlockMethod) throws {
    try withFixture { fixture in
      let ended = try fixture.startScheduled()
      fixture.clock.now = fixture.date(hour: 9, minute: 30)
      unlock(fixture, using: method)
      fixture.manager.toggleBlocking(context: fixture.context, activeProfile: fixture.profile)
      let active = try XCTUnwrap(fixture.manager.activeSession)
      XCTAssertNotEqual(active.id, ended.id)
      XCTAssertTrue(active.isActive)
      XCTAssertEqual(active.triggerSource, "manual")
      XCTAssertEqual(SharedData.getActiveStrategySharedSession()?.id, active.id)
      XCTAssertEqual(fixture.blocker.requests, [.unblock, .block(fixture.profile.id)])
      XCTAssertNil(SharedData.getActiveScheduleSharedSession())
    }
  }

  func testR1Card() throws { try checkForegroundRecovery(.card) }

  func testR1Emergency() throws { try checkForegroundRecovery(.emergency) }

  func testR2Card() throws { try checkRepeatedStartEvent(.card) }

  func testR2Emergency() throws { try checkRepeatedStartEvent(.emergency) }

  func testR3Card() throws { try checkRecreatedCoordinator(.card) }

  func testR3Emergency() throws { try checkRecreatedCoordinator(.emergency) }

  func testR4Card() throws { try checkOvernightRecovery(.card) }

  func testR4Emergency() throws { try checkOvernightRecovery(.emergency) }

  func testR5Card() throws { try checkProtectionBeforeStopCallback(.card) }

  func testR5Emergency() throws { try checkProtectionBeforeStopCallback(.emergency) }

  func testR6Card() throws { try checkRepeatedRecovery(.card) }

  func testR6Emergency() throws { try checkRepeatedRecovery(.emergency) }

  func testR8Card() throws { try checkNextWindow(.card) }

  func testR8Emergency() throws { try checkNextWindow(.emergency) }

  func testR12Card() throws { try checkExplicitRestart(.card) }

  func testR12Emergency() throws { try checkExplicitRestart(.emergency) }

  func testR11ManualSameProfile() throws {
    try checkManualOwnership(timer: false, differentProfile: false)
  }

  func testR11ManualOtherProfile() throws {
    try checkManualOwnership(timer: false, differentProfile: true)
  }

  func testR11TimerSameProfile() throws {
    try checkManualOwnership(timer: true, differentProfile: false)
  }

  func testR11TimerOtherProfile() throws {
    try checkManualOwnership(timer: true, differentProfile: true)
  }
}
