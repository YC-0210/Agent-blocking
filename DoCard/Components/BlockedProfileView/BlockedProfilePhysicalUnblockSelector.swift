import SwiftUI

struct BlockedProfilePhysicalUnblockSelector: View {
  let nfcTagId: String?
  var disabled: Bool = false
  var disabledText: String?

  let onSetNFC: () -> Void
  let onUnsetNFC: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      // DO Card Column
      PhysicalUnblockColumn(
        title: "DO Card",
        description: String(localized: "Set a specific DO Card that can only unblock this profile when active"),
        systemImage: "wave.3.right.circle.fill",
        id: nfcTagId,
        disabled: disabled,
        onSet: onSetNFC,
        onUnset: onUnsetNFC
      )

      if let disabledText = disabledText, disabled {
        Text(disabledText)
          .foregroundStyle(.red)
          .padding(.top, 4)
          .font(.caption)
      }
    }.padding(0)
  }
}

#Preview {
  NavigationStack {
    Form {
      Section {
        // Example with no ID set
        BlockedProfilePhysicalUnblockSelector(
          nfcTagId: nil,
          disabled: false,
          onSetNFC: { print("Set NFC") },
          onUnsetNFC: { print("Unset NFC") }
        )
      }

      Section {
        // Example with ID set
        BlockedProfilePhysicalUnblockSelector(
          nfcTagId: "nfc_12345678901234567890",
          disabled: false,
          onSetNFC: { print("Set NFC") },
          onUnsetNFC: { print("Unset NFC") }
        )
      }

      Section {
        // Example disabled
        BlockedProfilePhysicalUnblockSelector(
          nfcTagId: "nfc_12345678901234567890",
          disabled: true,
          disabledText: "Physical unblock options are locked",
          onSetNFC: { print("Set NFC") },
          onUnsetNFC: { print("Unset NFC") }
        )
      }
    }
  }
}
