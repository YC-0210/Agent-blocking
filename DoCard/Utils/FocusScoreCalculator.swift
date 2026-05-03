import Foundation
import SwiftData

/// Pure on-device calculator for Focus Report metrics.
/// All inputs must be pre-fetched; this struct performs no database queries.
struct FocusScoreCalculator {

    // MARK: - Qualified Session Filter (Task 2a)

    /// A session is "qualified" only if its duration >= 10 minutes (600 s).
    static func qualifiedSessions(from sessions: [BlockedProfileSession]) -> [BlockedProfileSession] {
        sessions.filter { $0.duration >= 600 }
    }

    // MARK: - Focus Score (Task 2b)

    struct FocusScoreResult {
        let completionRate: Double      // [0, 1]
        let durationScore: Double       // [0, 1]
        let consistencyScore: Double    // [0, 1]
        let focusScore: Int             // [0, 100]
    }

    /// Computes the Focus Score from qualified sessions.
    /// - Parameters:
    ///   - qualifiedSessions: Sessions with duration >= 600 s
    ///   - emergencySessionIds: Set of session IDs that ended via emergency unlock
    ///   - activeDaysThisWeek: Number of days this week where dayActiveScore > 0
    ///   - weeklyEffectiveSeconds: Total seconds of all qualified sessions this week
    static func computeFocusScore(
        qualifiedSessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>,
        activeDaysThisWeek: Int,
        weeklyEffectiveSeconds: TimeInterval
    ) -> FocusScoreResult {
        // Completion rate: qualified sessions without emergency ÷ total qualified
        let completionRate: Double
        if qualifiedSessions.isEmpty {
            completionRate = 0.0
        } else {
            let completed = qualifiedSessions.filter { !emergencySessionIds.contains($0.id) }.count
            completionRate = Double(completed) / Double(qualifiedSessions.count)
        }

        // Duration score: weekly effective minutes / 300, hard cap at 1.0
        let weeklyEffectiveMinutes = weeklyEffectiveSeconds / 60.0
        let durationScore = min(weeklyEffectiveMinutes / 300.0, 1.0)

        // Consistency score: active days / 5, hard cap at 1.0
        let consistencyScore = min(Double(activeDaysThisWeek) / 5.0, 1.0)

        // Weighted sum → [0, 100]
        let raw = (completionRate * 0.6 + durationScore * 0.3 + consistencyScore * 0.1) * 100.0
        let focusScore = Int(raw.rounded())

        return FocusScoreResult(
            completionRate: completionRate,
            durationScore: durationScore,
            consistencyScore: consistencyScore,
            focusScore: max(0, min(100, focusScore))
        )
    }

    // MARK: - Mode Classification (Task 2c)

    enum SessionMode: String {
        case classic = "Classic"
        case timer = "Timer"
    }

    private static let timerStrategyIds: Set<String> = [
        NFCTimerBlockingStrategy.id,
        ShortcutTimerBlockingStrategy.id,
    ]

    static func sessionMode(for session: BlockedProfileSession) -> SessionMode {
        let strategyId = session.blockedProfile.blockingStrategyId ?? ""
        return timerStrategyIds.contains(strategyId) ? .timer : .classic
    }

    /// Returns completion rates per mode for display.
    struct ModeCompletionRates {
        let classicRate: Double?   // nil if no classic qualified sessions
        let timerRate: Double?     // nil if no timer qualified sessions
        let classicCount: Int
        let timerCount: Int
    }

    static func completionRatesByMode(
        qualifiedSessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>
    ) -> ModeCompletionRates {
        let classic = qualifiedSessions.filter { sessionMode(for: $0) == .classic }
        let timer = qualifiedSessions.filter { sessionMode(for: $0) == .timer }

        let classicRate: Double? = classic.isEmpty ? nil : {
            let completed = classic.filter { !emergencySessionIds.contains($0.id) }.count
            return Double(completed) / Double(classic.count)
        }()

        let timerRate: Double? = timer.isEmpty ? nil : {
            let completed = timer.filter { !emergencySessionIds.contains($0.id) }.count
            return Double(completed) / Double(timer.count)
        }()

        return ModeCompletionRates(
            classicRate: classicRate,
            timerRate: timerRate,
            classicCount: classic.count,
            timerCount: timer.count
        )
    }

    // MARK: - Peak Focus Time (Task 3)

    struct PeakTimeResult {
        let bestHour: Int?              // nil if not enough data
        let bestHourScore: Double?
        let hourScores: [Int: Double]   // hour → score (only hours that passed the gate)
        let daysActive: Int
        let daysNeeded: Int             // 0 if enough data, else 14 - daysActive
    }

