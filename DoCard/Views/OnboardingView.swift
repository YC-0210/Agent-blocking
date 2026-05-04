import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject var onboardingManager: OnboardingManager

  @State private var currentPage: Int = 0
  @State private var screenTimeYears: Int = 16  // default fallback
  @State private var userAge: Int = 22  // default fallback
  @State private var navigatingBack = false

  // Screen time option → projected years mapping
  private var screenTimeMapping: [String: Int] {
    [
      String(localized: "1 小時以內"): 3,
      String(localized: "2 - 3 小時"): 10,
      String(localized: "4 - 5 小時"): 16,
      String(localized: "6 - 7 小時"): 20,
      String(localized: "8 小時以上"): 26,
    ]
  }

  // Total pages — will grow as more pages are added
  private let totalPages = 14

  /// Direction-aware transition: slides from left when going back, from right when going forward
  private var pageTransition: AnyTransition {
    .asymmetric(
      insertion: .move(edge: navigatingBack ? .leading : .trailing).combined(with: .opacity),
      removal: .move(edge: navigatingBack ? .trailing : .leading).combined(with: .opacity)
    )
  }

  var body: some View {
    ZStack {
      Color.black.ignoresSafeArea()

      // Page content
      Group {
        switch currentPage {
        case 0:
          OnboardingWelcomePage(
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 1:
          OnboardingStatementPage(
            text: String(localized: "你肯定懂那種想要每次要開始行動\n卻會忍不住去滑手機的感覺"),
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 2:
          OnboardingStatementPage(
            text: String(localized: "這不怪你\n要怪就怪那些故意設計讓你滑不停的社群媒體"),
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 3:
          OnboardingCardShowcasePage(
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 4:
          OnboardingSurveyPage(
            question: String(localized: "你每天花多少時間\n在手機上？"),
            options: [
              String(localized: "1 小時以內"),
              String(localized: "2 - 3 小時"),
              String(localized: "4 - 5 小時"),
              String(localized: "6 - 7 小時"),
              String(localized: "8 小時以上"),
            ],
            currentStep: 1,
            totalSteps: 5,
            onOptionSelected: { option in
              screenTimeYears = screenTimeMapping[option] ?? 16
              nextPage()
            }
          )
          .transition(pageTransition)
        case 5:
          OnboardingMultiSelectPage(
            question: String(localized: "你想改變哪些習慣？"),
            options: [
              .init(emoji: "😩", text: String(localized: "無意識滑手機")),
              .init(emoji: "🛏️", text: String(localized: "睡前滑手機")),
              .init(emoji: "🌅", text: String(localized: "早上起床就看手機")),
              .init(emoji: "💻", text: String(localized: "工作時被手機分心")),
              .init(emoji: "😰", text: String(localized: "想做的事一直被打斷")),
              .init(emoji: "🍽️", text: String(localized: "吃飯時滑手機")),
              .init(emoji: "🙄", text: String(localized: "忽略身邊的人")),
              .init(emoji: "😟", text: String(localized: "害怕錯過（FOMO）")),
            ],
            currentStep: 2,
            totalSteps: 5,
            onContinue: { _ in nextPage() }
          )
          .transition(pageTransition)
        case 6:
          OnboardingAgePage(
            currentStep: 3,
            totalSteps: 5,
            onContinue: { age in
              userAge = age
              nextPage()
            }
          )
          .transition(pageTransition)
        case 7:
          OnboardingCalculatingPage(
            onComplete: { nextPage() }
          )
          .transition(pageTransition)
        case 8:
          OnboardingStatementPage(
            text: String(localized: "有一個壞消息\n跟一個好消息"),
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 9:
          OnboardingBadNewsPage(
            targetYears: screenTimeYears,
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 10:
          OnboardingGoodNewsPage(
            targetYears: screenTimeYears,
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 11:
          OnboardingPermissionPage(onContinue: { nextPage() })
            .transition(pageTransition)
        case 12:
          OnboardingDOCardPairingPage(
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 13:
          OnboardingPromoPage(
            onComplete: {
              onboardingManager.completeOnboarding()
            }
          )
          .transition(pageTransition)
        default:
          SwiftUI.EmptyView()
        }
      }
      .animation(.spring(response: 0.5, dampingFraction: 0.85), value: currentPage)

      // Back button on interactive survey pages (4–6)
      if (4...6).contains(currentPage) {
        VStack {
          HStack {
            Button(action: { previousPage() }) {
              Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "Back"))
            Spacer()
          }
          .padding(.leading, 12)
          .padding(.top, 8)
          Spacer()
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: currentPage)
      }
    }
  }

  private func nextPage() {
    navigatingBack = false
    if currentPage < totalPages - 1 {
      currentPage += 1
    } else {
      onboardingManager.completeOnboarding()
    }
  }

  private func previousPage() {
    if currentPage > 0 {
      navigatingBack = true
      currentPage -= 1
    }
  }
}

#Preview {
  OnboardingView()
    .environmentObject(OnboardingManager.shared)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.dark)
}
