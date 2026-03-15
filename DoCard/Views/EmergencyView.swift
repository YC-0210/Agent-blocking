import SwiftUI

struct EmergencyView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss

  @EnvironmentObject var strategyManager: StrategyManager

  private var emergencyUnblocksRemaining: Int { strategyManager.getRemainingEmergencyUnblocks() }
  private var hasRemaining: Bool { strategyManager.getRemainingEmergencyUnblocks() > 0 }

  @State private var isPerformingEmergencyUnblock: Bool = false
  @State private var showFounderModeAlert: Bool = false
  @State private var founderModePassword: String = ""
  @State private var founderModeError: Bool = false

  var body: some View {
    ScrollView {
      VStack(spacing: 20) {
        header

        statusCard
      }
      .padding()
    }
    .onAppear {
      strategyManager.checkAndResetEmergencyUnblocks()
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(String(localized: "Emergency Access"))
          .font(.title2).bold()

        Spacer()

        HStack(spacing: 8) {
          HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath")
              .font(.caption)
              .foregroundColor(.secondary)

            Group {
              if let nextResetDate = strategyManager.getNextResetDate() {
                let timeUntilReset = nextResetDate.timeIntervalSinceNow
                if timeUntilReset <= 24 * 60 * 60 {  // Less than 24 hours
                  let hoursRemaining = max(1, Int(ceil(timeUntilReset / 3600)))
                  Text(String(localized: "Resets in \(hoursRemaining)h"))
                    .font(.caption)
                } else {
                  Text("\(String(localized: "Resets")) \(nextResetDate, format: .dateTime.month().day())")
                    .font(.caption)
                }
              }
            }
          }
          .padding(.vertical, 6)

          Menu {
            let currentPeriod = strategyManager.getResetPeriodInWeeks()

            Button {
              strategyManager.setResetPeriodInWeeks(2)
            } label: {
              if currentPeriod == 2 {
                Label(String(localized: "2 weeks"), systemImage: "checkmark")
              } else {
                Text(String(localized: "2 weeks"))
              }
            }

            Button {
              strategyManager.setResetPeriodInWeeks(4)
            } label: {
              if currentPeriod == 4 {
                Label(String(localized: "4 weeks"), systemImage: "checkmark")
              } else {
                Text(String(localized: "4 weeks"))
              }
            }

            Button {
              strategyManager.setResetPeriodInWeeks(6)
            } label: {
              if currentPeriod == 6 {
                Label(String(localized: "6 weeks"), systemImage: "checkmark")
              } else {
                Text(String(localized: "6 weeks"))
              }
            }

            Button {
              strategyManager.setResetPeriodInWeeks(8)
            } label: {
              if currentPeriod == 8 {
                Label(String(localized: "8 weeks"), systemImage: "checkmark")
              } else {
                Text(String(localized: "8 weeks"))
              }
            }
          } label: {
            Image(systemName: "gearshape.fill")
              .font(.caption)
              .foregroundColor(.secondary)
              .padding(8)
              .background(Circle().fill(Color.secondary.opacity(0.1)))
          }
          // SECURITY (V-03a): Prevent changing the reset period while
          // a session is active, which could be exploited to accelerate
          // emergency unlock counter resets.
          .disabled(strategyManager.isBlocking)
        }
      }

      Text(String(localized:
        "Tap the glass to reveal the emergency unblock button. Use only when absolutely necessary."
      ))
      .font(.callout)
      .foregroundColor(.secondary)
    }
    .padding(.top, 16)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        Image(systemName: hasRemaining ? "shield.lefthalf.filled" : "shield.slash")
          .font(.title3)
          .foregroundColor(hasRemaining ? .green : .red)
        VStack(alignment: .leading, spacing: 4) {
          Text(String(localized: "Unblocks remaining"))
            .font(.subheadline)
            .foregroundColor(.secondary)
          Text("\(emergencyUnblocksRemaining)")
            .font(.title2).bold()
            .foregroundColor(hasRemaining ? .primary : .red)
        }
        Spacer()
      }

      Text(String(localized: "You have a limited number of emergency unblocks."))
        .font(.footnote)
        .foregroundColor(.secondary)

      BreakGlassButton(tapsToShatter: 3) {
        ActionButton(
          title: String(localized: "Emergency Unblock"),
          backgroundColor: .red,
          iconName: "exclamationmark.triangle.fill",
          iconColor: .white,
          isLoading: isPerformingEmergencyUnblock,
          isDisabled: !hasRemaining
        ) {
          performEmergencyUnblock()
        }
      }
      .frame(height: 56)

      if !hasRemaining {
        Text(String(localized: "No emergency unblocks remaining. You're out of luck."))
          .font(.footnote)
          .foregroundColor(.red)
      } else {
        Text(String(localized: "This will reduce your remaining count by 1."))
          .font(.footnote)
          .foregroundColor(.secondary)
      }

      HStack {
        Spacer()
        Button {
          founderModePassword = ""
          founderModeError = false
          showFounderModeAlert = true
        } label: {
          Text("創辦人模式")
            .font(.caption2)
            .foregroundColor(.secondary.opacity(0.6))
        }
        .buttonStyle(.plain)
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.thinMaterial)
    )
    .alert("創辦人模式", isPresented: $showFounderModeAlert) {
      SecureField("請輸入密碼", text: $founderModePassword)
      Button("取消", role: .cancel) { }
      Button("確認") {
        if founderModePassword == "3962057301" {
          strategyManager.resetEmergencyUnblocks()
        } else {
          founderModeError = true
        }
      }
    } message: {
      if founderModeError {
        Text("密碼錯誤，請重新輸入。")
      } else {
        Text("輸入創辦人密碼以重置緊急解鎖次數。")
      }
    }
    .alert("密碼錯誤", isPresented: $founderModeError) {
      Button("好", role: .cancel) { }
    }
  }

  private func performEmergencyUnblock() {
    isPerformingEmergencyUnblock = true

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
      strategyManager.emergencyUnblock(context: context)
      isPerformingEmergencyUnblock = false
      dismiss()
    }
  }
}

struct EmergencyPreviewSheetHost: View {
  @State private var show: Bool = true

  var body: some View {
    Color.clear
      .sheet(isPresented: $show) {
        NavigationView { EmergencyView() }
          .presentationDetents([.medium])
          .presentationDragIndicator(.visible)
      }
  }
}

#Preview {
  EmergencyPreviewSheetHost()
    .environmentObject(StrategyManager())
    .defaultAppStorage(UserDefaults(suiteName: "preview")!)
}
