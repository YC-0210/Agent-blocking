import Foundation
import SwiftData

/// Habit formation calculator using Mitscherlich growth model.
/// All calculations are on-device only — no network calls.
struct HabitCurveCalculator {

    // MARK: - Daily Activity Score (Task 5a)

    /// Computes the activity score for a single day.
    /// - Manual tap (self-initiated NFC session) → 1.0
    /// - Scheduled session completed (no emergency) → 0.5
    /// - Scheduled session + emergency unlock → 0.25
    /// - No session → 0.0
    ///
    /// Uses the `triggerSource` and `endReason` fields directly on the session.
    static func dayActivityScore(
        sessionsOnDay: [BlockedProfileSession],
        emergencySessionIds: Set<String>,
        manualTapSessionIds: Set<String>
    ) -> Double {
        guard !sessionsOnDay.isEmpty else { return 0.0 }

        // Take the highest-scoring session for the day
        var bestScore = 0.0
        for session in sessionsOnDay {
            let score: Double
            switch session.triggerSource {
            case "manual":
                score = 1.0
            case "scheduled":
                score = session.endReason == "emergency_unlock" ? 0.25 : 0.5
            default:
                // "shortcut", "deeplink", or unknown — treat as scheduled weight
                score = 0.5
            }
            bestScore = max(bestScore, score)
        }
        return bestScore
    }

    /// Determines which session IDs were self-initiated (manual).
    /// Now reads `triggerSource` directly instead of the 60-second NFCTapEvent time-window join.
    /// NFCTapEvent and EmergencyUnlockEvent tables are kept as audit history.
    static func manualTapSessionIds(
        sessions: [BlockedProfileSession],
        nfcTaps: [NFCTapEvent]
    ) -> Set<String> {
        var result = Set<String>()
        for session in sessions {
            if session.triggerSource == "manual" {
                result.insert(session.id)
            }
        }
        return result
    }

    // MARK: - Daily Score History

    struct DayScore {
        let date: Date
        let score: Double
        let dayIndex: Int  // 0-based index from first active day
    }

    /// Computes daily activity scores for all days from firstActiveDay to today.
    static func dailyScores(
        allSessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>,
        manualTapSessionIds: Set<String>
    ) -> [DayScore] {
        let calendar = Calendar.current
        let completedSessions = allSessions.filter { $0.endTime != nil }

        guard let earliest = completedSessions.map({ $0.startTime }).min() else {
            return []
        }

        let firstDay = calendar.startOfDay(for: earliest)
        let today = calendar.startOfDay(for: Date())

        guard let totalDays = calendar.dateComponents([.day], from: firstDay, to: today).day else {
            return []
        }

        var scores: [DayScore] = []
        for dayOffset in 0...totalDays {
            guard let dayDate = calendar.date(byAdding: .day, value: dayOffset, to: firstDay) else {
                continue
            }
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayDate)!

            let sessionsOnDay = completedSessions.filter { session in
                session.startTime >= dayDate && session.startTime < nextDay
            }

            let score = dayActivityScore(
                sessionsOnDay: sessionsOnDay,
                emergencySessionIds: emergencySessionIds,
                manualTapSessionIds: manualTapSessionIds
            )

            scores.append(DayScore(date: dayDate, score: score, dayIndex: dayOffset))
        }

