import SwiftUI

/// A quiet entry point to the same notice used for existing installs.
struct AnalyticsPrivacyLink: View {
  @State private var isShowingNotice = false

  var body: some View {
    Button {
      isShowingNotice = true
    } label: {
      Text(AnalyticsConsent.disclosureTitle)
        .font(.footnote)
        .foregroundStyle(.white.opacity(0.7))
        .underline()
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("onboarding.privacyNotice")
    .sheet(isPresented: $isShowingNotice) {
      NavigationStack {
        ScrollView {
          Text(AnalyticsConsent.disclosureMessage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .navigationTitle(AnalyticsConsent.disclosureTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .confirmationAction) {
            Button(String(localized: "完成")) { isShowingNotice = false }
          }
        }
      }
      .preferredColorScheme(.dark)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }
}
