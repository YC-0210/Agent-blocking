import SwiftUI

struct OnboardingStatementPage: View {
  let text: String
  var buttonTitle: String? = nil
  let onContinue: () -> Void

  @State private var showText = false
  @State private var showButton = false

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      VStack(spacing: 0) {
        Spacer()

        Text(text)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)
          .multilineTextAlignment(.center)
          .lineSpacing(6)
          .padding(.horizontal, 30)
          .opacity(showText ? 1.0 : 0)
          .scaleEffect(showText ? 1.0 : 0.95)

        Spacer()

        if let buttonTitle {
          Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onContinue()
          }) {
            Text(buttonTitle)
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
      }
    }
    .onTapGesture {
      if buttonTitle == nil {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        onContinue()
      }
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.8).delay(0.2)) {
        showText = true
      }
      if buttonTitle != nil {
        withAnimation(.easeOut(duration: 0.6).delay(0.8)) {
          showButton = true
        }
      }
    }
  }
}

#Preview {
  OnboardingStatementPage(text: "我們清楚知道\n手機如何破壞生活節奏", onContinue: {})
    .preferredColorScheme(.dark)
}
