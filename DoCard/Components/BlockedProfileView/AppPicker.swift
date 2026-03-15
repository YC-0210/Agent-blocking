import FamilyControls
import SwiftUI

struct AppPicker: View {
  private let stateUpdateTimer = Timer.publish(every: 1, on: .main, in: .common)
    .autoconnect()

  @Binding var selection: FamilyActivitySelection
  @Binding var isPresented: Bool

  var allowMode: Bool = false

  @State private var updateFlag: Bool = false
  @State private var refreshID: UUID = UUID()
  @State private var showLimitAlert: Bool = false
  @State private var showClearConfirmation: Bool = false

  private var compactTitle: String {
    let displayText = FamilyActivityUtil.getCountDisplayText(selection, allowMode: allowMode)
    let action = allowMode ? String(localized: "allowed") : String(localized: "blocked")
    return "\(displayText) \(action)"
  }

  private var shouldShowWarning: Bool {
    return FamilyActivityUtil.shouldShowAllowModeWarning(selection, allowMode: allowMode)
  }

  private var isOverLimit: Bool {
    let count = FamilyActivityUtil.countSelectedActivities(selection, allowMode: allowMode)
    return count > 50
  }

  private var hasSelection: Bool {
    return FamilyActivityUtil.countSelectedActivities(selection, allowMode: allowMode) > 0
  }

  private func clearAll() {
    selection = FamilyActivitySelection(includeEntireCategory: allowMode)
    refreshID = UUID()
  }

  private func handleDone() {
    if isOverLimit {
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
        }
      }
      .confirmationDialog(
        String(localized: "Clear All Selections"),
        isPresented: $showClearConfirmation,
        titleVisibility: .visible
      ) {
        Button(String(localized: "Clear All"), role: .destructive) {
          clearAll()
        }
        Button(String(localized: "Cancel"), role: .cancel) {}
      } message: {
        Text(String(localized: "This will deselect all currently selected apps, categories, and web domains."))
      }
      .alert(String(localized: "Over 50 App Limit"), isPresented: $showLimitAlert) {
        Button(String(localized: "Cancel"), role: .cancel) {}
        Button(String(localized: "OK")) {
          isPresented = false
        }
      } message: {
        Text(String(localized:
          "You have selected more than 50 apps and sites. This can lead to issues due to Apple's hard limit of 50."
        ))
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
    }
  }
#endif
