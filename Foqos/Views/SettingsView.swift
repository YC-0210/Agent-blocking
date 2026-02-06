import SwiftData
import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var context
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var strategyManager: StrategyManager
  @EnvironmentObject var onboardingManager: OnboardingManager

  @Query private var profiles: [BlockedProfiles]

  @State private var showResetBlockingStateAlert = false
  @State private var showResetOnboardingAlert = false
  @State private var showProfilesExistAlert = false

  var body: some View {
    NavigationStack {
      Form {
        Section(String(localized: "Troubleshooting")) {
          Button {
            showResetBlockingStateAlert = true
          } label: {
            Text(String(localized: "Reset Blocking State"))
              .foregroundColor(themeManager.themeColor)
          }
          .disabled(strategyManager.isBlocking)

          Button {
            if profiles.isEmpty {
              showResetOnboardingAlert = true
            } else {
              showProfilesExistAlert = true
            }
          } label: {
            HStack {
              Text(String(localized: "Replay Tutorial"))
                .foregroundColor(themeManager.themeColor)
              Spacer()
              if onboardingManager.isOnboardingCompleted {
                Text(String(localized: "Completed"))
                  .font(.caption)
                  .foregroundColor(.secondary)
              } else if onboardingManager.isOnboardingSkipped {
                Text(String(localized: "Skipped"))
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        }

        if let doCardURL = URL(string: "https://www.do-card.online/") {
          Section {
            Link(destination: doCardURL) {
              HStack {
                Image(systemName: "creditcard.fill")
                  .foregroundStyle(themeManager.themeColor)
                  .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                  Text(String(localized: "Buy DO Card"))
                    .font(.headline)
                    .foregroundStyle(.primary)
                  Text(String(localized: "Get your physical DO Card"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "arrow.up.right.square")
                  .foregroundStyle(.secondary)
              }
              .padding(.vertical, 8)
            }
          }
        }
      }
      .navigationTitle(String(localized: "Settings"))
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Button(action: { dismiss() }) {
            Image(systemName: "xmark")
          }
          .accessibilityLabel(String(localized: "Close"))
        }
      }
      .alert(String(localized: "Reset Blocking State"), isPresented: $showResetBlockingStateAlert) {
        Button(String(localized: "Cancel"), role: .cancel) { }
        Button(String(localized: "Reset"), role: .destructive) {
          strategyManager.resetBlockingState(context: context)
        }
      } message: {
        Text(String(localized: "This will clear all app restrictions and remove any ghost schedules. Only use this if you're locked out and no profile is active."))
      }
      .alert(String(localized: "Replay Tutorial"), isPresented: $showResetOnboardingAlert) {
        Button(String(localized: "Cancel"), role: .cancel) { }
        Button(String(localized: "Reset")) {
          onboardingManager.resetOnboarding()
          dismiss()
        }
      } message: {
        Text(String(localized: "This will reset the onboarding tutorial. You'll see the setup guide again the next time you create a profile."))
      }
      .alert(String(localized: "Replay Tutorial"), isPresented: $showProfilesExistAlert) {
        Button(String(localized: "Cancel"), role: .cancel) { }
        Button(String(localized: "Delete All & Replay"), role: .destructive) {
          deleteAllProfilesAndResetOnboarding()
        }
      } message: {
        Text(String(localized: "Replaying the tutorial requires deleting all existing profiles. Do you want to continue?"))
      }
    }
  }

  private func deleteAllProfilesAndResetOnboarding() {
    for profile in profiles {
      try? BlockedProfiles.deleteProfile(profile, in: context)
    }
    try? context.save()
    onboardingManager.resetOnboarding()
    dismiss()
  }
}

#Preview {
  SettingsView()
    .environmentObject(ThemeManager.shared)
    .environmentObject(StrategyManager.shared)
    .environmentObject(OnboardingManager.shared)
}
