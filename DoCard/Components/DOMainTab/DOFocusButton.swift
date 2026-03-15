import SwiftUI

/// Large pill-shaped focus button — thin orange stroke with subtle glow, no solid fill.
struct DOFocusButton: View {
  @EnvironmentObject var themeManager: ThemeManager

  let isBlocking: Bool
  let showStopButton: Bool
  let isBreakAvailable: Bool
  let isBreakActive: Bool
  let breakUsed: Bool  // true when break has already been taken and ended
  let simpleTapMode: Bool  // when true, start button uses simple tap instead of long press (for tutorial)
  let onStartTapped: () -> Void
  let onStopTapped: () -> Void
  let onBreakTapped: (Int) -> Void  // passes selected break time in minutes

  @State private var isPressed = false
  @State private var holdProgress: CGFloat = 0
  @State private var longPressCompleted = false
  @State private var showBreakPicker = false
  @State private var selectedBreakMinutes: Double = 15

  private let longPressDuration: Double = 0.8

  var body: some View {
    VStack(spacing: 14) {
      if isBlocking {
        if isBreakActive {
          // During break — single "回到專注" button to end break early
          focusPillButton(
            title: String(localized: "回到專注"),
            color: themeManager.themeColor,
            action: {
              UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
              onBreakTapped(0)
            }
          )
        } else {
          // During focus — "休息一下" above "停止專注"
          if isBreakAvailable {
            if showBreakPicker {
              // Expanded: slider + confirm
              breakPickerView()
            } else {
              smallBreakButton(
                title: String(localized: "休息一下"),
                action: {
                  UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                  withAnimation(.easeOut(duration: 0.25)) {
                    showBreakPicker = true
                  }
                }
              )
            }
          }

          if showStopButton {
            focusPillButton(
              title: breakUsed
                ? String(localized: "結束專注")
                : String(localized: "停止專注"),
              color: themeManager.themeColor,
              action: {
                UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                onStopTapped()
              }
            )
          }
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

  // MARK: - Break Picker

  private func breakPickerView() -> some View {
    VStack(spacing: 12) {
      // Duration label
      Text("\(Int(selectedBreakMinutes)) " + String(localized: "分鐘"))
        .font(.system(size: 28, weight: .bold, design: .rounded))
        .foregroundColor(.white)

      // Slider
      Slider(value: $selectedBreakMinutes, in: 1...60, step: 1)
        .tint(Color.white.opacity(0.4))

      // Confirm + Cancel row
      HStack(spacing: 12) {
        // Cancel
        Button {
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          withAnimation(.easeOut(duration: 0.2)) {
            showBreakPicker = false
          }
        } label: {
          Text(String(localized: "取消"))
            .font(.system(size: 14, weight: .medium))
            .foregroundColor(.white.opacity(0.5))
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
              Capsule()
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)

        // Confirm
        Button {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          withAnimation(.easeOut(duration: 0.2)) {
            showBreakPicker = false
          }
          onBreakTapped(Int(selectedBreakMinutes))
        } label: {
          Text(String(localized: "開始休息"))
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
              Capsule()
                .fill(Color.white.opacity(0.15))
            )
            .overlay(
              Capsule()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 4)
    .padding(.vertical, 12)
    .transition(.opacity.combined(with: .scale(scale: 0.95)))
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

  // MARK: - Small Break Button (simple tap)

  /// Smaller, subtler break button — simple tap, muted appearance.
  private func smallBreakButton(
    title: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(.white.opacity(0.5))
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .background(
          Capsule()
            .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }
    .buttonStyle(.plain)
  }
}

#Preview {
  VStack(spacing: 30) {
    DOFocusButton(
      isBlocking: false,
      showStopButton: true,
      isBreakAvailable: false,
      isBreakActive: false,
      breakUsed: false,
      simpleTapMode: false,
      onStartTapped: {},
      onStopTapped: {},
      onBreakTapped: { _ in }
    )

    DOFocusButton(
      isBlocking: true,
      showStopButton: true,
      isBreakAvailable: true,
      isBreakActive: false,
      breakUsed: false,
      simpleTapMode: false,
      onStartTapped: {},
      onStopTapped: {},
      onBreakTapped: { _ in }
    )

    DOFocusButton(
      isBlocking: true,
      showStopButton: true,
      isBreakAvailable: false,
      isBreakActive: false,
      breakUsed: true,
      simpleTapMode: false,
      onStartTapped: {},
      onStopTapped: {},
      onBreakTapped: { _ in }
    )
  }
  .padding(.horizontal, 24)
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color.black)
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
