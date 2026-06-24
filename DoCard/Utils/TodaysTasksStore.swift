import Foundation

/// Owns the user's Today's Tasks (今日目標) — up to three Daily Tasks for the
/// current local day. The card reads from and mutates through this one type.
final class TodaysTasksStore: ObservableObject {
  static let maxGoals = 3

  @Published private(set) var goals: [DailyTask] = []

  private let defaults: UserDefaults
  private let now: () -> Date
  private let storageKey = "todaysTasks.v1"
  private var lastSeenDay: Date?

  init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
    self.defaults = defaults
    self.now = now
    load()
    refreshForCurrentDay()
  }

  /// Number of goals checked off — the numerator of the completion ring.
  var completedCount: Int { goals.filter(\.done).count }
  /// Number of goals set today — the denominator of the completion ring.
  var totalCount: Int { goals.count }

  /// Add a goal to today's list, up to `maxGoals`. A request beyond the cap is
  /// ignored.
  func addGoal(name: String, detail: String = "") {
    guard goals.count < Self.maxGoals else { return }
    goals.append(DailyTask(name: name, detail: detail))
    save()
  }

  /// Toggle a goal's done state.
  func toggleDone(_ task: DailyTask) {
    guard let index = goals.firstIndex(where: { $0.id == task.id }) else { return }
    goals[index].done.toggle()
    save()
  }

  /// Roll the list over to the current local day: if the local calendar day
  /// changed since the last save, drop completed goals and keep unfinished ones
  /// in order. Same-day is a no-op. Call on appear. The local-midnight boundary
  /// is intentionally separate from the noon focus-time reset on the main tab.
  func refreshForCurrentDay() {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: now())
    if let last = lastSeenDay, calendar.isDate(last, inSameDayAs: today) {
      return
    }
    if lastSeenDay != nil {
      goals = goals.filter { !$0.done }
    }
    lastSeenDay = today
    save()
  }

  // MARK: - Persistence (UserDefaults JSON, per ADR 0003 — not SwiftData)

  private struct Persisted: Codable {
    var goals: [DailyTask]
    var lastSeenDay: Date?
  }

  private func load() {
    guard let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode(Persisted.self, from: data)
    else { return }
    goals = decoded.goals
    lastSeenDay = decoded.lastSeenDay
  }

  private func save() {
    let payload = Persisted(goals: goals, lastSeenDay: lastSeenDay)
    guard let data = try? JSONEncoder().encode(payload) else { return }
    defaults.set(data, forKey: storageKey)
  }
}
