import Foundation
import SwiftData
import SwiftUI

struct WeekData: Identifiable {
    let id = UUID()
    let weekStart: Date
    let duration: TimeInterval
    let sessionCount: Int
}

struct ProfileDuration: Identifiable {
    let id: UUID
    let name: String
    let duration: TimeInterval
}

@MainActor
class ReportViewModel: ObservableObject {
    // Free tier metrics
    @Published var totalBlockDuration: TimeInterval = 0
    @Published var sessionCount: Int = 0
    @Published var averageSessionDuration: TimeInterval = 0
    @Published var topProfiles: [ProfileDuration] = []

    // Premium tier metrics (nil when free)
    @Published var focusScoreResult: FocusScoreCalculator.FocusScoreResult?
    @Published var modeRates: FocusScoreCalculator.ModeCompletionRates?
    @Published var peakTimeResult: FocusScoreCalculator.PeakTimeResult?
    @Published var optimalSessionResult: FocusScoreCalculator.OptimalSessionResult?
    @Published var habitResult: HabitCurveCalculator.HabitResult?
    @Published var weekTrend: [WeekData]?

    // Legacy convenience accessors
    var completionRate: Double? {
        guard let result = focusScoreResult else { return nil }
        return result.completionRate * 100.0
    }
    var focusScore: Int? { focusScoreResult?.focusScore }

    private let calendar = Calendar.current

    func load(context: ModelContext, isPremium: Bool) {
        let weekStart = startOfCurrentWeek()

        loadFreeTierMetrics(context: context, since: weekStart)

        // Always load premium metrics so cards can render real data behind the masked preview
        loadPremiumMetrics(context: context, since: weekStart)
    }

    // MARK: - Free Tier Metrics

    private func loadFreeTierMetrics(context: ModelContext, since weekStart: Date) {
        let sessions = completedSessions(since: weekStart, in: context)

        // Total block duration
        totalBlockDuration = sessions.reduce(0.0) { sum, session in
            guard let end = session.endTime else { return sum }
            let clippedStart = max(session.startTime, weekStart)
            return sum + end.timeIntervalSince(clippedStart)
        }

        // Session count
        sessionCount = sessions.count

        // Average session duration
        averageSessionDuration = sessionCount > 0 ? totalBlockDuration / Double(sessionCount) : 0

        // Top 3 profiles by duration
        var profileMap: [UUID: (name: String, duration: TimeInterval)] = [:]
        for session in sessions {
            let profileId = session.blockedProfile.id
            let profileName = session.blockedProfile.name
            guard let end = session.endTime else { continue }
            let clippedStart = max(session.startTime, weekStart)
            let dur = end.timeIntervalSince(clippedStart)
            let existing = profileMap[profileId]
            profileMap[profileId] = (
                name: profileName,
                duration: (existing?.duration ?? 0) + dur
            )
        }
        topProfiles = profileMap
            .map { ProfileDuration(id: $0.key, name: $0.value.name, duration: $0.value.duration) }
            .sorted { $0.duration > $1.duration }
            .prefix(3)
            .map { $0 }
    }

    // MARK: - Premium Tier Metrics

