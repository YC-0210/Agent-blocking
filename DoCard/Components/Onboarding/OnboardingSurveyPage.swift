import SwiftUI

struct OnboardingSurveyPage: View {
  @EnvironmentObject var themeManager: ThemeManager

  let question: String
  let options: [String]
  let currentStep: Int  // 1-based (1, 2, 3, 4)
  let totalSteps: Int  // e.g. 4
  @Binding var selectedOption: String?
  let onOptionSelected: (String) -> Void

  @State private var showContent = false

  var body: some View {
    VStack(spacing: 0) {
      // Progress bar
      GeometryReader { geometry in
        ZStack(alignment: .leading) {
          // Background track
          RoundedRectangle(cornerRadius: 4)
            .fill(Color.white.opacity(0.1))
            .frame(height: 6)

          // Orange filled portion
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
      Text(question)
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      Text(String(localized: "單選，依照你平常的使用情況估計。"))
        .font(.system(size: 13))
        .foregroundColor(.white.opacity(0.6))
        .padding(.top, 10)

      // Keep the choices scrollable on smaller phones.
      ScrollView(showsIndicators: false) {
        VStack(spacing: 14) {
          ForEach(options, id: \.self) { option in
            Button {
              UIImpactFeedbackGenerator(style: .medium).impactOccurred()
              withAnimation(.easeOut(duration: 0.15)) {
                selectedOption = option
              }
            } label: {
              Text(option)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .background(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                      selectedOption == option
                        ? themeManager.themeColor.opacity(0.3)
                        : Color.white.opacity(0.08)
                    )
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                      selectedOption == option
                        ? themeManager.themeColor.opacity(0.6)
                        : Color.clear,
                      lineWidth: 1.5
                    )
                )
            }
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
      }
      .opacity(showContent ? 1.0 : 0)
      .offset(y: showContent ? 0 : 15)

      Button {
        guard let selectedOption else { return }
        onOptionSelected(selectedOption)
      } label: {
        Text(String(localized: "繼續"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 58)
          .background(Capsule().fill(selectedOption == nil ? Color.white.opacity(0.3) : .white))
      }
      .disabled(selectedOption == nil)
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .padding(.top, 20)
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
    OnboardingSurveyPage(
      question: "你每天花多少時間\n在手機上？",
      options: [
        "1 小時以內",
        "2 - 3 小時",
        "4 - 5 小時",
        "6 - 7 小時",
        "8 小時以上",
      ],
      currentStep: 1,
      totalSteps: 3,
      selectedOption: .constant(nil),
      onOptionSelected: { _ in }
    )
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
