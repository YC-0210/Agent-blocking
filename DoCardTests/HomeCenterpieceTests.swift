import XCTest

@testable import DoCard

/// Tests for the `HomeCenterpiece` selection and its one-time migration from
/// the legacy `showMotivationGalleryOnHome` Boolean. These lock down the rule
/// that existing users keep their centerpiece after the 3-way chooser ships.
final class HomeCenterpieceTests: XCTestCase {
  private let suite = "HomeCenterpieceTests"
  private var defaults: UserDefaults!

  override func setUp() {
    super.setUp()
    defaults = UserDefaults(suiteName: suite)
    defaults.removePersistentDomain(forName: suite)
  }

  override func tearDown() {
    defaults.removePersistentDomain(forName: suite)
    defaults = nil
    super.tearDown()
  }

  func testMigratesLegacyTrueToGallery() {
    defaults.set(true, forKey: HomeCenterpiece.legacyGalleryKey)
    HomeCenterpiece.migrateLegacySettingIfNeeded(defaults)
    XCTAssertEqual(
      defaults.string(forKey: HomeCenterpiece.storageKey),
      HomeCenterpiece.gallery.rawValue,
      "A user who had the gallery showing should land on .gallery")
  }

  func testMigratesLegacyFalseToCard() {
    defaults.set(false, forKey: HomeCenterpiece.legacyGalleryKey)
    HomeCenterpiece.migrateLegacySettingIfNeeded(defaults)
    XCTAssertEqual(
      defaults.string(forKey: HomeCenterpiece.storageKey),
      HomeCenterpiece.card.rawValue,
      "A user who had the DO Card showing should land on .card")
  }

  func testAbsentLegacyDefaultsToGallery() {
    HomeCenterpiece.migrateLegacySettingIfNeeded(defaults)
    XCTAssertEqual(
      defaults.string(forKey: HomeCenterpiece.storageKey),
      HomeCenterpiece.gallery.rawValue,
      "A fresh install defaults to the gallery, matching the prior default")
  }

  func testDoesNotOverwriteExistingSelection() {
    // User already chose Today's Tasks; a stale legacy Boolean must not
    // downgrade their choice.
    defaults.set(HomeCenterpiece.tasks.rawValue, forKey: HomeCenterpiece.storageKey)
    defaults.set(false, forKey: HomeCenterpiece.legacyGalleryKey)
    HomeCenterpiece.migrateLegacySettingIfNeeded(defaults)
    XCTAssertEqual(
      defaults.string(forKey: HomeCenterpiece.storageKey),
      HomeCenterpiece.tasks.rawValue)
  }

  func testIsIdempotent() {
    defaults.set(false, forKey: HomeCenterpiece.legacyGalleryKey)
    HomeCenterpiece.migrateLegacySettingIfNeeded(defaults)
    HomeCenterpiece.migrateLegacySettingIfNeeded(defaults)
    XCTAssertEqual(
      defaults.string(forKey: HomeCenterpiece.storageKey),
      HomeCenterpiece.card.rawValue,
      "Running the migration twice must not change the result")
  }
}
