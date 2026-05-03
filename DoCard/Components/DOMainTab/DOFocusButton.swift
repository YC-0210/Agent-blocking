import SwiftUI

/// Large pill-shaped focus button — thin orange stroke with subtle glow, no solid fill.
struct DOFocusButton: View {
  @EnvironmentObject var themeManager: ThemeManager

  let isBlocking: Bool
  let showStopButton: Bool
  let simpleTapMode: Bool  // when true, start button uses simple tap instead of long press (for tutorial)
  let onStartTapped: () -> Void
  let onStopTapped: () -> Void

  @State private var isPressed = false
  @State private var holdProgress: CGFloat = 0
  @State private var longPressCompleted = false

  private let longPressDuration: Double = 0.8

  var body: some View {
    VStack(spacing: 14) {
      if isBlocking {
        if showStopButton {
          focusPillButton(
            title: String(localized: "停止專注"),
            color: themeManager.themeColor,
            action: {
              UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
              onStopTapped()
            }
          )
        }
      } else {
        focusPillButton(
          title: String(localized: "開始專注"),
          color: themeManager.themeColor,
          useLongPress: !simpleTapMode,
          action: onStartTapped
        )
      }
    }
  }

  // MARK: - Pill Button (long-press)

  @ViewBuilder
  private func focusPillButton(
    title: String,
    color: Color,
    textColor: Color = .white,
    useLongPress: Bool = true,
    action: @escaping () -> Void
  ) -> some View {
    let pillContent = ZStack {
      // Thin stroke border with subtle glow
      Capsule()
        .fill(Color.clear)
        .overlay(
          Capsule()
            .stroke(color.opacity(0.8), lineWidth: 1.5)
        )
        .overlay(
          // Progress fill during long press
          GeometryReader { geometry in
            Capsule()
              .fill(color.opacity(0.2))
              .frame(width: geometry.size.width * holdProgress)
          }
          .clipShape(Capsule())
        )
        // Outer glow effect
        .shadow(color: color.opacity(0.4), radius: 12, x: 0, y: 0)
        .shadow(color: color.opacity(0.2), radius: 6, x: 0, y: 0)

      Text(title)
        .font(.system(size: 17, weight: .semibold))
        .foregroundColor(textColor)
    }
    .frame(maxWidth: .infinity)
    .frame(height: 58)
    .scaleEffect(isPressed ? 0.97 : 1.0)
    .animation(.spring(response: 0.3), value: isPressed)
    .contentShape(Capsule())

    if useLongPress {
      pillContent
        .onLongPressGesture(
          minimumDuration: longPressDuration,
          pressing: { pressing in
            isPressed = pressing
            if pressing {
              longPressCompleted = false
              withAnimation(.linear(duration: longPressDuration)) {
                holdProgress = 1.0
              }
              UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
            } else if !longPressCompleted {
              // Cancelled early — smoothly return to start
              withAnimation(.easeOut(duration: 0.25)) {
                holdProgress = 0
              }
            }
          },
          perform: {
            longPressCompleted = true
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
              generator.impactOccurred(intensity: 0.7)
            }
            action()
            isPressed = false
            // Reset bar after a brief moment so user sees it fully filled before it fades
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
              withAnimation(.easeOut(duration: 0.3)) {
                holdProgress = 0
              }
            }
          }
        )
    } else {
      pillContent
        .onTapGesture {
          UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
          action()
        }
    }
  }
}

#Preview {
  VStack(spacing: 30) {
    DOFocusButton(
      isBlocking: false,
      showStopButton: true,
      simpleTapMode: false,
      onStartTapped: {},
      onStopTapped: {}
    )

    DOFocusButton(
      isBlocking: true,
      showStopButton: true,
      simpleTapMode: false,
      onStartTapped: {},
      onStopTapped: {}
    )
  }
  .padding(.horizontal, 24)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color.black)
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
