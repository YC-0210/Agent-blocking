import Charts
import SwiftUI

struct ProfileInsightsView: View {
  @StateObject private var viewModel: ProfileInsightsUtil
  @Environment(\.dismiss) private var dismiss

  init(profile: BlockedProfiles) {
    _viewModel = StateObject(wrappedValue: ProfileInsightsUtil(profile: profile))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 4) {
            Text(
              String(localized: "A snapshot of your focus habits, sessions, and breaks. Use these insights to understand patterns and improve productivity.")
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
          }

          VStack(alignment: .leading, spacing: 8) {
            SectionTitle(String(localized: "Focus Habits"))

            MultiStatCard(
              stats: [
                .init(
                  title: String(localized: "Current Streak"),
                  valueText: String(viewModel.currentStreakDays()) + " " + String(localized: "days"),
                  systemImageName: "flame",
                  iconColor: .red
                ),
                .init(
                  title: String(localized: "Longest Streak"),
                  valueText: String(viewModel.longestStreakDays()) + " " + String(localized: "days"),
                  systemImageName: "crown",
                  iconColor: .yellow
                ),
              ],
              columns: 2
            )
          }

          VStack(alignment: .leading, spacing: 8) {
            SectionTitle(String(localized: "Session"))

            MultiStatCard(
              stats: [
                .init(
                  title: String(localized: "Total Focus Time"),
                  valueText: viewModel.formattedDuration(viewModel.metrics.totalFocusTime),
                  systemImageName: "clock",
                  iconColor: .orange
                ),
                .init(
                  title: String(localized: "Average Session"),
                  valueText: viewModel.formattedDuration(viewModel.metrics.averageSessionDuration),
                  systemImageName: "chart.bar",
                  iconColor: .orange
                ),
                .init(
                  title: String(localized: "Longest Session"),
                  valueText: viewModel.formattedDuration(viewModel.metrics.longestSessionDuration),
                  systemImageName: "timer",
                  iconColor: .orange
                ),
                .init(
                  title: String(localized: "Shortest Session"),
                  valueText: viewModel.formattedDuration(viewModel.metrics.shortestSessionDuration),
                  systemImageName: "hourglass",
                  iconColor: .orange
                ),
                .init(
                  title: String(localized: "Total Sessions"),
                  valueText: String(viewModel.metrics.totalCompletedSessions),
                  systemImageName: "list.number",
                  iconColor: .orange
                ),
              ],
              columns: 2
            )
          }

          VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "Daily Patterns"))

            ChartCard(
              title: String(localized: "Sessions per Day"),
              subtitle: String(localized: "Daily session count over the last 14 days")
            ) {
              let data = viewModel.dailyAggregates(days: 14)
              SelectableChartFactory.dailyChart(
                data: data,
                xValue: \.date,
                yValue: { Double($0.sessionsCount) }
              ) { item in
                BarMark(
                  x: .value("Date", item.date),
                  y: .value("Sessions", item.sessionsCount)
                )
                .foregroundStyle(.blue)
              } annotationValue: { selectedData in
                String(localized: "\(selectedData?.sessionsCount ?? 0) sessions")
              }
              .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                  AxisGridLine()
                  AxisTick()
                  AxisValueLabel(format: .dateTime.month().day())
                }
              }
              .chartYAxis {
                AxisMarks(position: .leading)
              }
            }

            ChartCard(
              title: String(localized: "Focus Time Trend"),
              subtitle:
                String(localized: "Total minutes focused per day over 14 days")
            ) {
              let data = viewModel.dailyAggregates(days: 14)
              SelectableChartFactory.dailyChart(
                data: data,
                xValue: \.date,
                yValue: { $0.focusDuration / 60.0 }
              ) { item in
                LineMark(
                  x: .value("Date", item.date),
                  y: .value("Minutes", item.focusDuration / 60.0)
                )
                .foregroundStyle(.green)
                AreaMark(
                  x: .value("Date", item.date),
                  y: .value("Minutes", item.focusDuration / 60.0)
                )
                .foregroundStyle(.green.opacity(0.2))
              } annotationValue: { selectedData in
                String(localized: "\(Int(round((selectedData?.focusDuration ?? 0) / 60.0))) min")
              }
              .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                  AxisGridLine()
                  AxisTick()
                  AxisValueLabel(format: .dateTime.month().day())
                }
              }
              .chartYAxis {
                AxisMarks(position: .leading)
              }
            }
          }

          VStack(alignment: .leading, spacing: 16) {
            SectionTitle(String(localized: "Time of Day"))

            ChartCard(
              title: String(localized: "Sessions Started by Hour"),
              subtitle:
                String(localized: "When you typically begin focus sessions by hour over 14 days")
            ) {
              let data = viewModel.hourlyAggregates(days: 14)
              SelectableChartFactory.hourlyChart(
                data: data,
                xValue: \.hour,
                yValue: { Double($0.sessionsStarted) }
              ) { item in
                BarMark(
                  x: .value("Hour", item.hour),
                  y: .value("Sessions", item.sessionsStarted)
                )
                .foregroundStyle(.blue)
              } annotationValue: { selectedData in
                String(localized: "\(selectedData?.sessionsStarted ?? 0) sessions started")
              }
              .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                  AxisGridLine()
                  AxisTick()
                  if let hour = value.as(Int.self) {
                    AxisValueLabel(formatHourShort(hour))
                  }
                }
              }
              .chartYAxis {
                AxisMarks(position: .leading)
              }
            }

            ChartCard(
              title: String(localized: "Average Session by Hour"),
              subtitle:
                String(localized: "Mean session duration in minutes by hour over 14 days")
            ) {
              let data = viewModel.hourlyAggregates(days: 14)
              SelectableChartFactory.hourlyChart(
                data: data,
                xValue: \.hour,
                yValue: { ($0.averageSessionDuration ?? 0) / 60.0 }
              ) { item in
                LineMark(
                  x: .value("Hour", item.hour),
                  y: .value("Minutes", (item.averageSessionDuration ?? 0) / 60.0)
                )
                .foregroundStyle(.green)
                AreaMark(
                  x: .value("Hour", item.hour),
                  y: .value("Minutes", (item.averageSessionDuration ?? 0) / 60.0)
                )
                .foregroundStyle(.green.opacity(0.2))
              } annotationValue: { selectedData in
                String(localized: "\(Int(round(((selectedData?.averageSessionDuration ?? 0) / 60.0)))) min avg")
              }
              .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                  AxisGridLine()
                  AxisTick()
                  if let hour = value.as(Int.self) {
                    AxisValueLabel(formatHourShort(hour))
                  }
                }
              }
              .chartYAxis {
                AxisMarks(position: .leading)
              }
            }

            ChartCard(
              title: String(localized: "Session End Times"),
              subtitle:
                String(localized: "When you typically complete focus sessions by hour over 14 days")
            ) {
              let data = viewModel.sessionEndHourlyAggregates(days: 14)
              SelectableChartFactory.hourlyChart(
                data: data,
                xValue: \.hour,
                yValue: { Double($0.sessionsEnded) }
              ) { item in
                BarMark(
                  x: .value("Hour", item.hour),
                  y: .value("Sessions", item.sessionsEnded)
                )
                .foregroundStyle(.red)
              } annotationValue: { selectedData in
                String(localized: "\(selectedData?.sessionsEnded ?? 0) sessions ended")
              }
              .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { value in
                  AxisGridLine()
                  AxisTick()
                  if let hour = value.as(Int.self) {
                    AxisValueLabel(formatHourShort(hour))
                  }
                }
              }
              .chartYAxis {
                AxisMarks(position: .leading)
              }
            }
          }
          VStack(alignment: .leading, spacing: 8) {
            SectionTitle(String(localized: "Details"))

            MultiStatCard(
              stats: nerdStatsItems,
              columns: 2
            )
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .background(Color(.systemGroupedBackground).ignoresSafeArea())
      .navigationTitle(String(localized: "Stats for Nerds"))
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button {
            dismiss()
          } label: {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(String(localized: "Close"))
        }
      }
    }
  }
}

