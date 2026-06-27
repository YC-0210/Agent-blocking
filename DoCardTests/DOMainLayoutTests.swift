import XCTest

@testable import DoCard

/// Tests for `DOMainLayout` — the pure description of the DO main page's
/// vertical spacing around the home centerpiece. Mirrors `SettingsLayoutTests`:
/// the load-bearing layout metrics live in one tested place instead of being
/// re-derived inline in `DOMainTabView`.
///
/// The only behavioural input is the chosen centerpiece. The tall Today's Tasks
/// (`.tasks`) card must sit in a tighter layout than the compact gallery / DO
/// card so the page does not feel crowded; the gallery and card centerpieces
/// keep their original spacing.
final class DOMainLayoutTests: XCTestCase {

  // MARK: - Timer → centerpiece spacing

  func testTimerBottomPaddingTighterForTasks() {
    let tasks = DOMainLayout.timerBottomPadding(centerpiece: .tasks)
    let gallery = DOMainLayout.timerBottomPadding(centerpiece: .gallery)
    let card = DOMainLayout.timerBottomPadding(centerpiece: .card)

    XCTAssertLessThan(
      tasks, gallery,
      "今日目標 is taller, so it needs less space between the timer and the card")
    XCTAssertEqual(gallery, card, "Gallery and DO card keep the same timer spacing")
  }

  func testTimerBottomPaddingPreservesOriginalForCompactCenterpieces() {
    XCTAssertEqual(
      DOMainLayout.timerBottomPadding(centerpiece: .gallery), 50,
      "Gallery layout is unchanged from before the Tasks centerpiece existed")
  }

  // MARK: - Centerpiece → card-name / profile spacing

  func testCenterpieceBottomPaddingTighterForTasks() {
    for hasCardName in [true, false] {
      let tasks = DOMainLayout.centerpieceBottomPadding(centerpiece: .tasks, hasCardName: hasCardName)
      let gallery = DOMainLayout.centerpieceBottomPadding(
        centerpiece: .gallery, hasCardName: hasCardName)
      XCTAssertLessThanOrEqual(
        tasks, gallery,
        "今日目標 never uses more space below the card than the compact centerpieces")
    }
  }

  func testCenterpieceBottomPaddingPreservesOriginalForCompactCenterpieces() {
    XCTAssertEqual(
      DOMainLayout.centerpieceBottomPadding(centerpiece: .gallery, hasCardName: true), 8,
      "Original spacing when a card name is shown")
    XCTAssertEqual(
      DOMainLayout.centerpieceBottomPadding(centerpiece: .card, hasCardName: false), 30,
      "Original spacing when no card name is shown")
  }

  // MARK: - Only the Tasks centerpiece changes

  func testGalleryAndCardShareIdenticalMetrics() {
    XCTAssertEqual(
      DOMainLayout.timerBottomPadding(centerpiece: .gallery),
      DOMainLayout.timerBottomPadding(centerpiece: .card))
    for hasCardName in [true, false] {
      XCTAssertEqual(
        DOMainLayout.centerpieceBottomPadding(centerpiece: .gallery, hasCardName: hasCardName),
        DOMainLayout.centerpieceBottomPadding(centerpiece: .card, hasCardName: hasCardName),
        "Only the Tasks centerpiece changes the page spacing")
    }
  }
}
