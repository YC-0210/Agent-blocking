#if DEBUG && targetEnvironment(simulator)
import CryptoKit
import Foundation
import Security
import SwiftData

/// Explicit launch arguments only. Never available in Release or on a physical device.
enum MaestroFixture {
  private static func argument(_ name: String) -> String? {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-" + name), index + 1 < arguments.count else {
      return nil
    }
    return arguments[index + 1]
  }

  static var isRequested: Bool { argument("docardUITestScenario") != nil }

  static func makeContainerIfRequested() -> ModelContainer? {
    guard let scenario = argument("docardUITestScenario") else { return nil }
    precondition(["manual", "scheduled"].contains(scenario), "Unknown Maestro fixture")
    guard let resetValue = argument("docardUITestReset"), ["true", "false"].contains(resetValue) else {
      preconditionFailure("Maestro requires an explicit true/false reset argument")
    }
    let reset = resetValue == "true"
    let group = "group.DO.version3"
    let defaults = UserDefaults(suiteName: group)!
    let directory = URL.applicationSupportDirectory.appendingPathComponent("Maestro", isDirectory: true)
    let url = directory.appendingPathComponent("smoke.store")

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      if reset {
        // This runs before the app's StateObjects/singletons or signed storage are initialized.
        for suffix in ["", "-wal", "-shm"] {
          let file = URL(fileURLWithPath: url.path + suffix)
          if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
          }
        }
        defaults.removePersistentDomain(forName: group)
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        let status = SecItemDelete([
          kSecClass: kSecClassGenericPassword,
          kSecAttrService: "com.do-app.security",
          kSecAttrAccount: "sharedDataHMACKey",
        ] as CFDictionary)
        // CI's unsigned simulator build has no Keychain access group (-34018).
        // It cannot read an old signing key either; do not fake Keychain success.
        precondition(status == errSecSuccess || status == errSecItemNotFound
          || status == errSecMissingEntitlement, "Fixture Keychain reset failed: \(status)")
        print("Maestro fixture Keychain reset status: \(status)")
        defaults.set(scenario, forKey: "maestroFixtureScenario")
        defaults.set(true, forKey: "onboardingCompleted")
        defaults.set(true, forKey: "tutorialCompleted")
        defaults.set(true, forKey: "whatsNewSeenVersion_2_0_8")
        defaults.set(true, forKey: "analyticsDisclosureShown")
        // A future marker also prevents uploads if a flow crosses midnight.
        defaults.set(DailyUsageAggregator.dayFormatter.string(from: .distantFuture),
          forKey: "analyticsLastReportedDay")
        UserDefaults.standard.set(true, forKey: "hasShownCardNamingNudge")
      } else {
        precondition(defaults.string(forKey: "maestroFixtureScenario") == scenario,
          "A Maestro resume requires a matching reset launch first")
      }
      defaults.set("premium", forKey: "debugForcedSubscriptionTier")
      if reset {
        let key = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        defaults.set(key, forKey: "maestroSigningKey")
        defaults.set(MaestroSessionHarness.date(hour: 8, minute: 59).timeIntervalSince1970,
          forKey: "maestroClock")
        defaults.set(3, forKey: "maestroEmergencyUses")
        defaults.set(["maestro-card"], forKey: "pairedDOCardTagIds")
      }
      SharedData.simulatorRuntime = SharedData.Runtime(
        defaults: defaults,
        signingKey: SymmetricKey(data: defaults.data(forKey: "maestroSigningKey")!),
        now: { MaestroSessionHarness.shared.now }, calendar: MaestroSessionHarness.calendar)

      let schema = Schema(versionedSchema: AppSchemaV5.self)
      let configuration = ModelConfiguration(schema: schema, url: url)
      let container = try AppModelStore.open(configuration: configuration)
      if reset {
        let context = ModelContext(container)
        let schedule = BlockedProfileSchedule(
          name: "Lock Journey", days: [.monday],
          startHour: 9, startMinute: 0, endHour: 10, endMinute: 0)
        let profile = BlockedProfiles(name: "Journey Profile", enableAllowMode: true,
          physicalUnblockNFCTagIds: ["maestro-card"],
          schedules: scenario == "scheduled" ? [schedule] : [])
        context.insert(profile)
        try context.save()
      }
      return container
    } catch {
      fatalError("Maestro fixture failed: \(error)")
    }
  }
}
#endif
