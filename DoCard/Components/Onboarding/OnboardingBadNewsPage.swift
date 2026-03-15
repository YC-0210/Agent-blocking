import SwiftUI

struct OnboardingBadNewsPage: View {
  @EnvironmentObject var themeManager: ThemeManager

  let targetYears: Int
  let onContinue: () -> Void

  @State private var displayedYears: Int = 1
  @State private var countingDone = false
  @State private var showContent = false

  var body: some View {
    VStack(spacing: 0) {
      // Progress bar (4/5)
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.1))
            .frame(height: 6)

          RoundedRectangle(cornerRadius: 4)
            .fill(themeManager.themeColor)
            .frame(
              width: geometry.size.width * 4.0 / 5.0,
              height: 6
            )
        }
      }
      .frame(height: 6)
      .padding(.horizontal, 60)
      .padding(.top, 20)

      Spacer()

      // Top text
      Text(String(localized: "壞消息是\n按照目前的使用量，你將花費"))
        .font(.system(size: 20, weight: .medium))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      // Large year number with gradient
      Text("\(displayedYears) 年")
        .font(.system(size: 72, weight: .bold))
        .foregroundStyle(
          LinearGradient(
            colors: [
              themeManager.themeColor,
              themeManager.themeColor.opacity(0.6),
            ],
            startPoint: .leading,
            endPoint: .trailing
          )
        )
        .padding(.vertical, 16)
        .contentTransition(.numericText())

      // Bottom text
      Text(String(localized: "盯著一個六吋螢幕"))
        .font(.system(size: 18, weight: .medium))
        .foregroundColor(.white.opacity(0.7))
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      Spacer()
      Spacer()

      // Footnote
      Text(String(localized: "*以 80 年壽命為基準推算"))
        .font(.system(size: 13, weight: .regular))
        .foregroundColor(.white.opacity(0.3))
        .opacity(showContent ? 1.0 : 0)
        .padding(.bottom, 12)

      // Button
      Button(action: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onContinue()
      }) {
        Text(String(localized: "太恐怖啦"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 58)
          .background(
            Capsule()
              .fill(Color.white)
          )
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .opacity(showContent ? 1.0 : 0)
      .offset(y: showContent ? 0 : 20)
    }
    .onAppear {
      startCountingAnimation()
    }
  }

  private func startCountingAnimation() {
    displayedYears = 1
    countingDone = false
    showContent = false

    // Count from 1 to targetYears
    let totalDuration: Double = 1.5
    let steps = max(targetYears - 1, 1)
    let interval = totalDuration / Double(steps)

    for i in 0..<steps {
      DispatchQueue.main.asyncAfter(deadline: .now() + interval * Double(i + 1)) {
        withAnimation(.interpolatingSpring(stiffness: 300, damping: 30)) {
          displayedYears = min(i + 2, targetYears)
        }

        // After last step, show the rest of the content
        if i == steps - 1 {
          countingDone = true
          withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
            showContent = true
          }
        }
      }
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingBadNewsPage(targetYears: 16, onContinue: {})
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