        return scores
    }

    // MARK: - Mitscherlich Growth Model (Task 5b)

    struct HabitResult {
        let stage: HabitStage
        let autonomyRatio: Double       // 7-day rolling window
        let activeDays: Int
        let personalCeiling: Double     // A parameter
        let timeConstant: Double?       // τ parameter (nil if < 7 active days)
        let daysToAutomation: Int?      // nil if already automated or < 7 active days
        let predictedScore: Double?     // Current predicted score from model
    }

    enum HabitStage: String {
        case deliberate = "刻意執行期"     // autonomyRatio < 0.40
        case transition = "過渡期"         // 0.40 ≤ ratio < 0.75
        case automated = "自動化期"        // ratio ≥ 0.75

        var localizedName: String {
            switch self {
            case .deliberate: return String(localized: "刻意執行期")
            case .transition: return String(localized: "過渡期")
            case .automated:  return String(localized: "自動化期")
            }
        }
    }

    /// Main entry point for habit formation analysis.
    static func computeHabit(
        allSessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>,
        nfcTaps: [NFCTapEvent]
    ) -> HabitResult {
        let manualIds = manualTapSessionIds(sessions: allSessions, nfcTaps: nfcTaps)
        let scores = dailyScores(
            allSessions: allSessions,
            emergencySessionIds: emergencySessionIds,
            manualTapSessionIds: manualIds
        )

        let activeDayScores = scores.filter { $0.score > 0 }
        let activeDays = activeDayScores.count

        // Autonomy ratio: 7-day rolling window of active days
        let autonomyRatio = computeAutonomyRatio(
            scores: scores,
            manualTapSessionIds: manualIds,
            allSessions: allSessions
        )

        // Stage classification
        let stage: HabitStage
        if autonomyRatio >= 0.75 {
            stage = .automated
        } else if autonomyRatio >= 0.40 {
            stage = .transition
        } else {
            stage = .deliberate
        }

        // Below 7 active days: raw count only, no curve
        guard activeDays >= 7 else {
            return HabitResult(
                stage: stage,
                autonomyRatio: autonomyRatio,
                activeDays: activeDays,
                personalCeiling: 0,
                timeConstant: nil,
                daysToAutomation: nil,
                predictedScore: nil
            )
        }

        // Personal ceiling A = average daily activity score over last 14 active days (clamped to 1.0)
        let last14Active = activeDayScores.suffix(14)
        let personalCeiling = min(
            last14Active.map { $0.score }.reduce(0, +) / Double(max(last14Active.count, 1)),
            1.0
        )

        // Fit τ via grid search
        let tau = fitTimeConstant(activeDayScores: Array(activeDayScores), ceiling: personalCeiling)

        // Days to automation estimate
        let daysToAutomation: Int?
        if stage != .automated && personalCeiling > 0 {
            let target = 0.75 * personalCeiling
            if personalCeiling > target {
                // τ * ln(A / (A - target))
                let ratio = personalCeiling / (personalCeiling - target)
                let estimate = tau * log(ratio)
                let remaining = max(0, Int(ceil(estimate)) - activeDays)
                daysToAutomation = remaining > 0 ? remaining : nil
            } else {
                daysToAutomation = nil
            }
        } else {
            daysToAutomation = nil
        }

        // Current predicted score
        let currentDay = Double(activeDays)
        let predictedScore = personalCeiling * (1.0 - exp(-currentDay / tau))

        return HabitResult(
            stage: stage,
            autonomyRatio: autonomyRatio,
            activeDays: activeDays,
            personalCeiling: personalCeiling,
            timeConstant: tau,
            daysToAutomation: daysToAutomation,
            predictedScore: predictedScore
        )
    }

    // MARK: - Autonomy Ratio

    /// autonomyRatio = days with at least one manual session in last 7 active days
    ///                 ÷ total active days in last 7
    private static func computeAutonomyRatio(
        scores: [DayScore],
        manualTapSessionIds: Set<String>,
        allSessions: [BlockedProfileSession]
    ) -> Double {
        let calendar = Calendar.current
        let activeDays = scores.filter { $0.score > 0 }
        let last7Active = activeDays.suffix(7)

        guard !last7Active.isEmpty else { return 0.0 }

        let completedSessions = allSessions.filter { $0.endTime != nil }
        var daysWithManualTap = 0

        for dayScore in last7Active {
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayScore.date)!
            let sessionsOnDay = completedSessions.filter { session in
                session.startTime >= dayScore.date && session.startTime < nextDay
            }
            // Use triggerSource directly instead of NFCTapEvent join
            let hasManualSession = sessionsOnDay.contains { $0.triggerSource == "manual" }
            if hasManualSession {
                daysWithManualTap += 1
            }
        }

        return Double(daysWithManualTap) / Double(last7Active.count)
    }

    // MARK: - Mitscherlich Curve Fitting

    /// Fits τ using grid search over [1, 200] in steps of 0.5.
    /// Minimises sum of squared errors: (A * (1 - exp(-d/τ)) - observed)^2
    private static func fitTimeConstant(
        activeDayScores: [DayScore],
        ceiling: Double
    ) -> Double {
        guard !activeDayScores.isEmpty, ceiling > 0 else { return 30.0 }

        var bestTau = 30.0
        var bestError = Double.infinity

        // Grid search: τ from 1.0 to 200.0 in steps of 0.5
        var tau = 1.0
        while tau <= 200.0 {
            var totalError = 0.0
            for (index, dayScore) in activeDayScores.enumerated() {
                let d = Double(index + 1) // 1-based active day count
                let predicted = ceiling * (1.0 - exp(-d / tau))
                let diff = predicted - dayScore.score
                totalError += diff * diff
            }
            if totalError < bestError {
                bestError = totalError
                bestTau = tau
            }
            tau += 0.5
        }

        return bestTau
    }
}
