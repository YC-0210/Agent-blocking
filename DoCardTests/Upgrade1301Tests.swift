import CoreData
import Foundation
import SwiftData
import XCTest

@testable import DoCard

@MainActor
final class Upgrade1301Tests: XCTestCase {
  private struct Checkpoint: Codable {
    let processID: Int32
    let scheduleIDs: [String: UUID]
  }

  /// The local runner calls this once normally, then once with phase=reopen in a new process.
  /// A normal XCTest invocation always starts with a fresh copy and remains independent.
  func testFirstReleaseSavedDataSurvivesUpdate() throws {
    let phase = ProcessInfo.processInfo.environment["DOCARD_UPGRADE_PHASE"] ?? "migrate"
    guard phase == "migrate" || phase == "reopen" else { throw CocoaError(.coderInvalidValue) }
    let bundle = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "Upgrade1301", withExtension: "bundle"))
    let spec = try JSONDecoder().decode(
      Upgrade1301Spec.self, from: Data(contentsOf: bundle.appendingPathComponent("expected.json")))
    XCTAssertEqual(spec.sourceVersion, "1.30.1")
    XCTAssertEqual(spec.sourceBuild, "1")
    let directory = URL.applicationSupportDirectory.appendingPathComponent(
      "DoCardUpgrade1301Tests", isDirectory: true)
    let fm = FileManager.default
    let checkpointURL = directory.appendingPathComponent("reader-checkpoint.json")
    if phase == "migrate" {
      if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
      try fm.createDirectory(
        at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
      try fm.copyItem(at: bundle.appendingPathComponent("Store"), to: directory)
    }
    let storeURL = directory.appendingPathComponent("default.store")
    XCTAssertTrue(
      fm.fileExists(atPath: storeURL.path),
      "Require the old/copied store; never create an empty substitute")
    guard fm.fileExists(atPath: storeURL.path) else { throw CocoaError(.fileNoSuchFile) }
    let previous =
      phase == "reopen"
      ? try JSONDecoder().decode(Checkpoint.self, from: Data(contentsOf: checkpointURL)) : nil
    if let previous {
      XCTAssertNotEqual(
        previous.processID, ProcessInfo.processInfo.processIdentifier,
        "The reopen phase must run in a separate process")
    }
    let configuration = ModelConfiguration(
      schema: Schema(versionedSchema: AppSchemaV5.self), url: storeURL, cloudKitDatabase: .none)
    // Both the real app and this test call this opener. Errors propagate instead of resetting.
    let container = try AppModelStore.open(configuration: configuration)
    let context = ModelContext(container)
    context.autosaveEnabled = false
    BlockedProfiles.migrateSchedulesToArray(in: context)
    try context.save()
    let ids = try verifySavedData(in: context, against: spec)
    if let previous {
      XCTAssertEqual(
        ids, previous.scheduleIDs, "New schedule IDs must stay stable on the next launch")
    } else {
      let checkpoint = Checkpoint(
        processID: ProcessInfo.processInfo.processIdentifier, scheduleIDs: ids)
      try JSONEncoder().encode(checkpoint).write(to: checkpointURL, options: .atomic)
    }
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      ofType: NSSQLiteStoreType, at: storeURL)
    XCTAssertEqual(metadata[NSStoreModelVersionIdentifiersKey] as? [String], ["2.2.0"])
    print(
      "UPGRADE1301_RESULT: phase=\(phase), pid=\(ProcessInfo.processInfo.processIdentifier), profiles=2, schedules=2, sessions=3, schema=2.2.0"
    )
    print("UPGRADE1301_READER_STORE: \(directory.path)")
  }

  private func verifySavedData(in context: ModelContext, against spec: Upgrade1301Spec) throws
    -> [String: UUID]
  {
    let profiles = try context.fetch(FetchDescriptor<BlockedProfiles>())
    let sessions = try context.fetch(FetchDescriptor<BlockedProfileSession>())
    XCTAssertEqual(profiles.count, 2)
    XCTAssertEqual(sessions.count, 3)
    XCTAssertEqual(Set(profiles.map(\.id)), Set(spec.profiles.map(\.id)))
    XCTAssertEqual(Set(sessions.map(\.id)), Set(spec.sessions.map(\.id)))
    var scheduleIDs: [String: UUID] = [:]
    for input in spec.profiles {
      let actual = try XCTUnwrap(profiles.first { $0.id == input.id })
      XCTAssertEqual(actual.name, input.name)
      XCTAssertEqual(actual.order, input.order)
      XCTAssertEqual(actual.createdAt, try Upgrade1301Spec.date(input.createdAt))
      XCTAssertEqual(actual.updatedAt, try Upgrade1301Spec.date(input.updatedAt))
      XCTAssertEqual(actual.blockingStrategyId, input.strategy)
      XCTAssertEqual(actual.strategyData, input.timerJSON.map { Data($0.utf8) })
      XCTAssertEqual(actual.enableLiveActivity, input.enableLiveActivity)
      XCTAssertEqual(actual.reminderTimeInSeconds, input.reminderTimeInSeconds)
      XCTAssertEqual(actual.customReminderMessage, input.customReminderMessage)
      XCTAssertEqual(actual.enableBreaks, input.enableBreaks)
      XCTAssertEqual(actual.breakTimeInMinutes, input.breakTimeInMinutes)
      XCTAssertEqual(actual.enableAllowMode, input.enableAllowMode)
      XCTAssertEqual(actual.enableAllowModeDomains, input.enableAllowModeDomains)
      XCTAssertEqual(actual.enableSafariBlocking, input.enableSafariBlocking)
      XCTAssertEqual(actual.physicalUnblockNFCTagIds, input.cardIds)
      XCTAssertEqual(actual.domains, input.domains)
      XCTAssertTrue(actual.selectedActivity.applicationTokens.isEmpty)
      XCTAssertTrue(actual.selectedActivity.categoryTokens.isEmpty)
      XCTAssertTrue(actual.selectedActivity.webDomainTokens.isEmpty)
      XCTAssertNil(
        actual.schedule, "The old single schedule was moved, not retained for another conversion")
      XCTAssertEqual(
        actual.schedules.count, 1, "Exactly one old schedule per profile; no duplicates")
      let schedule = try XCTUnwrap(actual.schedules.first)
      XCTAssertNotEqual(schedule.id, UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
      XCTAssertEqual(schedule.name, input.schedule.name)
      XCTAssertEqual(schedule.days.map(\.rawValue), input.schedule.days)
      XCTAssertEqual(schedule.startHour, input.schedule.startHour)
      XCTAssertEqual(schedule.startMinute, input.schedule.startMinute)
      XCTAssertEqual(schedule.endHour, input.schedule.endHour)
      XCTAssertEqual(schedule.endMinute, input.schedule.endMinute)
      XCTAssertEqual(schedule.endType.rawValue, input.schedule.endType)
      XCTAssertEqual(schedule.updatedAt, try Upgrade1301Spec.date(input.schedule.updatedAt))
      XCTAssertFalse(schedule.isNextDay)
      scheduleIDs[input.id.uuidString] = schedule.id
      XCTAssertEqual(
        Set(actual.sessions.map(\.id)),
        Set(spec.sessions.filter { $0.profileId == input.id }.map(\.id)))
    }
    XCTAssertEqual(Set(scheduleIDs.values).count, 2, "Each migrated schedule gets its own ID")
    for input in spec.sessions {
      let actual = try XCTUnwrap(sessions.first { $0.id == input.id })
      XCTAssertEqual(actual.blockedProfile.id, input.profileId)
      XCTAssertEqual(actual.tag, input.tag)
      XCTAssertEqual(actual.startTime, try Upgrade1301Spec.date(input.startTime))
      XCTAssertEqual(actual.endTime, try Upgrade1301Spec.date(input.endTime))
      XCTAssertEqual(actual.breakStartTime, try input.breakStartTime.map(Upgrade1301Spec.date))
      XCTAssertEqual(actual.breakEndTime, try input.breakEndTime.map(Upgrade1301Spec.date))
      XCTAssertEqual(actual.forceStarted, input.forceStarted)
      XCTAssertFalse(actual.isActive)
      XCTAssertEqual(
        actual.triggerSource, "manual", "Migration default; not a recovered historical fact")
      XCTAssertNil(actual.endReason, "The old release did not store an end reason")
      XCTAssertEqual(
        actual.duration,
        try Upgrade1301Spec.date(input.endTime).timeIntervalSince(
          Upgrade1301Spec.date(input.startTime)))
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<NFCTapEvent>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<EmergencyUnlockEvent>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<MotivationPhoto>()), 0)
    return scheduleIDs
  }
}
