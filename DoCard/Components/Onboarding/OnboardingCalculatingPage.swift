import SwiftUI

struct OnboardingCalculatingPage: View {
  let onComplete: () -> Void

  @State private var progress: CGFloat = 0
  @State private var showContent = false
  @State private var gradientOffset: CGFloat = -1

  private let duration: Double = 3.5

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      // "計算中" text
      Text(String(localized: "計算中"))
        .font(.system(size: 22, weight: .medium))
        .foregroundColor(.white)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      // Progress bar with colorful gradient
      GeometryReader { geometry in
        let barWidth = geometry.size.width

        ZStack(alignment: .leading) {
          // Background track
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.12))
            .frame(height: 6)

          // Colorful animated fill
          RoundedRectangle(cornerRadius: 4)
            .fill(
              LinearGradient(
                colors: [
                  Color(red: 0.55, green: 0.3, blue: 0.9),   // purple
                  Color(red: 0.4, green: 0.5, blue: 1.0),    // blue
                  Color(red: 0.3, green: 0.8, blue: 0.9),    // cyan
                  Color(red: 0.55, green: 0.3, blue: 0.9),   // purple again for seamless loop
                ],
                startPoint: UnitPoint(x: gradientOffset, y: 0.5),
                endPoint: UnitPoint(x: gradientOffset + 1, y: 0.5)
              )
            )
            .frame(width: barWidth * progress, height: 6)
        }
      }
      .frame(height: 6)
      .padding(.horizontal, 60)
      .padding(.top, 16)

      Spacer()
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.4)) {
        showContent = true
      }

      // Animate gradient shimmer
      withAnimation(
        .linear(duration: 1.2)
        .repeatForever(autoreverses: false)
      ) {
        gradientOffset = 1
      }

      // Animate progress bar fill over 3.5s
      withAnimation(.easeInOut(duration: duration)) {
        progress = 1.0
      }

      // Auto-advance after completion
      DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.3) {
        onComplete()
      }
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingCalculatingPage(onComplete: {})
  }
  .preferredColorScheme(.dark)
}
