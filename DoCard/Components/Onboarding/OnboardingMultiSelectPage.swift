import SwiftUI

struct OnboardingMultiSelectOption: Identifiable {
  let id: String
  let emoji: String
  let text: String
}

struct OnboardingMultiSelectPage: View {
  @EnvironmentObject var themeManager: ThemeManager

  let question: String
  let options: [OnboardingMultiSelectOption]
  let currentStep: Int
  let totalSteps: Int
  @Binding var selectedIds: Set<String>
  let onContinue: ([String]) -> Void
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

      Text(String(localized: "可複選，選擇符合你的項目。"))
        .font(.system(size: 13))
        .foregroundColor(.white.opacity(0.6))
        .padding(.top, 10)

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
                  .multilineTextAlignment(.leading)
                  .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 4)

                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                  .font(.system(size: 18))
                  .foregroundColor(isSelected ? themeManager.themeColor : .white.opacity(0.35))
              }
              .padding(.horizontal, 18)
              .frame(maxWidth: .infinity)
              .frame(minHeight: 58)
              .padding(.vertical, 8)
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
            .accessibilityIdentifier("onboarding.option.\(option.id)")
            .accessibilityValue(isSelected ? String(localized: "已選擇") : String(localized: "未選擇"))
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
          }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
      }
      .opacity(showContent ? 1.0 : 0)
      .offset(y: showContent ? 0 : 15)

      Text(
        selectedIds.isEmpty
          ? String(localized: "請選擇至少一項") : String(localized: "已選 \(selectedIds.count) 項")
      )
      .font(.system(size: 12))
      .foregroundColor(.white.opacity(0.6))
      .padding(.top, 12)

      // "繼續" button
      Button {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let selected = options.filter { selectedIds.contains($0.id) }.map(\.id)
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
        .init(id: "automatic_checking", emoji: "😩", text: "無意識滑手機"),
        .init(id: "bedtime", emoji: "🛏️", text: "睡前滑手機"),
        .init(id: "morning", emoji: "🌅", text: "早上起床就看手機"),
        .init(id: "work", emoji: "💻", text: "工作時被手機分心"),
      ],
      currentStep: 2,
      totalSteps: 3,
      selectedIds: .constant([]),
      onContinue: { _ in }
    )
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
