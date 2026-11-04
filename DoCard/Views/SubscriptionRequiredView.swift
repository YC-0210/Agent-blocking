import StoreKit
import SwiftData
import SwiftUI

/// Only recovery, billing, help and legal actions are reachable without access.
struct SubscriptionRequiredView: View {
  @Environment(\.modelContext) private var context
  @EnvironmentObject private var subscriptionManager: SubscriptionManager
  @EnvironmentObject private var manager: StrategyManager
  @State private var showEmergency = false
  @State private var redeemCode = false

  var body: some View {
    VStack(spacing: 8) {
      PaywallView(showsCloseButton: false)
      HStack {
        Button(String(localized: "Stop blocking")) {
          if !subscriptionManager.isPremium { manager.reconcileSubscription(context: context) }
        }
        Button(String(localized: "Emergency Unlock")) { showEmergency = true }
          .accessibilityIdentifier("access.emergency")
      }
      if let profile = manager.activeSession?.blockedProfile {
        Button(String(localized: "Tap card to stop")) {
          manager.toggleBlocking(context: context, activeProfile: profile)
        }
      }
      Button(String(localized: "Redeem subscription offer")) { redeemCode = true }
      HStack {
        Link(
          String(localized: "Manage subscription"),
          destination: URL(string: "https://apps.apple.com/account/subscriptions")!)
        Link(String(localized: "Help"), destination: URL(string: "https://do-card.online")!)
      }
    }
    .sheet(isPresented: $showEmergency) { EmergencyView() }
    .offerCodeRedemption(isPresented: $redeemCode)
  }
}
