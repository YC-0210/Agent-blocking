import FamilyControls
import SwiftUI

struct AppPicker: View {
  private let stateUpdateTimer = Timer.publish(every: 1, on: .main, in: .common)
    .autoconnect()

  @Binding var selection: FamilyActivitySelection
  @Binding var isPresented: Bool

  var allowMode: Bool = false

  @EnvironmentObject var subscriptionManager: SubscriptionManager

  @State private var updateFlag: Bool = false
  @State private var refreshID: UUID = UUID()
  @State private var showLimitAlert: Bool = false
  @State private var showFreeLimitAlert: Bool = false
  @State private var showClearConfirmation: Bool = false
  @State private var showPaywall: Bool = false

  /// Current app count (applicationTokens includes expanded category apps)
  private var appCount: Int {
    selection.applicationTokens.count
  }

  /// The max allowed for the current tier
  private var appLimit: Int {
    if allowMode {
      return Entitlements.premiumAppLimit
    }
    return subscriptionManager.entitlements.appLimit
  }

  private var compactTitle: String {
    let displayText = FamilyActivityUtil.getCountDisplayText(selection, allowMode: allowMode)
    let action = allowMode ? String(localized: "allowed") : String(localized: "blocked")
    return "\(displayText) \(action)"
  }

  private var shouldShowWarning: Bool {
    return FamilyActivityUtil.shouldShowAllowModeWarning(selection, allowMode: allowMode)
  }

  /// Whether the current selection exceeds the 50-app Apple hard limit
  private var isOverLimit: Bool {
    return appCount > Entitlements.premiumAppLimit
  }

  private var hasSelection: Bool {
    return appCount > 0
  }

  /// Whether the current selection exceeds free tier limits
  private var exceedsFreeTierLimit: Bool {
    guard !subscriptionManager.isPremium, !allowMode else { return false }
    return appCount > Entitlements.freeAppLimit
  }

  /// Whether the current selection exceeds premium tier limits (Apple hard limit)
  private var exceedsPremiumLimit: Bool {
    return appCount > Entitlements.premiumAppLimit
  }

  /// Whether the Done button should be disabled
  private var isDoneDisabled: Bool {
    return exceedsFreeTierLimit || exceedsPremiumLimit
  }

  private func clearAll() {
    selection = FamilyActivitySelection(includeEntireCategory: true)
    refreshID = UUID()
  }

  private func handleDone() {
    if exceedsFreeTierLimit {
      showFreeLimitAlert = true
    } else if exceedsPremiumLimit {
      showLimitAlert = true
    } else {
      isPresented = false
    }
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 12) {
        ZStack {
          Text(verbatim: "Updating view state because of bug in iOS...")
            .foregroundStyle(.clear)
            .accessibilityHidden(true)
            .opacity(updateFlag ? 1 : 0)

          FamilyActivityPicker(selection: $selection)
            .id(refreshID)
        }

        // Count display
        HStack {
          Text(compactTitle)
            .font(.subheadline)
            .bold()
            .foregroundColor(.primary)

          Spacer()

          if shouldShowWarning {
            Image(systemName: "exclamationmark.triangle.fill")
              .foregroundColor(.orange)
              .font(.caption)
          }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal, 16)

        // Free tier inline limit gate
        if exceedsFreeTierLimit {
          HStack(spacing: 6) {
            Image(systemName: "lock.fill")
              .font(.caption)
              .foregroundStyle(.orange)
            Text(String(localized: "免費版最多阻擋 3 個 App，請減少選擇或升級 Premium"))
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
            Button(String(localized: "升級")) {
              showPaywall = true
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
          }
          .padding(12)
          .background(Color(.systemGray6))
          .cornerRadius(10)
          .padding(.horizontal, 16)
        } else if exceedsPremiumLimit {
          HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.red)
            Text(String(localized: "最多只能阻擋 50 個 App，請減少選擇"))
              .font(.caption)
              .foregroundStyle(.secondary)
            Spacer()
          }
          .padding(12)
          .background(Color(.systemGray6))
          .cornerRadius(10)
          .padding(.horizontal, 16)
        } else if !subscriptionManager.isPremium && !allowMode {
          HStack(spacing: 8) {
            Image(systemName: "info.circle.fill")
              .foregroundStyle(.orange)
              .font(.caption)
            Text(String(localized: "免費版最多阻擋 3 個 App"))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(12)
          .background(Color(.systemGray6))
          .cornerRadius(10)
          .padding(.horizontal, 16)
        }

        // App count badge (x/N) at bottom
        HStack {
          Spacer()
          Text(String(localized: "已選 \(appCount)/\(appLimit) 個 App"))
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(isDoneDisabled ? .red : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
              Capsule()
                .fill(isDoneDisabled ? Color.red.opacity(0.1) : Color(.systemGray6))
            )
          Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
      }
      .onReceive(stateUpdateTimer) { _ in
        updateFlag.toggle()
      }
      .onDisappear {
        stateUpdateTimer.upstream.connect().cancel()
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { showClearConfirmation = true }) {
            Image(systemName: "arrow.clockwise")
          }
          .accessibilityLabel(String(localized: "Clear All"))
          .disabled(!hasSelection)
        }

        ToolbarItem(placement: .topBarTrailing) {
          Button(action: handleDone) {
            Image(systemName: "checkmark")
          }
          .accessibilityLabel(String(localized: "Done"))
          .disabled(isDoneDisabled)
        }
      }
      .confirmationDialog(
        String(localized: "清除所有選擇"),
        isPresented: $showClearConfirmation,
        titleVisibility: .visible
      ) {
        Button(String(localized: "全部清除"), role: .destructive) {
          clearAll()
        }
        Button(String(localized: "取消"), role: .cancel) {}
      } message: {
        Text(String(localized: "將清除所有已選的 App、類別與網域"))
      }
      .alert(String(localized: "超過 50 個 App 上限"), isPresented: $showLimitAlert) {
        Button(String(localized: "好"), role: .cancel) {}
      } message: {
        Text(String(localized: "最多只能阻擋 50 個 App，請減少選擇"))
      }
      .alert(String(localized: "超過免費版上限"), isPresented: $showFreeLimitAlert) {
        Button(String(localized: "好"), role: .cancel) {}
        Button(String(localized: "升級")) {
          showPaywall = true
        }
      } message: {
        Text(String(localized: "免費版最多阻擋 3 個 App，請減少選擇或升級 Premium"))
      }
      .sheet(isPresented: $showPaywall) {
        PremiumUpgradeView()
          .environmentObject(subscriptionManager)
      }
    }
  }
}

#if DEBUG
  struct AppPicker_Previews: PreviewProvider {
    static var previews: some View {
      AppPicker(
        selection: .constant(FamilyActivitySelection()),
        isPresented: .constant(true)
      )
      .environmentObject(SubscriptionManager.shared)
    }
  }
#endif
