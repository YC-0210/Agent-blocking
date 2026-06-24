import SwiftUI

/// Placeholder shown in the centerpiece slot when the user selects Today's
/// Tasks (今日目標), before the real Option C card exists. Replaced by the
/// actual card in Slice 2 (issue #9).
struct TodaysTasksPlaceholderView: View {
  @EnvironmentObject var themeManager: ThemeManager

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: "checklist")
        .font(.system(size: 40, weight: .light))
        .foregroundColor(themeManager.themeColor)
      Text(String(localized: "今日目標"))
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.white)
      Text(String(localized: "即將推出"))
        .font(.system(size: 13))
        .foregroundColor(.white.opacity(0.5))
    }
    .frame(maxWidth: 300)
    .padding(.vertical, 40)
  }
}
