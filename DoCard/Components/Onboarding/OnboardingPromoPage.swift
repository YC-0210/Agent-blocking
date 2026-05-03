import SwiftUI

struct OnboardingPromoPage: View {
  @EnvironmentObject var themeManager: ThemeManager
  @EnvironmentObject var onboardingManager: OnboardingManager

  @State private var showContent = false

  let onComplete: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      // Before / After comparison
      beforeAfterSection
        .padding(.top, 40)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 15)

      // Headline
      VStack(spacing: 0) {
        Text(String(localized: "行動，"))
          .font(.system(size: 28, weight: .bold))
          .foregroundColor(.white)
        Text(String(localized: "從第一次靠卡開始"))
          .font(.system(size: 28, weight: .bold))
          .foregroundColor(.white)
      }
      .multilineTextAlignment(.center)
      .padding(.top, 30)
      .opacity(showContent ? 1.0 : 0)
      .offset(y: showContent ? 0 : 10)

      // Benefit list
      VStack(spacing: 24) {
        benefitRow(
          icon: "lock.shield.fill",
          title: String(localized: "全神貫注，做好一件事。"),
          subtitle: String(localized: "每次感應，都是你展開行動的象徵。")
        )
        benefitRow(
          icon: "calendar",
          title: String(localized: "掌控你的時間。"),
          subtitle: String(localized: "讓每一天都過得更有意義。")
        )
        benefitRow(
          icon: "person.2.fill",
          title: String(localized: "全心投入生活。"),
          subtitle: String(localized: "因為真正的人生發生在螢幕之外。")
        )
      }
      .padding(.horizontal, 30)
      .padding(.top, 30)
      .opacity(showContent ? 1.0 : 0)
      .offset(y: showContent ? 0 : 15)

      Spacer()

      // CTA button
      Button {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onComplete()
      } label: {
        Text(String(localized: "做就對了，現在開始"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 58)
          .background(
            Capsule()
              .fill(themeManager.themeColor)
          )
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .opacity(showContent ? 1.0 : 0)
      .offset(y: showContent ? 0 : 20)
    }
    .onAppear {
      withAnimation(.easeOut(duration: 0.7).delay(0.15)) {
        showContent = true
      }
    }
  }

  // MARK: - Before / After Section

  private var beforeAfterSection: some View {
    HStack(spacing: 14) {
      // Before card
      screenTimeCard(
        label: "Before",
        sublabel: "DO",
        dailyAverage: "6h 41m",
        barHeights: [0.7, 0.85, 0.6, 0.9, 0.75, 0.8, 0.65],
        barColor: Color.white.opacity(0.3)
      )

      // After card
      screenTimeCard(
        label: "After",
        sublabel: "DO",
        dailyAverage: "1h 12m",
        barHeights: [0.2, 0.15, 0.25, 0.18, 0.22, 0.12, 0.2],
        barColor: themeManager.themeColor.opacity(0.6)
      )
    }
    .padding(.horizontal, 30)
  }

  private func screenTimeCard(
    label: String,
    sublabel: String,
    dailyAverage: String,
    barHeights: [CGFloat],
    barColor: Color
  ) -> some View {
    VStack(spacing: 8) {
      // Label
      Text(label)
        .font(.system(size: 14, weight: .regular))
        .foregroundColor(.white.opacity(0.5))

      Text(sublabel)
        .font(.system(size: 18, weight: .bold))
        .foregroundColor(.white)

      // Card body
      VStack(alignment: .leading, spacing: 8) {
        Text(String(localized: "每日平均"))
          .font(.system(size: 11, weight: .regular))
          .foregroundColor(.white.opacity(0.4))

        Text(dailyAverage)
          .font(.system(size: 22, weight: .bold))
          .foregroundColor(.white)

        // Bar chart
        HStack(alignment: .bottom, spacing: 6) {
          ForEach(Array(barHeights.enumerated()), id: \.offset) { _, height in
            RoundedRectangle(cornerRadius: 3)
              .fill(barColor)
              .frame(height: 40 * height)
          }
        }
        .frame(height: 40)
        .padding(.top, 4)
      }
      .padding(14)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(
        RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(Color.white.opacity(0.06))
      )
    }
  }

  // MARK: - Benefit Row

  private func benefitRow(icon: String, title: String, subtitle: String) -> some View {
    HStack(alignment: .top, spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 20))
        .foregroundColor(themeManager.themeColor)
        .frame(width: 32, height: 32)

      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 16, weight: .bold))
          .foregroundColor(.white)
        +
        Text(" ")
        +
        Text(subtitle)
          .font(.system(size: 16, weight: .regular))
          .foregroundColor(.white.opacity(0.6))
      }
      .lineSpacing(2)

      Spacer()
    }
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingPromoPage(onComplete: {})
  }
  .environmentObject(ThemeManager.shared)
  .environmentObject(OnboardingManager.shared)
  .preferredColorScheme(.dark)
}
