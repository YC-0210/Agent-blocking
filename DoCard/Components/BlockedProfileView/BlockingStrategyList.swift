import SwiftUI

struct BlockingStrategyList: View {
  @EnvironmentObject var themeManager: ThemeManager

  let strategies: [BlockingStrategy]
  @Binding var selectedStrategy: BlockingStrategy?
  var disabled: Bool = false
  var disabledText: String?
  var onAdvancedSettingsTapped: (() -> Void)? = nil

  var body: some View {
    Section("Blocking Strategy") {
      VStack(alignment: .leading, spacing: 8) {
        VStack {
          ForEach(strategies, id: \.name) { strategy in
            StrategyRow(
              strategy: strategy,
              isSelected: selectedStrategy?.name == strategy.name,
              onTap: {
                if !disabled {
                  selectedStrategy = strategy
                }
              }
            )
            .opacity(disabled ? 0.5 : 1)
          }
        }

        if let disabledText = disabledText, disabled {
          Text(disabledText)
            .foregroundStyle(.red)
            .padding(.top, 4)
            .font(.caption)
        }
      }.padding(0)

      if let onAdvancedSettingsTapped = onAdvancedSettingsTapped {
        Button(action: onAdvancedSettingsTapped) {
          HStack {
            Text(String(localized: "Advanced Settings"))
              .foregroundStyle(.gray)
            Spacer()
            Image(systemName: "chevron.right")
              .foregroundStyle(.gray)
          }
        }
        .disabled(disabled)
      }
    }
  }
}

#Preview {
  @Previewable @State var selectedStrategy: BlockingStrategy?
  NavigationStack {
    Form {
      BlockingStrategyList(
        strategies: [NFCBlockingStrategy(), ManualBlockingStrategy()],
        selectedStrategy: $selectedStrategy,
        disabled: true,
        disabledText: "Strategy selection is locked"
      )
    }
  }
  .environmentObject(ThemeManager.shared)
}
