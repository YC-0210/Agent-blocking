import Charts
import SwiftData
import SwiftUI

struct ActivityTabView: View {
  @EnvironmentObject var themeManager: ThemeManager

  @Query(sort: [
    SortDescriptor(\BlockedProfiles.order, order: .forward),
    SortDescriptor(\BlockedProfiles.createdAt, order: .reverse),
  ]) private var profiles: [BlockedProfiles]

  @Query(
    filter: #Predicate<BlockedProfileSession> { $0.endTime != nil },
    sort: \BlockedProfileSession.endTime,
    order: .reverse
  ) private var allCompletedSessions: [BlockedProfileSession]

  @State private var selectedPeriod: TimePeriod = .week
  @State private var showingProfilePicker = false

  enum TimePeriod: String, CaseIterable {
    case week
    case month
    case all

    var displayTitle: String {
      switch self {
      case .week: return String(localized: "每週活動")
      case .month: return String(localized: "每月活動")
      case .all: return String(localized: "所有活動")
      }
    }

    var subtitle: String {
      switch self {
      case .week: return String(localized: "本週")
      case .month: return String(localized: "本月")
      case .all: return String(localized: "全部")
      }
    }
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        // Period dropdown header
        VStack(spacing: 6) {
          Menu {
            ForEach(TimePeriod.allCases, id: \.self) { period in
              Button {
                withAnimation(.easeInOut(duration: 0.25)) { selectedPeriod = period }
              } label: {
                HStack {
                  Text(period.displayTitle)
                  if period == selectedPeriod {
                    Image(systemName: "checkmark")
                  }
                }
              }
            }
          } label: {
            HStack(spacing: 6) {
              Text(selectedPeriod.displayTitle)
                .font(.title3)
                .fontWeight(.semibold)
              Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
            }
            .foregroundColor(.primary)
          }

          Text(selectedPeriod.subtitle)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .tracking(1.5)
        }
        .padding(.top, 16)
        .padding(.bottom, 20)

        // Main content
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            // Average focus time
            avgFocusTimeSection
              .padding(.horizontal, 20)

            // Bar chart
            chartSection
              .padding(.top, 24)
              .padding(.horizontal, 20)

