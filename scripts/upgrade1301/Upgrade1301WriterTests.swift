import CoreData
import Foundation
import SwiftData
import XCTest

@testable import DoCard

@MainActor
final class Upgrade1301WriterTests: XCTestCase {
  func testCreateFirstReleaseSavedData() throws {
    let bundle = try XCTUnwrap(
      Bundle(for: Self.self).url(forResource: "Upgrade1301", withExtension: "bundle"))
    let expectedData = try Data(contentsOf: bundle.appendingPathComponent("expected.json"))
    let spec = try JSONDecoder().decode(Upgrade1301Spec.self, from: expectedData)
    XCTAssertEqual(spec.sourceVersion, "1.30.1")
    let directory = URL.documentsDirectory.appendingPathComponent(
      "Upgrade1301Seed", isDirectory: true)
    let fm = FileManager.default
    if fm.fileExists(atPath: directory.path) { try fm.removeItem(at: directory) }
    try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = directory.appendingPathComponent("default.store")
    // The release used these live types, with NO VersionedSchema or migration plan.
    let schema = Schema([BlockedProfileSession.self, BlockedProfiles.self])
    let config = ModelConfiguration(schema: schema, url: store, cloudKitDatabase: .none)
    let container = try ModelContainer(for: schema, configurations: config)
    let context = ModelContext(container)
    context.autosaveEnabled = false
    for input in spec.profiles {
      let schedule = BlockedProfileSchedule(
        name: input.schedule.name,
        days: try input.schedule.days.map { try XCTUnwrap(Weekday(rawValue: $0)) },
        startHour: input.schedule.startHour, startMinute: input.schedule.startMinute,
        endHour: input.schedule.endHour, endMinute: input.schedule.endMinute,
        endType: try XCTUnwrap(ScheduleEndType(rawValue: input.schedule.endType)),
        updatedAt: try Upgrade1301Spec.date(input.schedule.updatedAt))
      let profile = BlockedProfiles(
        id: input.id, name: input.name,
        createdAt: try Upgrade1301Spec.date(input.createdAt),
        updatedAt: try Upgrade1301Spec.date(input.updatedAt),
        blockingStrategyId: input.strategy, strategyData: input.timerJSON.map { Data($0.utf8) },
        enableLiveActivity: input.enableLiveActivity,
        reminderTimeInSeconds: input.reminderTimeInSeconds,
        customReminderMessage: input.customReminderMessage, enableBreaks: input.enableBreaks,
        breakTimeInMinutes: input.breakTimeInMinutes, enableAllowMode: input.enableAllowMode,
        enableAllowModeDomains: input.enableAllowModeDomains,
        enableSafariBlocking: input.enableSafariBlocking,
        order: input.order, domains: input.domains, physicalUnblockNFCTagIds: input.cardIds,
        schedule: schedule)
      context.insert(profile)
      for value in spec.sessions where value.profileId == input.id {
        let session = BlockedProfileSession(
          tag: value.tag, blockedProfile: profile, forceStarted: value.forceStarted)
        session.id = value.id
        session.startTime = try Upgrade1301Spec.date(value.startTime)
        session.endTime = try Upgrade1301Spec.date(value.endTime)
        session.breakStartTime = try value.breakStartTime.map(Upgrade1301Spec.date)
        session.breakEndTime = try value.breakEndTime.map(Upgrade1301Spec.date)
        context.insert(session)
      }
    }
    try context.save()
    let reader = ModelContext(container)
    let profiles = try reader.fetch(FetchDescriptor<BlockedProfiles>())
    let sessions = try reader.fetch(FetchDescriptor<BlockedProfileSession>())
    XCTAssertEqual(profiles.count, 2)
    XCTAssertEqual(sessions.count, 3)
    for expected in spec.profiles {
      let actual = try XCTUnwrap(profiles.first { $0.id == expected.id })
      XCTAssertEqual(actual.name, expected.name)
      XCTAssertEqual(actual.order, expected.order)
      XCTAssertEqual(actual.createdAt, try Upgrade1301Spec.date(expected.createdAt))
      XCTAssertEqual(actual.updatedAt, try Upgrade1301Spec.date(expected.updatedAt))
      XCTAssertEqual(actual.blockingStrategyId, expected.strategy)
      XCTAssertEqual(actual.strategyData, expected.timerJSON.map { Data($0.utf8) })
      XCTAssertEqual(actual.enableLiveActivity, expected.enableLiveActivity)
      XCTAssertEqual(actual.reminderTimeInSeconds, expected.reminderTimeInSeconds)
      XCTAssertEqual(actual.customReminderMessage, expected.customReminderMessage)
      XCTAssertEqual(actual.enableBreaks, expected.enableBreaks)
      XCTAssertEqual(actual.breakTimeInMinutes, expected.breakTimeInMinutes)
      XCTAssertEqual(actual.enableAllowMode, expected.enableAllowMode)
      XCTAssertEqual(actual.enableAllowModeDomains, expected.enableAllowModeDomains)
      XCTAssertEqual(actual.enableSafariBlocking, expected.enableSafariBlocking)
      XCTAssertEqual(actual.physicalUnblockNFCTagIds, expected.cardIds)
      XCTAssertEqual(actual.domains, expected.domains)
      XCTAssertTrue(actual.selectedActivity.applicationTokens.isEmpty)
      XCTAssertTrue(actual.selectedActivity.categoryTokens.isEmpty)
      XCTAssertTrue(actual.selectedActivity.webDomainTokens.isEmpty)
      XCTAssertEqual(actual.schedule?.days.map(\.rawValue), expected.schedule.days)
      XCTAssertEqual(actual.schedule?.endType.rawValue, expected.schedule.endType)
      XCTAssertEqual(actual.schedule?.name, expected.schedule.name)
      XCTAssertEqual(actual.schedule?.startHour, expected.schedule.startHour)
      XCTAssertEqual(actual.schedule?.startMinute, expected.schedule.startMinute)
      XCTAssertEqual(actual.schedule?.endHour, expected.schedule.endHour)
      XCTAssertEqual(actual.schedule?.endMinute, expected.schedule.endMinute)
      XCTAssertEqual(
        actual.schedule?.updatedAt, try Upgrade1301Spec.date(expected.schedule.updatedAt))
      XCTAssertEqual(
        Set(actual.sessions.map(\.id)),
        Set(spec.sessions.filter { $0.profileId == expected.id }.map(\.id)))
    }
    for expected in spec.sessions {
      let actual = try XCTUnwrap(sessions.first { $0.id == expected.id })
      XCTAssertEqual(actual.blockedProfile.id, expected.profileId)
      XCTAssertEqual(actual.tag, expected.tag)
      XCTAssertEqual(actual.startTime, try Upgrade1301Spec.date(expected.startTime))
      XCTAssertEqual(actual.endTime, try Upgrade1301Spec.date(expected.endTime))
      XCTAssertEqual(actual.breakStartTime, try expected.breakStartTime.map(Upgrade1301Spec.date))
      XCTAssertEqual(actual.breakEndTime, try expected.breakEndTime.map(Upgrade1301Spec.date))
      XCTAssertEqual(actual.forceStarted, expected.forceStarted)
    }
    try expectedData.write(to: directory.appendingPathComponent("expected.json"))
    let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
      ofType: NSSQLiteStoreType, at: store)
    XCTAssertEqual(metadata[NSStoreModelVersionIdentifiersKey] as? [String], ["1.0.0"])
    let hashes = try XCTUnwrap(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
    XCTAssertEqual(Set(hashes.keys), ["BlockedProfiles", "BlockedProfileSession"])
    try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
      .write(to: directory.appendingPathComponent("source-store-metadata.plist"))
    print("UPGRADE1301_SEED_READY: \(directory.path)")
  }
}
