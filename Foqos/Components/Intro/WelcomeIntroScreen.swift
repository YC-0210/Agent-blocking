import SwiftUI

struct WelcomeIntroScreen: View {
  @State private var cardScale: CGFloat = 0.5
  @State private var showContent: Bool = false
  @State private var pulseAnimation: Bool = false
  @State private var floatAnimation: Bool = false

  var body: some View {
    VStack(spacing: 0) {
      // Heading
      VStack(spacing: 8) {
        Text(String(localized: "Welcome to DO"))
          .font(.system(size: 34, weight: .bold))
          .foregroundColor(.primary)
          .opacity(showContent ? 1 : 0)
          .offset(y: showContent ? 0 : -20)

        Text(String(localized: "Live your best life with focus and intention."))
          .font(.system(size: 16))
          .foregroundColor(.secondary)
          .opacity(showContent ? 1 : 0)
          .offset(y: showContent ? 0 : -20)
      }

      Spacer()

      // DO Card container with glow effect
      ZStack {
        // Pulse rings (circular glow effect) - scaled up to match larger card
        ForEach(0..<2) { index in
          Circle()
            .stroke(
              LinearGradient(
                gradient: Gradient(colors: [
                  Color(hex: "#FF6B35").opacity(0.3),
                  Color(hex: "#FF6B35").opacity(0.1),
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
              ),
              lineWidth: 4
            )
            .frame(width: 380, height: 380)
            .scaleEffect(pulseAnimation ? 1.3 : 1.0)
            .opacity(pulseAnimation ? 0 : 0.6)
            .animation(
              .easeOut(duration: 2)
                .repeatForever(autoreverses: false)
                .delay(Double(index) * 0.6),
              value: pulseAnimation
            )
        }

        // DO Card image with 3D tilt and floating effect - 3x size (220x140 -> 660x420)
        Image("DOCard")
          .resizable()
          .scaledToFit()
          .frame(width: 340, height: 215)
          .rotation3DEffect(
            .degrees(15),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.5
          )
          .rotation3DEffect(
            .degrees(-10),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.5
          )
          .shadow(
            color: Color(hex: "#FF6B35").opacity(0.4),
            radius: 30,
            x: 0,
            y: 20
          )
          .shadow(
            color: Color.black.opacity(0.3),
            radius: 15,
            x: 8,
            y: 15
          )
          .scaleEffect(cardScale)
          .offset(y: floatAnimation ? -10 : 10)
          .animation(
            .easeInOut(duration: 2.0)
              .repeatForever(autoreverses: true),
            value: floatAnimation
          )
          .opacity(showContent ? 1 : 0)
      }
      .frame(height: 420)

      Spacer()

      // Message text
      VStack(spacing: 12) {
        Text(String(localized: "Use your DO Card to lock and unlock apps. Take control of your digital life."))
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .lineSpacing(4)
      }
      .padding(.horizontal, 15)
      .opacity(showContent ? 1 : 0)
      .offset(y: showContent ? 0 : 20)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      // Card scale animation (0.8s spring animation with 0.2s delay = 1.0s total)
      withAnimation(.spring(response: 0.8, dampingFraction: 0.6, blendDuration: 0).delay(0.2)) {
        cardScale = 1.0
      }

      // Content fade in
      withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
        showContent = true
      }

      // Start pulse animation
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        pulseAnimation = true
      }

      // Start floating animation
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        floatAnimation = true
      }
    }
  }
}

#Preview {
  WelcomeIntroScreen()
    .background(Color(.systemBackground))
}
