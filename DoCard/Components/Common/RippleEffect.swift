import SwiftUI

struct RippleEffect: View {
  let color: Color
  let isAnimating: Bool

  @State private var rippleScale1: CGFloat = 0.8
  @State private var rippleScale2: CGFloat = 0.8
  @State private var rippleScale3: CGFloat = 0.8
  @State private var rippleOpacity1: Double = 0.4
  @State private var rippleOpacity2: Double = 0.4
  @State private var rippleOpacity3: Double = 0.4

  var body: some View {
    ZStack {
      // Outermost ripple
      RoundedRectangle(cornerRadius: 16)
        .stroke(color.opacity(rippleOpacity3), lineWidth: 1.5)
        .scaleEffect(rippleScale3)

      // Middle ripple
      RoundedRectangle(cornerRadius: 16)
        .stroke(color.opacity(rippleOpacity2), lineWidth: 1.5)
        .scaleEffect(rippleScale2)

      // Inner ripple
      RoundedRectangle(cornerRadius: 16)
        .stroke(color.opacity(rippleOpacity1), lineWidth: 2)
        .scaleEffect(rippleScale1)
    }
    .onChange(of: isAnimating) { _, newValue in
      if newValue {
        startRipple()
      } else {
        stopRipple()
      }
    }
    .onAppear {
      if isAnimating {
        startRipple()
      }
    }
  }

  private func startRipple() {
    // Ring 1 - fastest
    withAnimation(
      .easeOut(duration: 1.8)
        .repeatForever(autoreverses: false)
    ) {
      rippleScale1 = 1.08
      rippleOpacity1 = 0
    }

    // Ring 2 - offset
    withAnimation(
      .easeOut(duration: 1.8)
        .repeatForever(autoreverses: false)
        .delay(0.6)
    ) {
      rippleScale2 = 1.08
      rippleOpacity2 = 0
    }

    // Ring 3 - most offset
    withAnimation(
      .easeOut(duration: 1.8)
        .repeatForever(autoreverses: false)
        .delay(1.2)
    ) {
      rippleScale3 = 1.08
      rippleOpacity3 = 0
    }
  }

  private func stopRipple() {
    withAnimation(.easeOut(duration: 0.3)) {
      rippleScale1 = 0.8
      rippleScale2 = 0.8
      rippleScale3 = 0.8
      rippleOpacity1 = 0
      rippleOpacity2 = 0
      rippleOpacity3 = 0
    }
  }
}