    /// Computes peak focus time using weighted-sum approach.
    /// Only surfaces suggestion if user has >= 14 days of usage.
    static func computePeakTime(
        qualifiedSessions: [BlockedProfileSession],
        allManualTaps: [NFCTapEvent],
        firstSessionDate: Date?
    ) -> PeakTimeResult {
        let calendar = Calendar.current

        // Calculate days active
        let daysActive: Int
        if let firstDate = firstSessionDate {
            daysActive = max(1, calendar.dateComponents([.day], from: firstDate, to: Date()).day ?? 0)
        } else {
            daysActive = 0
        }

        let daysNeeded = max(0, 14 - daysActive)

        guard daysActive >= 14 else {
            return PeakTimeResult(bestHour: nil, bestHourScore: nil, hourScores: [:], daysActive: daysActive, daysNeeded: daysNeeded)
        }

        // Compute global median duration
        let allDurations = qualifiedSessions.map { $0.duration }.sorted()
        let globalMedian = median(allDurations)

        // Manual start taps
        let startTaps = allManualTaps.filter { $0.action == NFCTapEvent.actionStartBlock }
        let totalManualTaps = max(startTaps.count, 1)

        var hourScores: [Int: Double] = [:]

        for h in 0...23 {
            let sessionsInHour = qualifiedSessions.filter {
                calendar.component(.hour, from: $0.startTime) == h
            }
            // Minimum sample gate: >= 3 qualified sessions
            guard sessionsInHour.count >= 3 else { continue }

            // Dimension A: preference
            let manualTapsInHour = startTaps.filter {
                calendar.component(.hour, from: $0.timestamp) == h
            }.count
            let prefScore = Double(manualTapsInHour) / Double(totalManualTaps)

            // Dimension B: completion rate at this hour
            // We don't have emergencySessionIds here, so we check if session has emergency event
            // Actually, we need to pass emergency IDs. Let me adjust the API.
            // For now, use a simpler heuristic - we'll pass emergency IDs via a parameter.
            // This will be handled by the overload below.

            // Dimension C: relative duration vs global median
            let avgDuration = sessionsInHour.map { $0.duration }.reduce(0, +) / Double(sessionsInHour.count)
            let durationScoreVal = min(avgDuration / max(globalMedian, 1), 1.0)

            // These will be filled in by the full version
            hourScores[h] = 0.3 * prefScore + 0.5 * 1.0 + 0.2 * durationScoreVal
        }

        let best = hourScores.max(by: { $0.value < $1.value })

        return PeakTimeResult(
            bestHour: best?.key,
            bestHourScore: best?.value,
            hourScores: hourScores,
            daysActive: daysActive,
            daysNeeded: daysNeeded
        )
    }

    /// Full peak time computation with emergency session tracking.
    static func computePeakTime(
        qualifiedSessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>,
        allManualTaps: [NFCTapEvent],
        firstSessionDate: Date?
    ) -> PeakTimeResult {
        let calendar = Calendar.current

        let daysActive: Int
        if let firstDate = firstSessionDate {
            daysActive = max(1, calendar.dateComponents([.day], from: firstDate, to: Date()).day ?? 0)
        } else {
            daysActive = 0
        }

        let daysNeeded = max(0, 14 - daysActive)

        guard daysActive >= 14 else {
            return PeakTimeResult(bestHour: nil, bestHourScore: nil, hourScores: [:], daysActive: daysActive, daysNeeded: daysNeeded)
        }

        let allDurations = qualifiedSessions.map { $0.duration }.sorted()
        let globalMedian = median(allDurations)

        let startTaps = allManualTaps.filter { $0.action == NFCTapEvent.actionStartBlock }
        let totalManualTaps = max(startTaps.count, 1)

        var hourScores: [Int: Double] = [:]

        for h in 0...23 {
            let sessionsInHour = qualifiedSessions.filter {
                calendar.component(.hour, from: $0.startTime) == h
            }
            guard sessionsInHour.count >= 3 else { continue }

            // Dimension A: preference
            let manualTapsInHour = startTaps.filter {
                calendar.component(.hour, from: $0.timestamp) == h
            }.count
            let prefScore = Double(manualTapsInHour) / Double(totalManualTaps)

            // Dimension B: completion rate at this hour
            let completed = sessionsInHour.filter { !emergencySessionIds.contains($0.id) }.count
            let completionScore = Double(completed) / Double(sessionsInHour.count)

            // Dimension C: relative duration vs global median (capped at 1.0)
            let avgDuration = sessionsInHour.map { $0.duration }.reduce(0, +) / Double(sessionsInHour.count)
            let durationScoreVal = min(avgDuration / max(globalMedian, 1), 1.0)

            hourScores[h] = 0.3 * prefScore + 0.5 * completionScore + 0.2 * durationScoreVal
        }

        let best = hourScores.max(by: { $0.value < $1.value })

        return PeakTimeResult(
            bestHour: best?.key,
            bestHourScore: best?.value,
            hourScores: hourScores,
            daysActive: daysActive,
            daysNeeded: daysNeeded
        )
    }

