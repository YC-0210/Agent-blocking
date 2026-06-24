import XCTest

@testable import DoCard

/// Behavior tests for `TodaysTasksStore` — the store that owns the day's goals
/// and the local-midnight rollover. Driven test-first; each test describes an
/// observable behavior through the public interface, mirroring
/// `EntitlementsTests` / `HomeCenterpieceTests`.
final class TodaysTasksStoreTests: XCTestCase {
  private let suite = "TodaysTasksStoreTests"
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

  /// A fixed local date at 09:00, for deterministic injection.
  private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int, hour: Int = 9) -> Date {
    var c = DateComponents()
    c.year = year
    c.month = month
    c.day = dayOfMonth
    c.hour = hour
    return Calendar.current.date(from: c)!
  }

  // MARK: - Behavior 1: a fresh store is empty

  func testFreshStoreIsEmpty() {
    let today = day(2026, 6, 24)
    let store = TodaysTasksStore(defaults: defaults, now: { today })
    XCTAssertTrue(store.goals.isEmpty)
    XCTAssertEqual(store.totalCount, 0)
    XCTAssertEqual(store.completedCount, 0)
  }

  // MARK: - Behavior 2: adding a goal persists across reload

  func testAddedGoalPersistsAcrossReload() {
    let today = day(2026, 6, 24)
    let store = TodaysTasksStore(defaults: defaults, now: { today })
    store.addGoal(name: "Finish report", detail: "Section 3")
    XCTAssertEqual(store.totalCount, 1)

    // A new instance backed by the same storage loads the saved goal.
    let reloaded = TodaysTasksStore(defaults: defaults, now: { today })
    XCTAssertEqual(reloaded.goals.map(\.name), ["Finish report"])
    XCTAssertEqual(reloaded.goals.first?.detail, "Section 3")
  }

  // MARK: - Behavior 3: the store caps at three goals

  func testCapsAtThreeGoals() {
    let today = day(2026, 6, 24)
    let store = TodaysTasksStore(defaults: defaults, now: { today })
    store.addGoal(name: "One")
    store.addGoal(name: "Two")
    store.addGoal(name: "Three")
    store.addGoal(name: "Four")  // refused — already at the cap

    XCTAssertEqual(store.totalCount, 3)
    XCTAssertEqual(store.goals.map(\.name), ["One", "Two", "Three"])
  }

  // MARK: - Behavior 4: toggling done flips, and undoes

  func testToggleDoneFlipsAndUndoes() {
    let today = day(2026, 6, 24)
    let store = TodaysTasksStore(defaults: defaults, now: { today })
    store.addGoal(name: "Gym")

    store.toggleDone(store.goals[0])
    XCTAssertTrue(store.goals[0].done)

    store.toggleDone(store.goals[0])
    XCTAssertFalse(store.goals[0].done)
  }

  // MARK: - Behavior 5: ring counts reflect the current goals

  func testRingCountsReflectGoals() {
    let today = day(2026, 6, 24)
    let store = TodaysTasksStore(defaults: defaults, now: { today })
    store.addGoal(name: "A")
    store.addGoal(name: "B")
    store.addGoal(name: "C")
    store.toggleDone(store.goals[0])

    XCTAssertEqual(store.totalCount, 3)
    XCTAssertEqual(store.completedCount, 1)  // ring shows 1/3
  }

  // MARK: - Behavior 6: midnight rollover clears completed, carries unfinished

  func testRolloverClearsCompletedAndCarriesUnfinished() {
    let day1 = day(2026, 6, 24)
    let store = TodaysTasksStore(defaults: defaults, now: { day1 })
    store.addGoal(name: "Done thing")
    store.addGoal(name: "Unfinished A")
    store.addGoal(name: "Unfinished B")
    store.toggleDone(store.goals[0])  // complete "Done thing"

    // A new local day: a fresh instance reads the saved state and rolls over.
    let day2 = day(2026, 6, 25)
    let nextDay = TodaysTasksStore(defaults: defaults, now: { day2 })
    XCTAssertEqual(
      nextDay.goals.map(\.name), ["Unfinished A", "Unfinished B"],
      "Completed goals cleared; unfinished carried over in order")
    XCTAssertEqual(nextDay.completedCount, 0)

    // Re-opening the same day must not drop anything further.
    let sameDayAgain = TodaysTasksStore(defaults: defaults, now: { day2 })
    XCTAssertEqual(sameDayAgain.goals.map(\.name), ["Unfinished A", "Unfinished B"])
  }
}
