import SwiftUI

struct EmergencyView: View {
  @Environment(\.modelContext) private var context
  @Environment(\.dismiss) private var dismiss

  @EnvironmentObject var strategyManager: StrategyManager

  private var emergencyUnblocksRemaining: Int { strategyManager.getRemainingEmergencyUnblocks() }
  private var hasRemaining: Bool { strategyManager.getRemainingEmergencyUnblocks() > 0 }

  @State private var isPerformingEmergencyUnblock: Bool = false

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
        Text(String(localized: "緊急解鎖"))
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
                  Text(String(localized: "\(hoursRemaining) 小時後重置"))
                    .font(.caption)
                } else {
                  Text("\(String(localized: "重置日期")) \(nextResetDate, format: .dateTime.month().day())")
                    .font(.caption)
                }
              }
            }
          }
          .padding(.vertical, 6)

        }
      }

      Text(String(localized: "需要緊急停止嗎？長按按鈕確認解鎖，請謹慎使用。"))
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
          Text(String(localized: "剩餘次數"))
            .font(.subheadline)
            .foregroundColor(.secondary)
          Text("\(emergencyUnblocksRemaining)")
            .font(.title2).bold()
            .foregroundColor(hasRemaining ? .primary : .red)
        }
        Spacer()
      }

      Text(String(localized: "每週有固定的緊急解鎖次數，用完後下個月重置。"))
        .font(.footnote)
        .foregroundColor(.secondary)

      BreakGlassButton(tapsToShatter: 3) {
        ActionButton(
          title: String(localized: "確認緊急解鎖"),
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
        Text(String(localized: "次數已用完，下個月再試。"))
          .font(.footnote)
          .foregroundColor(.red)
      } else {
        Text(String(localized: "這次將消耗 1 次機會。"))
          .font(.footnote)
          .foregroundColor(.secondary)
      }

      // === REMOVE_BEFORE_APP_STORE: emergency-unlock reset for testing ===
      // Lifts the dev-only reset out of the #if DEBUG Settings → Debug
      // section so QA can refill the counter without switching to a Debug
      // build. Grep "REMOVE_BEFORE_APP_STORE" before submission.
      Button {
        strategyManager.resetEmergencyUnblocks()
      } label: {
        HStack(spacing: 4) {
          Image(systemName: "arrow.counterclockwise.circle")
          Text("重置次數（測試用）")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
      }
      .padding(.top, 4)
      // === END REMOVE_BEFORE_APP_STORE ===
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(.thinMaterial)
    )
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
