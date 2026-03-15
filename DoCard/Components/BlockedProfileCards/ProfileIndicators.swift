import SwiftUI

struct ProfileIndicators: View {
  let enableLiveActivity: Bool
  let hasReminders: Bool
  let enableBreaks: Bool
  var isActive: Bool = false

  var body: some View {
    HStack(spacing: 16) {
      if enableBreaks {
        indicatorView(label: "Breaks")
      }
      if enableLiveActivity {
        indicatorView(label: "Live Activity")
      }
      if hasReminders {
        indicatorView(label: "Reminders")
      }
    }
  }

  private func indicatorView(label: String) -> some View {
    HStack(spacing: 6) {
      PulsingDot(isActive: isActive)

      Text(label)
        .font(.caption2)
        .foregroundColor(.secondary)
    }
  }
}

/// A small dot that pulses when the profile is active
private struct PulsingDot: View {
  let isActive: Bool
  @State private var isPulsing = false

  var body: some View {
    ZStack {
      if isActive {
        // Outer pulse ring
        Circle()
          .fill(Color.primary.opacity(0.3))
          .frame(width: 10, height: 10)
          .scaleEffect(isPulsing ? 1.6 : 1.0)
          .opacity(isPulsing ? 0 : 0.5)
      }

      Circle()
        .fill(Color.primary.opacity(0.85))
        .frame(width: 6, height: 6)
    }
    .animation(
      isActive
        ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
        : .default,
      value: isPulsing
    )
    .onChange(of: isActive) { _, newValue in
      isPulsing = newValue
    }
    .onAppear {
      isPulsing = isActive
    }
  }
}

#Preview {
  VStack(spacing: 20) {
    ProfileIndicators(
      enableLiveActivity: true,
      hasReminders: true,
      enableBreaks: false,
      isActive: true
    )
    ProfileIndicators(
      enableLiveActivity: false,
      hasReminders: false,
      enableBreaks: true,
      isActive: false
    )
  }
  .padding()
  .background(Color(.systemGroupedBackground))
}
