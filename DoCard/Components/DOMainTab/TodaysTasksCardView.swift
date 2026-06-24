import SwiftUI

/// Today's Tasks (今日目標) home centerpiece — Option C: a card in the
/// Motivation Gallery's visual language (300pt, 24pt corner, three-layer accent
/// glow) with a completion ring and a 做就對了 cheer line. Reads and mutates
/// through `TodaysTasksStore`. Creating / editing / deleting / reordering goals
/// arrives in Slice 3 (#10); here the empty "＋ 新增目標" rows are inert and the
/// only mutation is checking a goal off.
struct TodaysTasksCardView: View {
  @EnvironmentObject var themeManager: ThemeManager
  @StateObject private var store = TodaysTasksStore()

  private let maxCardWidth: CGFloat = 300
  private let corner: CGFloat = 24

  var body: some View {
    VStack(spacing: 16) {
      header
      ring
      cheerLine
      Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
      rows
    }
    .padding(20)
    .frame(maxWidth: maxCardWidth)
    .background(
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(Color(red: 0.086, green: 0.086, blue: 0.094))
        .overlay(
          RoundedRectangle(cornerRadius: corner, style: .continuous)
            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    )
    .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
    .shadow(color: themeManager.themeColor.opacity(0.35), radius: 40)
    .shadow(color: themeManager.themeColor.opacity(0.25), radius: 20)
    .shadow(color: themeManager.themeColor.opacity(0.15), radius: 8)
    .frame(maxWidth: .infinity)
    .onAppear { store.refreshForCurrentDay() }
  }

  // MARK: - Header

  private var header: some View {
    VStack(spacing: 4) {
      Text(String(localized: "今日目標"))
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.white)
      Text(Date(), format: .dateTime.month().day().weekday(.wide))
        .font(.system(size: 12.5))
        .foregroundColor(.white.opacity(0.5))
    }
  }

  // MARK: - Completion ring

  private var ring: some View {
    ZStack {
      Circle().stroke(Color.white.opacity(0.12), lineWidth: 7)
      Circle()
        .trim(from: 0, to: ringProgress)
        .stroke(themeManager.themeColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
        .rotationEffect(.degrees(-90))
        .animation(.easeInOut, value: store.completedCount)
      ringCenterLabel
    }
    .frame(width: 78, height: 78)
  }

  private var ringProgress: CGFloat {
    guard store.totalCount > 0 else { return 0 }
    return CGFloat(store.completedCount) / CGFloat(store.totalCount)
  }

  @ViewBuilder private var ringCenterLabel: some View {
    if store.totalCount == 0 {
      Text(String(localized: "今日"))
        .font(.system(size: 15, weight: .semibold))
        .foregroundColor(.white.opacity(0.6))
    } else {
      Text("\(store.completedCount)/\(store.totalCount)")
        .font(.system(size: 20, weight: .bold))
        .foregroundColor(.white)
    }
  }

  // MARK: - Cheer line

  private var cheerLine: some View {
    Text(
      store.totalCount == 0
        ? String(localized: "新增你的第一個目標")
        : String(localized: "做就對了")
    )
    .font(.system(size: 13, weight: .bold))
    .foregroundColor(store.totalCount == 0 ? .white.opacity(0.5) : themeManager.themeColor)
  }

  // MARK: - Goal rows

  private var rows: some View {
    VStack(spacing: 12) {
      ForEach(store.goals) { goal in
        filledRow(goal)
      }
      ForEach(0..<emptySlotCount, id: \.self) { _ in
        emptyRow
      }
    }
  }

  private var emptySlotCount: Int {
    max(0, TodaysTasksStore.maxGoals - store.goals.count)
  }

  private func filledRow(_ goal: DailyTask) -> some View {
    HStack(spacing: 12) {
      Button {
        store.toggleDone(goal)
      } label: {
        Image(systemName: goal.done ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 22))
          .foregroundColor(goal.done ? themeManager.themeColor : .white.opacity(0.4))
      }
      .buttonStyle(.plain)

      Text(goal.name)
        .font(.system(size: 15))
        .foregroundColor(goal.done ? .white.opacity(0.4) : .white)
        .strikethrough(goal.done, color: .white.opacity(0.4))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var emptyRow: some View {
    HStack(spacing: 12) {
      Image(systemName: "plus.circle")
        .font(.system(size: 22))
        .foregroundColor(.white.opacity(0.2))
      Text(String(localized: "新增目標"))
        .font(.system(size: 15))
        .foregroundColor(.white.opacity(0.25))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }
}
