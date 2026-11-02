#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import SwiftUI

/// Only hardware input, the clock and OS writes are simulated. No session states are assigned here.
final class MaestroSessionHarness: @unchecked Sendable {
  static let shared = MaestroSessionHarness()
  private let defaults = UserDefaults(suiteName: "group.DO.version3")!
  let scanner = MaestroCardScanner()

  static var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone = TimeZone(identifier: "Asia/Taipei")!
    return value
  }

  static func date(hour: Int, minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: hour, minute: minute))!
  }

  var now: Date { Date(timeIntervalSince1970: defaults.double(forKey: "maestroClock")) }

  lazy var blocker = AppBlockerUtil(write: { [unowned self] plan in
    let wasOn = defaults.bool(forKey: "maestroShieldOn")
    if plan != nil {
      defaults.set(defaults.integer(forKey: "maestroBlockCalls") + 1, forKey: "maestroBlockCalls")
      if defaults.bool(forKey: "maestroStopped") {
        defaults.set(defaults.integer(forKey: "maestroReblocks") + 1, forKey: "maestroReblocks")
      }
    } else if wasOn {
      defaults.set(true, forKey: "maestroStopped")
    }
    defaults.set(plan != nil, forKey: "maestroShieldOn")
  })

  @MainActor
  func makeManager() -> StrategyManager {
    StrategyManager(
      appBlocker: blocker,
      makeStrategy: { [unowned self] id in
        if id == ManualBlockingStrategy.id { return ManualBlockingStrategy(appBlocker: blocker) }
        precondition(id == NFCBlockingStrategy.id, "Unexpected strategy in locking journey")
        return NFCBlockingStrategy(nfcScanner: scanner, appBlocker: blocker)
      },
      makeNFCScanner: { [unowned self] in scanner },
      systemEffect: { _ in },
      readEmergencyUses: { [unowned self] in defaults.integer(forKey: "maestroEmergencyUses") },
      writeEmergencyUses: { [unowned self] in defaults.set($0, forKey: "maestroEmergencyUses") })
  }

  @MainActor
  func deliverSchedule(hour: Int, minute: Int, context: ModelContext, manager: StrategyManager) {
    defaults.set(Self.date(hour: hour, minute: minute).timeIntervalSince1970, forKey: "maestroClock")
    guard let profile = try! BlockedProfiles.fetchProfiles(in: context).first else {
      preconditionFailure("Missing journey profile")
    }
    let snapshot = BlockedProfiles.getSnapshot(for: profile)
    // Simulate OS delivery to the real handler, including late/repeated callbacks.
    let activity = ScheduleTimerActivity(appBlocker: blocker)
    if hour >= 10 { activity.stop(for: snapshot) } else { activity.start(for: snapshot) }
    manager.loadActiveSession(context: context)
    manager.restoreScheduledSessionIfNeeded()
  }

  var shield: String { defaults.bool(forKey: "maestroShieldOn") ? "on" : "off" }
  var reblocks: Int { defaults.integer(forKey: "maestroReblocks") }
  var quota: Int { defaults.integer(forKey: "maestroEmergencyUses") }
}

final class MaestroCardScanner: NFCScannerUtil {
  private(set) var pending = false

  override func scan(profileName: String, isUnlocking: Bool = false) { pending = true }

  func deliverCard() {
    precondition(pending, "A real UI scan request must precede simulated card input")
    pending = false
    deliverReadResult(
      NFCResult(id: "maestro-card", payload: "valid-do-card-payload", DateScanned: SharedData.currentDate),
      expectedIds: expectedTagIds, invalidate: { _ in })
  }
}

/// Observation panel and external-event controls. It cannot start/stop a session directly.
struct MaestroSessionPanel: View {
  let container: ModelContainer
  @ObservedObject var manager: StrategyManager
  private let harness = MaestroSessionHarness.shared

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
      VStack(spacing: 2) {
        Text("Simulated hardware · \(harness.shield)")
          .accessibilityIdentifier("journey.shield")
        Text(manager.activeSessionStatus.isBlocking ? "active" : "idle")
          .accessibilityIdentifier("journey.state")
        Text(harness.scanner.pending ? "pending" : "none")
          .accessibilityIdentifier("journey.scan")
        Text(history).accessibilityIdentifier("journey.history")
        Text("quota=\(harness.quota);reblocks=\(harness.reblocks)")
          .accessibilityIdentifier("journey.safety")
        HStack {
          Button("Card") { harness.scanner.deliverCard() }
            .disabled(!harness.scanner.pending)
            .accessibilityIdentifier("journey.card")
          ForEach([0, 15, 60], id: \.self) { minute in
            Button(minute == 60 ? "10:00" : "9:\(minute)") {
              harness.deliverSchedule(hour: minute == 60 ? 10 : 9,
                minute: minute == 60 ? 0 : minute,
                context: container.mainContext, manager: manager)
            }
            .accessibilityIdentifier("journey.clock.\(minute)")
          }
        }
      }
      .font(.system(size: 11))
      .buttonStyle(.bordered)
      .padding(4)
      .frame(maxWidth: .infinity)
      .background(.black)
    }
  }

  private var history: String {
    // A separate context reads saved rows, rather than echoing the manager's in-memory state.
    let context = ModelContext(container)
    let sessions = try! context.fetch(FetchDescriptor<BlockedProfileSession>())
    let ended = sessions.filter { $0.endTime != nil }
    let audits = try! context.fetchCount(FetchDescriptor<EmergencyUnlockEvent>())
    let last = ended.sorted { $0.endTime! > $1.endTime! }.first
    return "saved=\(ended.count);reason=\(last?.endReason ?? "none");source=\(last?.triggerSource ?? "none");audits=\(audits)"
  }
}
#endif
