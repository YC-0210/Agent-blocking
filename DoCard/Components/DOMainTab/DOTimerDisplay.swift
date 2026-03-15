import SwiftData
import SwiftUI

/// Compact pill-shaped badge showing focus time.
/// When idle: shows accumulated focus time today.
/// When active: shows current session elapsed time counting by seconds.
struct DOTimerDisplay: View {
  let elapsedTime: TimeInterval
  let isBlocking: Bool
  let todayFocusTime: TimeInterval

  private var displayTime: TimeInterval {
    isBlocking ? elapsedTime : todayFocusTime
  }

  private var label: String {
    isBlocking
      ? String(localized: "本次")
      : String(localized: "今日")
  }

  var body: some View {
    HStack(spacing: 8) {
      Text(formattedTime)
        .font(.system(size: 22, weight: .bold, design: .rounded))
        .foregroundColor(.white)
        .contentTransition(.numericText())
        .animation(.default, value: displayTime)

      Text(label)
        .font(.system(size: 16, weight: .regular, design: .rounded))
        .foregroundColor(.white.opacity(0.5))
    }
    .padding(.horizontal, 24)
    .padding(.vertical, 14)
    .background(
      Capsule()
        .fill(Color.white.opacity(0.08))
    )
  }

  private var formattedTime: String {
    let totalSeconds = Int(displayTime)
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60

    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
      return String(format: "%02d:%02d", minutes, seconds)
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    DOTimerDisplay(elapsedTime: 0, isBlocking: false, todayFocusTime: 4380)
    DOTimerDisplay(elapsedTime: 1232, isBlocking: true, todayFocusTime: 0)
    DOTimerDisplay(elapsedTime: 0, isBlocking: false, todayFocusTime: 0)
    DOTimerDisplay(elapsedTime: 7265, isBlocking: true, todayFocusTime: 0)
  }
  .frame(maxWidth: .infinity, maxHeight: .infinity)
  .background(Color.black)
  .preferredColorScheme(.dark)
}
