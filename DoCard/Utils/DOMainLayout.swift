import CoreGraphics

/// A pure description of the DO main page's vertical spacing around the home
/// centerpiece. `DOMainTabView` reads these instead of hard-coding the paddings
/// inline, so the values live in one place and are unit-tested with no live
/// SwiftUI — mirroring `SettingsLayout`.
///
/// The only input is the chosen centerpiece. The Today's Tasks (`.tasks`) card
/// is much taller than the compact gallery / DO-card centerpieces (header +
/// completion ring + cheer line + divider + three goal rows), so it gets a
/// tighter layout to keep the page from feeling crowded. The gallery and card
/// centerpieces keep exactly the spacing they had before Tasks existed.
enum DOMainLayout {
  /// Space below the timer pill block, above the centerpiece.
  static func timerBottomPadding(centerpiece: HomeCenterpiece) -> CGFloat {
    centerpiece == .tasks ? 24 : 50
  }

  /// Space below the centerpiece, above the card name / profile info. When a
  /// card name is shown the gap is smaller (the name sits close under the card);
  /// when it is absent the centerpiece carries the whole gap to the profile row.
  static func centerpieceBottomPadding(
    centerpiece: HomeCenterpiece, hasCardName: Bool
  ) -> CGFloat {
    if centerpiece == .tasks {
      return hasCardName ? 4 : 16
    }
    return hasCardName ? 8 : 30
  }
}
