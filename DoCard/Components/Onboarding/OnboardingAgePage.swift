import SwiftUI

struct OnboardingAgePage: View {
  @EnvironmentObject var themeManager: ThemeManager

  let currentStep: Int
  let totalSteps: Int
  let onContinue: (Int) -> Void

  @State private var selectedAge: Int = 22
  @State private var showContent = false

  private let ageRange = Array(13...80)

  var body: some View {
    VStack(spacing: 0) {
      // Progress bar
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.1))
            .frame(height: 6)

          RoundedRectangle(cornerRadius: 4)
            .fill(themeManager.themeColor)
            .frame(
              width: geometry.size.width * CGFloat(currentStep) / CGFloat(totalSteps),
              height: 6
            )
            .animation(.easeInOut(duration: 0.4), value: currentStep)
        }
      }
      .frame(height: 6)
      .padding(.horizontal, 60)
      .padding(.top, 20)

      // Question title
      Text(String(localized: "你今年幾歲？"))
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      Spacer()

      // Scrolling age picker
      Picker("Age", selection: $selectedAge) {
        ForEach(ageRange, id: \.self) { age in
          Text("\(age)")
            .font(.system(size: 28, weight: age == selectedAge ? .bold : .regular))
            .foregroundColor(.white)
            .tag(age)
        }
      }
      .pickerStyle(.wheel)
      .frame(height: 250)
      .opacity(showContent ? 1.0 : 0)

      Spacer()

      // "繼續" button
      Button {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onContinue(selectedAge)
      } label: {
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
      .padding(.top, 12)
      .opacity(showContent ? 1.0 : 0)
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.6).delay(0.15)) {
        showContent = true
      }
    }
    .onDisappear {
      showContent = false
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingAgePage(
      currentStep: 3,
      totalSteps: 5,
      onContinue: { _ in }
    )
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