            // Detailed stats link
            detailedStatsLink
              .padding(.top, 40)
              .padding(.horizontal, 20)
              .padding(.bottom, 32)
          }
        }
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .sheet(isPresented: $showingProfilePicker) {
        profilePickerSheet
      }
    }
  }

  // MARK: - Average Focus Time

  private var avgFocusTimeSection: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(String(localized: "平均專注時間"))
        .font(.subheadline)
        .foregroundColor(.secondary)

      Text(formattedDuration(averageDailyFocusTime))
        .font(.system(size: 48, weight: .bold, design: .rounded))
        .foregroundColor(.primary)
    }
  }

  // MARK: - Bar Chart

  private var chartSection: some View {
    let data = chartData
    let maxDuration = data.map(\.focusDuration).max() ?? 3600

    return Chart(data) { item in
      BarMark(
        x: .value("Day", item.label),
        y: .value("Duration", item.focusDuration / 60.0)
      )
      .foregroundStyle(item.isToday ? themeManager.themeColor : themeManager.themeColor.opacity(0.3))
      .cornerRadius(4)
    }
    .chartYAxis {
      AxisMarks(position: .trailing, values: yAxisValues(max: maxDuration)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
          .foregroundStyle(Color(.separator))
        AxisValueLabel {
          if let minutes = value.as(Double.self) {
            Text(formatMinutesAxis(minutes))
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .chartXAxis {
      AxisMarks { value in
        AxisValueLabel {
          if let label = value.as(String.self) {
            let parts = label.components(separatedBy: "\n")
            VStack(spacing: 2) {
              Text(parts.first ?? "")
                .font(.system(size: 11, weight: .medium))
              if parts.count > 1 {
                Text(parts.last ?? "")
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
              }
            }
          }
        }
      }
    }
    .chartYScale(domain: 0...max(yAxisMax(max: maxDuration), 1))
    .frame(height: 240)
  }

  // MARK: - Detailed Stats Link

  private var detailedStatsLink: some View {
    Group {
      if !profiles.isEmpty {
        Button {
          showingProfilePicker = true
        } label: {
          HStack {
            Image(systemName: "chart.bar.doc.horizontal")
              .font(.body)
            Text(String(localized: "詳細統計"))
              .font(.subheadline)
              .fontWeight(.medium)
            Spacer()
            Image(systemName: "chevron.right")
              .font(.caption)
          }
          .foregroundColor(.secondary)
          .padding(16)
          .background(
            RoundedRectangle(cornerRadius: 12)
              .fill(Color(.secondarySystemGroupedBackground))
          )
        }
      }
    }
  }

  private var profilePickerSheet: some View {
    NavigationStack {
      List(profiles) { profile in
        NavigationLink(destination: ProfileInsightsView(profile: profile)) {
          Text(profile.name)
        }
      }
      .navigationTitle(String(localized: "選擇模式"))
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  // MARK: - Chart Data

  private struct ChartDataPoint: Identifiable {
    let id = UUID()
    let label: String
    let date: Date
    let focusDuration: TimeInterval
    let isToday: Bool
  }

  private var chartData: [ChartDataPoint] {
    switch selectedPeriod {
    case .week: return weeklyChartData
    case .month: return monthlyChartData
    case .all: return allTimeChartData
    }
  }

  private var weeklyChartData: [ChartDataPoint] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Find the start of the current week (Sunday)
    let weekday = calendar.component(.weekday, from: today)
    guard let weekStart = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) else {
      return []
    }

    let daySymbols = calendar.shortWeekdaySymbols.map { $0.uppercased() }
    var result: [ChartDataPoint] = []

    for i in 0..<7 {
      guard let day = calendar.date(byAdding: .day, value: i, to: weekStart) else { continue }
      let dayNumber = calendar.component(.day, from: day)
      let label = "\(daySymbols[i])\n\(dayNumber)"
      let duration = totalFocusDuration(for: day)
      let isToday = calendar.isDate(day, inSameDayAs: today)
      result.append(ChartDataPoint(label: label, date: day, focusDuration: duration, isToday: isToday))
    }
    return result
  }

  private var monthlyChartData: [ChartDataPoint] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())
    let range = calendar.range(of: .day, in: .month, for: today) ?? 1..<31
    guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))
    else { return [] }

    var result: [ChartDataPoint] = []
    for dayNum in range {
      guard let day = calendar.date(byAdding: .day, value: dayNum - 1, to: monthStart) else {
        continue
      }
      let label = "\(dayNum)"
      let duration = totalFocusDuration(for: day)
      let isToday = calendar.isDate(day, inSameDayAs: today)
      result.append(ChartDataPoint(label: label, date: day, focusDuration: duration, isToday: isToday))
    }
    return result
  }

  private var allTimeChartData: [ChartDataPoint] {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: Date())

    // Show last 30 days for all time
    guard let windowStart = calendar.date(byAdding: .day, value: -29, to: today) else { return [] }

    var result: [ChartDataPoint] = []
    var current = windowStart
    while current <= today {
      let dayNum = calendar.component(.day, from: current)
      let label = "\(dayNum)"
      let duration = totalFocusDuration(for: current)
      let isToday = calendar.isDate(current, inSameDayAs: today)
      result.append(
        ChartDataPoint(label: label, date: current, focusDuration: duration, isToday: isToday))
      guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
      current = next
    }
    return result
  }

  // MARK: - Calculations

  private func totalFocusDuration(for day: Date) -> TimeInterval {
    let calendar = Calendar.current
    return allCompletedSessions
      .filter { session in
        guard let end = session.endTime else { return false }
        return calendar.isDate(calendar.startOfDay(for: end), inSameDayAs: day)
      }
      .reduce(0) { total, session in
        guard let end = session.endTime else { return total }
        return total + max(0, end.timeIntervalSince(session.startTime))
      }
  }

  private var averageDailyFocusTime: TimeInterval? {
    let data = chartData
    let daysWithFocus = data.filter { $0.focusDuration > 0 }
    guard !daysWithFocus.isEmpty else { return nil }
    let total = daysWithFocus.reduce(0) { $0 + $1.focusDuration }
    return total / Double(daysWithFocus.count)
  }

  // MARK: - Y-Axis Helpers

  private func yAxisValues(max duration: TimeInterval) -> [Double] {
    let maxMinutes = duration / 60.0
    if maxMinutes <= 0 {
      return [0, 30, 60]
    } else if maxMinutes <= 30 {
      return stride(from: 0, through: 30, by: 10).map { $0 }
    } else if maxMinutes <= 60 {
      return stride(from: 0, through: 60, by: 30).map { $0 }
    } else if maxMinutes <= 120 {
      return stride(from: 0, through: 120, by: 30).map { $0 }
    } else if maxMinutes <= 180 {
      return stride(from: 0, through: 180, by: 60).map { $0 }
    } else {
      let step = ceil(maxMinutes / 4 / 30) * 30
      let top = step * 4
      return stride(from: 0, through: top, by: step).map { $0 }
    }
  }

  private func yAxisMax(max duration: TimeInterval) -> Double {
    let values = yAxisValues(max: duration)
    return values.last ?? 60
  }

  private func formatMinutesAxis(_ minutes: Double) -> String {
    let mins = Int(minutes)
    if mins == 0 { return "" }
    let h = mins / 60
    let m = mins % 60
    if h > 0 && m > 0 { return "\(h)h \(m)m" }
    if h > 0 { return "\(h)h" }
    return "\(m)m"
  }

  // MARK: - Duration Formatting

  private func formattedDuration(_ interval: TimeInterval?) -> String {
    guard let interval = interval, interval > 0 else { return "0h 0m" }
    let totalSeconds = Int(interval)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    return "\(hours)h \(minutes)m"
  }
}

#Preview {
  ActivityTabView()
    .environmentObject(ThemeManager.shared)
}