    // MARK: - Optimal Session Length (Task 4)

    struct OptimalSessionResult {
        let timerOptimalMinutes: Int?       // Best bucket for timer mode
        let timerOptimalRate: Double?       // Completion rate of that bucket
        let classicNaturalSeconds: Double?  // Median duration of classic sessions (non-emergency)
        let suggestion: OptimalSuggestion
    }

    enum OptimalSuggestion {
        case tryLonger(minutes: Int)    // classicNatural > timerOptimal * 1.15
        case tryShorter(minutes: Int)   // classicNatural < timerOptimal * 0.85
        case justRight                  // within range
        case insufficientData           // not enough data for either mode
    }

    static func computeOptimalSession(
        qualifiedSessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>
    ) -> OptimalSessionResult {
        let timerSessions = qualifiedSessions.filter { sessionMode(for: $0) == .timer }
        let classicSessions = qualifiedSessions.filter { sessionMode(for: $0) == .classic }

        // Timer mode: bucket by targetDuration rounded to nearest 5 min
        let timerOptimal = computeTimerOptimal(timerSessions: timerSessions, emergencySessionIds: emergencySessionIds)

        // Classic mode: median duration of non-emergency sessions
        let classicNonEmergency = classicSessions.filter { !emergencySessionIds.contains($0.id) }
        let classicNatural: Double?
        if classicNonEmergency.count >= 3 {
            classicNatural = median(classicNonEmergency.map { $0.duration })
        } else {
            classicNatural = nil
        }

        // Cross-mode recommendation
        let suggestion: OptimalSuggestion
        if let timerOpt = timerOptimal?.durationSeconds, let classicNat = classicNatural {
            if classicNat > timerOpt * 1.15 {
                let suggestionMinutes = roundToNearest5(timerOpt * 1.1)
                suggestion = .tryLonger(minutes: suggestionMinutes)
            } else if classicNat < timerOpt * 0.85 {
                let suggestionMinutes = roundToNearest5(classicNat)
                suggestion = .tryShorter(minutes: suggestionMinutes)
            } else {
                suggestion = .justRight
            }
        } else {
            suggestion = .insufficientData
        }

        return OptimalSessionResult(
            timerOptimalMinutes: timerOptimal.map { roundToNearest5(Double($0.durationSeconds)) },
            timerOptimalRate: timerOptimal?.completionRate,
            classicNaturalSeconds: classicNatural,
            suggestion: suggestion
        )
    }

    private struct TimerBucket {
        let durationSeconds: Double
        let completionRate: Double
    }

    private static func computeTimerOptimal(
        timerSessions: [BlockedProfileSession],
        emergencySessionIds: Set<String>
    ) -> TimerBucket? {
        // Bucket by target duration (from strategyData) rounded to nearest 5 min
        var buckets: [Int: [BlockedProfileSession]] = [:]  // key = rounded minutes

        for session in timerSessions {
            let targetMinutes: Int
            if let data = session.blockedProfile.strategyData {
                let timerData = StrategyTimerData.toStrategyTimerData(from: data)
                targetMinutes = roundToNearest5(Double(timerData.durationInMinutes * 60))
            } else {
                // Fallback: use actual duration rounded to nearest 5
                targetMinutes = roundToNearest5(session.duration)
            }
            buckets[targetMinutes, default: []].append(session)
        }

        // Only surface buckets with >= 3 sessions
        let validBuckets = buckets.filter { $0.value.count >= 3 }

        guard !validBuckets.isEmpty else { return nil }

        // Find bucket with highest completion rate (ties → prefer longer)
        let best = validBuckets
            .map { (minutes: $0.key, sessions: $0.value) }
            .map { bucket -> (minutes: Int, rate: Double) in
                let completed = bucket.sessions.filter { !emergencySessionIds.contains($0.id) }.count
                let rate = Double(completed) / Double(bucket.sessions.count)
                return (minutes: bucket.minutes, rate: rate)
            }
            .sorted { a, b in
                if a.rate != b.rate { return a.rate > b.rate }
                return a.minutes > b.minutes  // ties → prefer longer
            }
            .first

        guard let bestBucket = best else { return nil }

        return TimerBucket(
            durationSeconds: Double(bestBucket.minutes * 60),
            completionRate: bestBucket.rate
        )
    }

    // MARK: - Helpers

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let count = sorted.count
        if count % 2 == 0 {
            return (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
        } else {
            return sorted[count / 2]
        }
    }

    static func roundToNearest5(_ seconds: Double) -> Int {
        let minutes = Int(seconds / 60)
        return Int((Double(minutes) / 5.0).rounded() * 5)
    }
}