    private func loadPremiumMetrics(context: ModelContext, since weekStart: Date) {
        let sessions = completedSessions(since: weekStart, in: context)

        // Qualified sessions (>= 10 min)
        let qualified = FocusScoreCalculator.qualifiedSessions(from: sessions)

        // Emergency unlock events → session IDs
        let emergencyEvents = EmergencyUnlockEvent.events(since: weekStart, in: context)
        let emergencySessionIds = Set(emergencyEvents.map { $0.sessionId })

        // Active days this week (days where dayActiveScore > 0)
        let nfcTaps = NFCTapEvent.tapEvents(since: weekStart, in: context)
        let manualIds = HabitCurveCalculator.manualTapSessionIds(sessions: sessions, nfcTaps: nfcTaps)
        let activeDaysThisWeek = countActiveDaysThisWeek(
            sessions: sessions,
            emergencySessionIds: emergencySessionIds,
            manualTapSessionIds: manualIds,
            weekStart: weekStart
        )

        // Weekly effective seconds from qualified sessions only
        let weeklyEffectiveSeconds = qualified.reduce(0.0) { sum, session in
            guard let end = session.endTime else { return sum }
            let clippedStart = max(session.startTime, weekStart)
            return sum + end.timeIntervalSince(clippedStart)
        }

        // Task 2b: Focus Score
        focusScoreResult = FocusScoreCalculator.computeFocusScore(
            qualifiedSessions: qualified,
            emergencySessionIds: emergencySessionIds,
            activeDaysThisWeek: activeDaysThisWeek,
            weeklyEffectiveSeconds: weeklyEffectiveSeconds
        )

        // Task 2c: Mode completion rates
        modeRates = FocusScoreCalculator.completionRatesByMode(
            qualifiedSessions: qualified,
            emergencySessionIds: emergencySessionIds
        )

        // Task 3: Peak Focus Time (uses all-time qualified sessions)
        let allSessions = allCompletedSessions(in: context)
        let allQualified = FocusScoreCalculator.qualifiedSessions(from: allSessions)
        let allEmergencyEvents = EmergencyUnlockEvent.events(
            since: Date.distantPast, in: context
        )
        let allEmergencyIds = Set(allEmergencyEvents.map { $0.sessionId })
        let allNfcTaps = NFCTapEvent.tapEvents(since: Date.distantPast, in: context)

        let firstSessionDate = allSessions.last?.startTime  // sorted by startTime desc

        peakTimeResult = FocusScoreCalculator.computePeakTime(
            qualifiedSessions: allQualified,
            emergencySessionIds: allEmergencyIds,
            allManualTaps: allNfcTaps,
            firstSessionDate: firstSessionDate
        )

        // Task 4: Optimal Session Length
        optimalSessionResult = FocusScoreCalculator.computeOptimalSession(
            qualifiedSessions: allQualified,
            emergencySessionIds: allEmergencyIds
        )

        // Task 5: Habit Formation
        habitResult = HabitCurveCalculator.computeHabit(
            allSessions: allSessions,
            emergencySessionIds: allEmergencyIds,
            nfcTaps: allNfcTaps
        )

        // Week-over-week trend (last 4 weeks)
        loadWeekTrend(context: context)
    }

    /// Count days this week where dayActiveScore > 0.
    private func countActiveDaysThisWeek(
        sessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>,
        manualTapSessionIds: Set<String>,
        weekStart: Date
    ) -> Int {
        let today = calendar.startOfDay(for: Date())
        var activeDays = 0

        for dayOffset in 0..<7 {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: weekStart) else {
                continue
            }
            guard dayDate <= today else { break }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayDate)!

            let sessionsOnDay = sessions.filter { session in
                session.startTime >= dayDate && session.startTime < nextDay
            }

            let score = HabitCurveCalculator.dayActivityScore(
                sessionsOnDay: sessionsOnDay,
                emergencySessionIds: emergencySessionIds,
                manualTapSessionIds: manualTapSessionIds
            )
            if score > 0 { activeDays += 1 }
        }

        return activeDays
    }

    private func loadWeekTrend(context: ModelContext) {
        var weeks: [WeekData] = []
        let now = Date()

        for weeksAgo in (0..<4).reversed() {
            guard let wStart = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: startOfCurrentWeek()) else {
                continue
            }
            guard let wEnd = calendar.date(byAdding: .weekOfYear, value: 1, to: wStart) else {
                continue
            }

            let sessions = completedSessions(from: wStart, to: min(wEnd, now), in: context)
            let duration = sessions.reduce(0.0) { sum, session in
                guard let end = session.endTime else { return sum }
                let clippedStart = max(session.startTime, wStart)
                let clippedEnd = min(end, wEnd)
                return sum + clippedEnd.timeIntervalSince(clippedStart)
            }

            weeks.append(WeekData(
                weekStart: wStart,
                duration: duration,
                sessionCount: sessions.count
            ))
        }

        weekTrend = weeks
    }

    // MARK: - Helpers

    private func startOfCurrentWeek() -> Date {
        var cal = calendar
        cal.firstWeekday = 2 // Monday
        return cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
    }

    private func completedSessions(since date: Date, in context: ModelContext) -> [BlockedProfileSession] {
        let descriptor = FetchDescriptor<BlockedProfileSession>(
            predicate: #Predicate { $0.endTime != nil && $0.startTime >= date },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func completedSessions(from start: Date, to end: Date, in context: ModelContext) -> [BlockedProfileSession] {
        let descriptor = FetchDescriptor<BlockedProfileSession>(
            predicate: #Predicate { $0.endTime != nil && $0.startTime >= start && $0.startTime < end },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func allCompletedSessions(in context: ModelContext) -> [BlockedProfileSession] {
        let descriptor = FetchDescriptor<BlockedProfileSession>(
            predicate: #Predicate { $0.endTime != nil },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }
}
