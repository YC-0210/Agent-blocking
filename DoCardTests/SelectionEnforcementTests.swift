import CryptoKit
import XCTest

@testable import DoCard

final class SelectionEnforcementTests: XCTestCase {
  func testB5UnpaidAllowModeCannotActivate() {
    let name = "SelectionEnforcementTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let runtime = SharedData.Runtime(
      defaults: defaults, signingKey: SymmetricKey(size: .bits256), now: { now },
      calendar: Calendar(identifier: .gregorian))
    SharedData.$runtime.withValue(runtime) {
      let profile = BlockedProfiles(name: "allow-only", enableAllowMode: true)
      let snapshot = BlockedProfiles.getSnapshot(for: profile)
      XCTAssertFalse(AppBlockerUtil().wouldShieldAnything(for: snapshot))
    }
  }
}
