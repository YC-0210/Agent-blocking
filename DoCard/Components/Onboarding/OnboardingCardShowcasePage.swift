import SwiftUI

struct OnboardingCardShowcasePage: View {
  @EnvironmentObject var themeManager: ThemeManager

  let onContinue: () -> Void

  // Animation states
  @State private var showCard = false
  @State private var showText = false
  @State private var showButton = false

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      // Title — appears after delay
      Text(String(localized: "所以我們設計了DO Card"))
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .lineSpacing(6)
        .opacity(showText ? 1.0 : 0)
        .offset(y: showText ? 0 : 10)
        .padding(.bottom, 40)

      // DO Card with orange glow
      Image("DOCardMain")
        .resizable()
        .aspectRatio(1.585, contentMode: .fit)
        .frame(maxWidth: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: themeManager.themeColor.opacity(0.5), radius: 40, x: 0, y: 0)
        .shadow(color: themeManager.themeColor.opacity(0.35), radius: 20, x: 0, y: 0)
        .shadow(color: themeManager.themeColor.opacity(0.2), radius: 8, x: 0, y: 0)
        .scaleEffect(showCard ? 1.0 : 0.85)
        .opacity(showCard ? 1.0 : 0)

      Spacer()
      Spacer()

      // "繼續" button — appears after delay
      Button(action: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onContinue()
      }) {
        Text(String(localized: "繼續"))
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
      .opacity(showButton ? 1.0 : 0)
      .offset(y: showButton ? 0 : 20)
    }
    .onAppear {
      // Card appears first
      withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
        showCard = true
      }
      // Text and button appear after 2 seconds
      withAnimation(.easeOut(duration: 0.7).delay(2.0)) {
        showText = true
      }
      withAnimation(.easeOut(duration: 0.7).delay(2.2)) {
        showButton = true
      }
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingCardShowcasePage(onContinue: {})
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
