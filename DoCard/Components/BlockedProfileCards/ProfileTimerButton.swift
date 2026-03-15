import SwiftUI

struct ProfileTimerButton: View {
  @EnvironmentObject var themeManager: ThemeManager

  let isActive: Bool

  let isBreakAvailable: Bool
  let isBreakActive: Bool

  let elapsedTime: TimeInterval?

  let showStopButton: Bool

  let onStartTapped: () -> Void
  let onStopTapped: () -> Void

  let onBreakTapped: () -> Void

  // Breathing glow state
  @State private var glowIntensity: Double = 0.3

  var breakMessage: String {
    return isBreakActive ? String(localized: "Hold to Stop Break") : String(localized: "Hold to Start Break")
  }

  var breakColor: Color? {
    return isBreakActive ? .orange : nil
  }

  var body: some View {
    VStack(spacing: 8) {
      HStack(spacing: 8) {
        if isActive, let elapsedTimeVal = elapsedTime {
          // Timer with breathing glow
          HStack(spacing: 8) {
            Text(timeString(from: elapsedTimeVal))
              .foregroundColor(.primary)
              .font(.system(size: 16, weight: .semibold))
              .contentTransition(.numericText())
              .animation(.default, value: elapsedTimeVal)
          }
          .padding(.vertical, 10)
          .padding(.horizontal, 12)
          .frame(minWidth: 0, maxWidth: .infinity)
          .background(
            ZStack {
              RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)

              // Breathing glow overlay
              RoundedRectangle(cornerRadius: 16)
                .fill(themeManager.themeColor.opacity(glowIntensity * 0.15))

              RoundedRectangle(cornerRadius: 16)
                .stroke(
                  themeManager.themeColor.opacity(glowIntensity),
                  lineWidth: 1.5
                )
            }
          )
          .shadow(
            color: themeManager.themeColor.opacity(glowIntensity * 0.4),
            radius: 8, x: 0, y: 0
          )
          .onAppear {
            withAnimation(
              .easeInOut(duration: 1.5)
                .repeatForever(autoreverses: true)
            ) {
              glowIntensity = 0.7
            }
          }

          // Stop button (shown when showStopButton is true)
          if showStopButton {
            GlassButton(
              title: String(localized: "Stop"),
              icon: "stop.fill",
              fullWidth: false,
              equalWidth: true
            ) {
              // Strong haptic for stop
              UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
              onStopTapped()
            }
          }
        } else {
          // Start button (no ripple in inactive state — ripple is only for active timer)
          GlassButton(
            title: String(localized: "Hold to Start"),
            icon: "play.fill",
            fullWidth: true,
            longPressEnabled: true
          ) {
            onStartTapped()
          }
        }
      }

      if isBreakAvailable {
        GlassButton(
          title: breakMessage,
          icon: "cup.and.heat.waves.fill",
          fullWidth: true,
          longPressEnabled: true,
          color: breakColor
        ) {
          onBreakTapped()
        }
      }
    }
    .onChange(of: isActive) { _, newValue in
      if !newValue {
        // Reset glow when deactivated
        glowIntensity = 0.3
      }
    }
  }

  // Format TimeInterval to HH:MM:SS
  private func timeString(from timeInterval: TimeInterval) -> String {
    let hours = Int(timeInterval) / 3600
    let minutes = Int(timeInterval) / 60 % 60
    let seconds = Int(timeInterval) % 60
    return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
  }
}

#Preview {
  VStack(spacing: 20) {
    ProfileTimerButton(
      isActive: false,
      isBreakAvailable: false,
      isBreakActive: false,
      elapsedTime: nil,
      showStopButton: true,
      onStartTapped: {},
      onStopTapped: {},
      onBreakTapped: {}
    )

    ProfileTimerButton(
      isActive: true,
      isBreakAvailable: true,
      isBreakActive: false,
      elapsedTime: 3665,
      showStopButton: true,
      onStartTapped: {},
      onStopTapped: {},
      onBreakTapped: {}
    )
  }
  .padding()
  .background(Color(.systemGroupedBackground))
}
