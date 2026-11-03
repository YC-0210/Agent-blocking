import FamilyControls
import SwiftData
import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject var onboardingManager: OnboardingManager
  @Environment(\.modelContext) private var modelContext

  @State private var currentPage: Int = 0
  @State private var screenTimeYears: Int = 16  // default fallback
  @State private var selectedPurposes: Set<String> = []
  @State private var selectedHabits: Set<String> = []
  @State private var selectedPhoneTime: String?
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
  private let totalPages = 16

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
          OnboardingMultiSelectPage(
            question: String(localized: "你想用 DO Card，\n為哪些事留出時間呢？"),
            options: [
              .init(id: "study", emoji: "📚", text: String(localized: "讀書")),
              .init(id: "major_exam", emoji: "✍️", text: String(localized: "準備大考")),
              .init(id: "work_tasks", emoji: "💻", text: String(localized: "工作與完成任務")),
              .init(id: "bedtime_rest", emoji: "🌙", text: String(localized: "睡前休息")),
              .init(id: "family_friends", emoji: "💬", text: String(localized: "陪伴家人與朋友")),
              .init(id: "personal_projects", emoji: "🎯", text: String(localized: "興趣與個人計畫")),
              .init(id: "other", emoji: "＋", text: String(localized: "其他")),
            ],
            currentStep: 1,
            totalSteps: 3,
            selectedIds: $selectedPurposes,
            onContinue: { _ in nextPage() }
          )
          .id("purposes")
          .transition(pageTransition)
        case 5:
          OnboardingMultiSelectPage(
            question: String(localized: "哪個符合你滑手機的經驗呢"),
            options: [
              .init(
                id: "automatic_checking", emoji: "📱",
                text: String(localized: "沒特別要看什麼，也會習慣性打開手機")),
              .init(
                id: "boredom", emoji: "⏳",
                text: String(localized: "一覺得無聊，或有空檔，就想滑手機")),
              .init(
                id: "task_avoidance", emoji: "📋",
                text: String(localized: "不想面對手上的事，先滑手機再說")),
              .init(
                id: "emotional_relief", emoji: "☁️",
                text: String(localized: "心情煩悶或有壓力時，想靠滑手機放鬆")),
              .init(
                id: "notification_cue", emoji: "🔔",
                text: String(localized: "看到通知，就忍不住打開手機查看")),
              .init(
                id: "lost_time_awareness", emoji: "🌀",
                text: String(localized: "原本只想看一下，回過神已經滑了很久")),
              .init(id: "other", emoji: "＋", text: String(localized: "其他")),
            ],
            currentStep: 2,
            totalSteps: 3,
            selectedIds: $selectedHabits,
            onContinue: { _ in nextPage() }
          )
          .id("habits")
          .transition(pageTransition)
        case 6:
          OnboardingSurveyPage(
            question: String(localized: "你每天花多少時間\n在手機上？"),
            options: [
              String(localized: "1 小時以內"),
              String(localized: "2 - 3 小時"),
              String(localized: "4 - 5 小時"),
              String(localized: "6 - 7 小時"),
              String(localized: "8 小時以上"),
            ],
            currentStep: 3,
            totalSteps: 3,
            selectedOption: $selectedPhoneTime,
            onOptionSelected: { option in
              screenTimeYears = screenTimeMapping[option] ?? 16
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
          OnboardingDistractionAppsPage(
            onContinue: { selection in
              handleDistractionSelection(selection)
              nextPage()
            }
          )
          .transition(pageTransition)
        case 13:
          OnboardingDOCardPairingPage(
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 14:
          OnboardingPhotoGalleryPage(
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 15:
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

  /// Persists the user's distracting-app selection, turns on distraction
  /// tracking + monitoring, marks the analytics disclosure as shown, and
  /// auto-creates a Classic-mode profile blocking those same apps so the user
  /// can start a focus session immediately after onboarding.
  private func handleDistractionSelection(_ selection: FamilyActivitySelection) {
    let hasAny = !selection.applicationTokens.isEmpty
      || !selection.categoryTokens.isEmpty
      || !selection.webDomainTokens.isEmpty
    guard hasAny else { return }

    DistractionTracking.selection = selection
    DistractionTracking.setEnabled(true)
    AnalyticsConsent.markDisclosureShown()
    DistractionMonitor.start()

    try? BlockedProfiles.createProfile(
      in: modelContext,
      name: String(localized: "專注模式"),
      selection: selection,
      blockingStrategyId: NFCBlockingStrategy.id
    )
  }
}

#Preview {
  OnboardingView()
    .environmentObject(OnboardingManager.shared)
    .environmentObject(ThemeManager.shared)
    .preferredColorScheme(.dark)
}