#Preview {
  let profile = BlockedProfiles(name: "Focus")
  ProfileInsightsView(profile: profile)
}

extension ProfileInsightsView {
  private func formatHourShort(_ hour: Int) -> String {
    var comps = DateComponents()
    comps.hour = max(0, min(23, hour))
    let calendar = Calendar.current
    let date = calendar.date(from: comps) ?? Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "ha"
    return formatter.string(from: date).lowercased()
  }

  private var nerdStatsItems: [MultiStatCard.StatItem] {
    let profile = viewModel.profile
    let profileIdShort = String(profile.id.uuidString.prefix(8))

    var items: [MultiStatCard.StatItem] = [
      .init(
        title: String(localized: "模式 ID"), valueText: profileIdShort, systemImageName: "tag", iconColor: .gray),
      .init(
        title: String(localized: "Created"), valueText: profile.createdAt.formatted(), systemImageName: "calendar",
        iconColor: .gray),
      .init(
        title: String(localized: "Last Modified"), valueText: profile.updatedAt.formatted(), systemImageName: "clock",
        iconColor: .gray),
      .init(
        title: String(localized: "Details Total Sessions"), valueText: "\(profile.sessions.count)",
        systemImageName: "list.number", iconColor: .gray),
      .init(
        title: String(localized: "Apps Blocked"), valueText: "\(profile.selectedActivity.applicationTokens.count)",
        systemImageName: "app", iconColor: .gray),
    ]

    let activeTimers = profile.activeScheduleTimerActivities
    if let active = activeTimers.first {
      items.append(
        .init(
          title: String(localized: "Active Schedule Timer Activity"), valueText: String(active.rawValue.prefix(8)),
          systemImageName: "bolt.fill",
          iconColor: .gray))
    }

    return items
  }
}
