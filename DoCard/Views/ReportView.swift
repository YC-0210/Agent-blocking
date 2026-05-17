import SwiftData
import SwiftUI

struct ReportView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var coFocusManager: CoFocusManager
    @Environment(\.modelContext) private var context

    @StateObject private var viewModel = ReportViewModel()

    @Query(
        filter: #Predicate<BlockedProfileSession> { $0.endTime != nil },
        sort: \BlockedProfileSession.endTime,
        order: .reverse
    ) private var allCompletedSessions: [BlockedProfileSession]

    @State private var showPaywall = false

    private var hasAnySessions: Bool {
        !allCompletedSessions.isEmpty
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasAnySessions {
                    reportContent
                } else {
                    emptyState
                }
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(String(localized: "週報"))
        }
        .onAppear {
            loadReport()
            Task { await coFocusManager.refreshMonthlyTotal() }
        }
        .onChange(of: subscriptionManager.tier) { _, _ in loadReport() }
        .sheet(isPresented: $showPaywall) {
            PremiumUpgradeView()
                .environmentObject(subscriptionManager)
        }
    }

    private func loadReport() {
        viewModel.load(context: context, isPremium: subscriptionManager.isPremium)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 56))
                .foregroundStyle(themeManager.themeColor.opacity(0.5))
            Text(String(localized: "碰一下卡片，開始記錄你的專注歷程"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }

    // MARK: - Report Content

    private var reportContent: some View {
        let isPremium = subscriptionManager.isPremium

        return ScrollView {
            VStack(spacing: 16) {
                weekHeader

                // Free tier metrics
                durationCard

                HStack(spacing: 12) {
                    statCard(
                        title: String(localized: "專注次數"),
                        value: "\(viewModel.sessionCount)",
                        icon: "flame.fill"
                    )
                    statCard(
                        title: String(localized: "平均專注"),
                        subtitle: String(localized: "（本週每次專注的平均時間）"),
                        value: formatDuration(viewModel.averageSessionDuration),
                        icon: "timer"
                    )
                }

                if coFocusManager.monthlyTotal.sessionCount > 0 {
                    coFocusMonthlyCard
                }

                if !viewModel.topProfiles.isEmpty {
                    topProfilesCard
                }

                if let score = viewModel.focusScore {
                    focusScoreCard(score: score, isPremium: isPremium)
                } else if !isPremium {
                    focusScoreCard(score: 0, isPremium: false)
                }

                if let rate = viewModel.completionRate {
                    completionRateCard(rate: rate, isPremium: isPremium)
                } else if !isPremium {
                    completionRateCard(rate: 0, isPremium: false)
                }

                if let peakResult = viewModel.peakTimeResult {
                    peakTimeCard(result: peakResult, isPremium: isPremium)
                }

                if let optResult = viewModel.optimalSessionResult {
                    optimalSessionCard(result: optResult, isPremium: isPremium)
                }

                if let habitResult = viewModel.habitResult {
                    habitFormationCard(result: habitResult, isPremium: isPremium)
                }

                if let trend = viewModel.weekTrend {
                    weekTrendCard(trend: trend, isPremium: isPremium)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    // MARK: - Week Header

    private var weekHeader: some View {
        let calendar = Calendar.current
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: Date())
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let startStr = formatter.string(from: weekInterval?.start ?? Date())
        let endStr = formatter.string(
            from: calendar.date(byAdding: .day, value: -1, to: weekInterval?.end ?? Date()) ?? Date()
        )
        let isPremium = subscriptionManager.isPremium

        return Group {
            if isPremium {
                Text("\(startStr) – \(endStr)")
            } else {
                Text(String(localized: "本週"))
            }
        }
        .font(.subheadline)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Duration Card

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass.circle.fill")
                    .foregroundStyle(themeManager.themeColor)
                Text(String(localized: "本週專注時間"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(formatDuration(viewModel.totalBlockDuration))
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Stat Card

    private func statCard(title: String, subtitle: String? = nil, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Top Profiles Card

    private var topProfilesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "trophy.fill")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "最常使用模式"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            let maxDuration = viewModel.topProfiles.first?.duration ?? 1

            ForEach(Array(viewModel.topProfiles.enumerated()), id: \.element.id) { index, profile in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profile.name)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        GeometryReader { geo in
                            let fraction = maxDuration > 0 ? profile.duration / maxDuration : 0
                            RoundedRectangle(cornerRadius: 3)
                                .fill(themeManager.themeColor.opacity(1.0 - Double(index) * 0.25))
                                .frame(width: geo.size.width * fraction)
                        }
                        .frame(height: 6)
                    }

                    Spacer()

                    Text(formatDuration(profile.duration))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Co-Focus Monthly Card

    private var coFocusMonthlyCard: some View {
        let total = coFocusManager.monthlyTotal
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "person.2.fill")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "本月共同專注"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(formatDurationCompact(TimeInterval(total.totalSeconds)))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(String.localizedStringWithFormat(
                    String(localized: "%lld 次"),
                    Int64(total.sessionCount)
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Premium Upsell Card

    private var premiumUpsellCard: some View {
        Button(action: { showPaywall = true }) {
            HStack(spacing: 12) {
                Image(systemName: "crown.fill")
                    .foregroundStyle(.orange)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "解鎖完整週報"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                    Text(String(localized: "專注分數、趨勢分析、完成率"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Focus Score Card

    private func focusScoreCard(score: Int, isPremium: Bool) -> some View {
        VStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile.fill")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "專注分數"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(String(localized: "（根據完成率、專注時長與碰卡一致性綜合計算）"))
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isPremium {
                // Score ring
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: CGFloat(score) / 100.0)
                        .stroke(
                            scoreColor(score),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 2) {
                        Text("\(score)")
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)
                        Text("/100")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 140, height: 140)

                // Sub-score breakdown
                if let result = viewModel.focusScoreResult {
                    HStack(spacing: 16) {
                        subScoreLabel(
                            title: String(localized: "完成率"),
                            value: "\(Int((result.completionRate * 100).rounded()))%",
                            weight: "60%"
                        )
                        subScoreLabel(
                            title: String(localized: "時長"),
                            value: "\(Int((result.durationScore * 100).rounded()))%",
                            weight: "30%"
                        )
                        subScoreLabel(
                            title: String(localized: "一致性"),
                            value: "\(Int((result.consistencyScore * 100).rounded()))%",
                            weight: "10%"
                        )
                    }
                }
            } else {
                ZStack {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 10)
                    Circle()
                        .trim(from: 0, to: 0.62)
                        .stroke(
                            themeManager.themeColor.opacity(0.35),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    VStack(spacing: 8) {
                        maskedValue(width: 72, height: 18)
                        maskedValue(width: 40, height: 12)
                    }
                }
                .frame(width: 140, height: 140)

                HStack(spacing: 16) {
                    subScoreLabel(title: String(localized: "完成率"), value: nil, weight: nil)
                    subScoreLabel(title: String(localized: "時長"), value: nil, weight: nil)
                    subScoreLabel(title: String(localized: "一致性"), value: nil, weight: nil)
                }
            }

            // Contextual message
            Text(focusScoreMessage(score))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPremium {
                showPaywall = true
            }
        }
    }

    private func subScoreLabel(title: String, value: String?, weight: String?) -> some View {
        VStack(spacing: 2) {
            if let value {
                Text(value)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
            } else {
                maskedValue(width: 44, height: 14)
            }
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let weight {
                Text(weight)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func scoreColor(_ score: Int) -> Color {
        switch score {
        case 80...100: return .green
        case 60..<80: return themeManager.themeColor
        case 40..<60: return .yellow
        default: return .red
        }
    }

    private func focusScoreMessage(_ score: Int) -> String {
        switch score {
        case 80...100: return String(localized: "本週狀態極佳，保持下去")
        case 60..<80: return String(localized: "不錯的一週，還有進步空間")
        case 40..<60: return String(localized: "本週稍微分心了，下週再來")
        default: return String(localized: "這週有點難熬，沒關係，明天繼續")
        }
    }

    // MARK: - Completion Rate Card (Task 2c: with mode badge)

    private func completionRateCard(rate: Double, isPremium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "完成率"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(String(localized: "（專注期間沒有中途緊急停止的比例）"))
                .font(.caption)
                .foregroundColor(.gray)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if isPremium {
                    Text("\(Int(rate.rounded()))")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("%")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                } else {
                    maskedValue(width: 54, height: 22)
                    maskedValue(width: 14, height: 10)
                }
            }

            // Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isPremium ? themeManager.themeColor : themeManager.themeColor.opacity(0.45))
                        .frame(width: geo.size.width * min(isPremium ? rate / 100.0 : 0.68, 1.0))
                }
            }
            .frame(height: 8)

            // Mode badges (Task 2c)
            if let modes = viewModel.modeRates {
                HStack(spacing: 12) {
                    if let classicRate = modes.classicRate {
                        modeBadge(
                            mode: String(localized: "Classic"),
                            rate: classicRate,
                            count: modes.classicCount,
                            isPremium: isPremium
                        )
                    }
                    if let timerRate = modes.timerRate {
                        modeBadge(
                            mode: String(localized: "Timer"),
                            rate: timerRate,
                            count: modes.timerCount,
                            isPremium: isPremium
                        )
                    }
                }
                .padding(.top, 4)
            }

            if !isPremium {
                Text(completionRateMessage(rate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPremium {
                showPaywall = true
            }
        }
    }

    private func modeBadge(mode: String, rate: Double, count: Int, isPremium: Bool) -> some View {
        HStack(spacing: 4) {
            Text(mode)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(themeManager.themeColor.opacity(0.7))
                )
            if isPremium {
                Text("\(Int((rate * 100).rounded()))%")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                Text("(\(count))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                maskedValue(width: 34, height: 10)
                maskedValue(width: 20, height: 8)
            }
        }
    }

    // MARK: - Peak Time Card (Task 3)

    private func peakTimeCard(result: FocusScoreCalculator.PeakTimeResult, isPremium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "最佳專注時段"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if result.daysNeeded > 0 {
                // Not enough data
                Text(isPremium
                     ? String(localized: "繼續使用 \(result.daysNeeded) 天後解鎖")
                     : String(localized: "繼續累積使用紀錄後解鎖更多分析"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else if let bestHour = result.bestHour {
                if isPremium {
                    Text(String(localized: "根據你的歷史數據，\(formatHour(bestHour)) 是你專注效果最好的時段"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                } else {
                    Text(String(localized: "你的專注表現會在特定時段明顯提升"))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                }

                // Hour score bar chart (hours with scores)
                if !result.hourScores.isEmpty {
                    peakTimeBarChart(hourScores: result.hourScores, bestHour: bestHour, isPremium: isPremium)
                }
            } else {
                Text(String(localized: "資料不足"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if !isPremium {
                showPaywall = true
            }
        }
    }

    private func peakTimeBarChart(hourScores: [Int: Double], bestHour: Int, isPremium: Bool) -> some View {
        let maxScore = hourScores.values.max() ?? 1

        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(6..<24, id: \.self) { hour in
                let score = hourScores[hour]
                let fraction = score.map { CGFloat($0) / CGFloat(maxScore) } ?? 0
                let isBest = hour == bestHour

                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(score != nil
                              ? (isBest ? themeManager.themeColor : themeManager.themeColor.opacity(0.5))
                              : Color(.systemGray5))
                        .frame(height: max(fraction * 60, score != nil ? 4 : 2))

                    if hour % 3 == 0 {
                        if isPremium {
                            Text("\(hour)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        } else {
                            Text(timeOfDayLabel(for: hour))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("")
                            .font(.system(size: 9))
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 80)
    }

    // MARK: - Optimal Session Card (Task 4)

    private func optimalSessionCard(result: FocusScoreCalculator.OptimalSessionResult, isPremium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "target")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "最佳專注時長"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            if case .insufficientData = result.suggestion {
                Text(String(localized: "資料不足，繼續累積更多專注紀錄"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 12)
            } else {
                // Show timer optimal and classic natural
                HStack(spacing: 16) {
                    if let timerMin = result.timerOptimalMinutes {
                        VStack(spacing: 4) {
                            if isPremium {
                                Text("\(timerMin)")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                            } else {
                                maskedValue(width: 48, height: 18)
                            }
                            Text(String(localized: "分鐘"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Timer")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(themeManager.themeColor.opacity(0.7)))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    if let classicSec = result.classicNaturalSeconds {
                        VStack(spacing: 4) {
                            if isPremium {
                                Text("\(FocusScoreCalculator.roundToNearest5(classicSec))")
                                    .font(.system(size: 28, weight: .bold, design: .rounded))
                            } else {
                                maskedValue(width: 48, height: 18)
                            }
                            Text(String(localized: "分鐘"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Classic")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(themeManager.themeColor.opacity(0.7)))
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                // Suggestion text
                if isPremium {
                    switch result.suggestion {
                    case .tryLonger(let minutes):
                        Text(String(localized: "試試看調到 \(minutes) 分鐘——你的大腦其實可以更多。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    case .tryShorter(let minutes):
                        Text(String(localized: "先把目標設在 \(minutes) 分鐘——撐得完比撐得久更重要。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    case .justRight:
                        Text(String(localized: "你目前的設定很適合你。"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    case .insufficientData:
                        SwiftUI.EmptyView()
                    }
                } else {
                    Text(optimalSessionMessage(result.suggestion))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Habit Formation Card (Task 5)

    private func habitFormationCard(result: HabitCurveCalculator.HabitResult, isPremium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "習慣養成"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            // Stage badge
            HStack(spacing: 8) {
                Text(result.stage.localizedName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(stageColor(result.stage))
                    )

                if isPremium {
                    Text(String(localized: "第 \(result.activeDays) 天"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(String(localized: "持續累積中"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            // Progress details
            if result.activeDays >= 7 {
                if isPremium {
                    // Autonomy ratio
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "自主比例"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Int((result.autonomyRatio * 100).rounded()))%")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(stageColor(result.stage))
                                    .frame(width: geo.size.width * min(CGFloat(result.autonomyRatio), 1.0))
                            }
                        }
                        .frame(height: 8)

                        // Stage thresholds indicator
                        HStack {
                            Text("0%")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("40%")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("75%")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Text("100%")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Days to automation
                    if let daysToAuto = result.daysToAutomation {
                        Text(String(localized: "預計還需 \(daysToAuto) 天達到自動化"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(String(localized: "自主比例"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            maskedValue(width: 36, height: 12)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemGray5))
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(stageColor(result.stage).opacity(0.45))
                                    .frame(width: geo.size.width * 0.58)
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Circle().fill(.secondary.opacity(0.4)).frame(width: 5, height: 5)
                            Spacer()
                            Circle().fill(.secondary.opacity(0.4)).frame(width: 5, height: 5)
                            Spacer()
                            Circle().fill(.secondary.opacity(0.4)).frame(width: 5, height: 5)
                            Spacer()
                            Circle().fill(.secondary.opacity(0.4)).frame(width: 5, height: 5)
                        }
                    }

                    Text(String(localized: "繼續使用後，這裡會顯示更完整的習慣分析"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            } else {
                Text(String(localized: "累積 7 天活躍數據後解鎖詳細分析"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func stageColor(_ stage: HabitCurveCalculator.HabitStage) -> Color {
        switch stage {
        case .deliberate: return .orange
        case .transition: return .yellow
        case .automated: return .green
        }
    }

    // MARK: - Week Trend Card

    private func weekTrendCard(trend: [WeekData], isPremium: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(themeManager.themeColor)
                    .font(.caption)
                Text(String(localized: "週趨勢"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Text(String(localized: "（過去四週的每週專注總時長變化）"))
                .font(.caption)
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()

                // Delta vs last week
                if trend.count >= 2 {
                    let current = trend[trend.count - 1].duration
                    let previous = trend[trend.count - 2].duration
                    let delta = previous > 0 ? ((current - previous) / previous) * 100.0 : 0

                    if abs(delta) > 0.5 {
                        if isPremium {
                            HStack(spacing: 2) {
                                Image(systemName: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption2)
                                Text("\(Int(abs(delta.rounded())))%")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                            .foregroundStyle(delta > 0 ? .green : .red)
                        } else {
                            Text(delta > 0 ? String(localized: "較上週更穩定") : String(localized: "較上週有回落"))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(delta > 0 ? .green : .red)
                        }
                    }
                }
            }

            trendBars(trend: trend, isPremium: isPremium)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    // MARK: - Trend Bars

    private func trendBars(trend: [WeekData], isPremium: Bool) -> some View {
        let maxDuration = trend.map(\.duration).max() ?? 1

        return HStack(alignment: .bottom, spacing: 8) {
            ForEach(Array(trend.enumerated()), id: \.element.id) { index, week in
                let fraction = maxDuration > 0 ? CGFloat(week.duration) / CGFloat(maxDuration) : 0
                let isCurrentWeek = Calendar.current.isDate(week.weekStart, equalTo: Date(), toGranularity: .weekOfYear)

                VStack(spacing: 6) {
                    if isPremium {
                        Text(formatDurationCompact(week.duration))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        maskedValue(width: 28, height: 10)
                    }

                    RoundedRectangle(cornerRadius: 4)
                        .fill(isCurrentWeek ? themeManager.themeColor : themeManager.themeColor.opacity(0.35))
                        .frame(height: max(fraction * 80, 4))

                    if isPremium {
                        Text(weekLabel(week.weekStart))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text(trendLabel(for: index, count: trend.count))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 120)
    }

    private func weekLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    // MARK: - Helpers

    private func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(interval, 0))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    private func formatDurationCompact(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(interval, 0))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        if hours > 0 && minutes > 0 {
            return "\(hours)h\(minutes)m"
        } else if hours > 0 {
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    private func formatHour(_ hour: Int) -> String {
        var comps = DateComponents()
        comps.hour = max(0, min(23, hour))
        let date = Calendar.current.date(from: comps) ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func maskedValue(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(Color(.systemGray4).opacity(0.75))
            .frame(width: width, height: height)
    }

    private func completionRateMessage(_ rate: Double) -> String {
        switch rate {
        case 80...:
            return String(localized: "你的專注完成度很高")
        case 60..<80:
            return String(localized: "你的完成表現已經不錯了")
        case 40..<60:
            return String(localized: "本週還有一些中斷空間")
        default:
            return String(localized: "本週比較容易提早結束")
        }
    }

    private func optimalSessionMessage(_ suggestion: FocusScoreCalculator.OptimalSuggestion) -> String {
        switch suggestion {
        case .tryLonger(_):
            return String(localized: "你可能會從更長一點的專注節奏受益")
        case .tryShorter(_):
            return String(localized: "你可能更適合更短、更穩定的專注節奏")
        case .justRight:
            return String(localized: "目前的節奏看起來很適合你")
        case .insufficientData:
            return String(localized: "資料還不夠，先累積更多紀錄")
        }
    }

    private func timeOfDayLabel(for hour: Int) -> String {
        switch hour {
        case 6..<9: return String(localized: "清晨")
        case 9..<12: return String(localized: "上午")
        case 12..<14: return String(localized: "中午")
        case 14..<18: return String(localized: "下午")
        case 18..<22: return String(localized: "晚上")
        default: return String(localized: "夜間")
        }
    }

    private func trendLabel(for index: Int, count: Int) -> String {
        if count == 4 {
            switch index {
            case 3: return String(localized: "本週")
            case 2: return String(localized: "上週")
            case 1: return String(localized: "前週")
            default: return String(localized: "更早")
            }
        }
        return String(localized: "趨勢")
    }
}

#Preview {
    ReportView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(SubscriptionManager.shared)
}
