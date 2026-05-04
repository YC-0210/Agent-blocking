import SwiftUI

struct OnboardingMultiSelectOption: Identifiable {
  let id = UUID()
  let emoji: String
  let text: String
}

struct OnboardingMultiSelectPage: View {
  @EnvironmentObject var themeManager: ThemeManager

  let question: String
  let options: [OnboardingMultiSelectOption]
  let currentStep: Int
  let totalSteps: Int
  let onContinue: ([String]) -> Void

  @State private var selectedIds: Set<UUID> = []
  @State private var showContent = false

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
      Text(question)
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 30)
        .padding(.top, 40)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)

      // Scrollable options
      ScrollView(showsIndicators: false) {
        VStack(spacing: 12) {
          ForEach(options) { option in
            let isSelected = selectedIds.contains(option.id)
            Button {
              UIImpactFeedbackGenerator(style: .light).impactOccurred()
              withAnimation(.easeOut(duration: 0.15)) {
                if isSelected {
                  selectedIds.remove(option.id)
                } else {
                  selectedIds.insert(option.id)
                }
              }
            } label: {
              HStack(spacing: 14) {
                Text(option.emoji)
                  .font(.system(size: 24))

                Text(option.text)
                  .font(.system(size: 16, weight: .medium))
                  .foregroundColor(.white)

                Spacer()
              }
              .padding(.horizontal, 18)
              .frame(maxWidth: .infinity)
              .frame(height: 58)
              .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .fill(
                    isSelected
                      ? themeManager.themeColor.opacity(0.2)
                      : Color.white.opacity(0.08)
                  )
              )
              .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                  .stroke(
                    isSelected
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

      // "繼續" button
      Button {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let selected = options.filter { selectedIds.contains($0.id) }.map(\.text)
        onContinue(selected)
      } label: {
        Text(String(localized: "繼續"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 58)
          .background(
            Capsule()
              .fill(selectedIds.isEmpty ? Color.white.opacity(0.3) : Color.white)
          )
      }
      .disabled(selectedIds.isEmpty)
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .padding(.top, 12)
      .opacity(showContent ? 1.0 : 0)
    }
    .onAppear {
      selectedIds = []
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
    OnboardingMultiSelectPage(
      question: "你想改變哪些習慣？",
      options: [
        .init(emoji: "😩", text: "無意識滑手機"),
        .init(emoji: "🛏️", text: "睡前滑手機"),
        .init(emoji: "🌅", text: "早上起床就看手機"),
        .init(emoji: "💻", text: "工作時被手機分心"),
      ],
      currentStep: 2,
      totalSteps: 4,
      onContinue: { _ in }
    )
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
