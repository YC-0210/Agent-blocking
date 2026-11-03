import FamilyControls
import SwiftData
import SwiftUI

struct OnboardingView: View {
  @EnvironmentObject var onboardingManager: OnboardingManager
  @Environment(\.modelContext) private var modelContext

  @State private var currentPage: Int = 0
  @State private var selectedPurposes: Set<String> = []
  @State private var selectedHabits: Set<String> = []
  @State private var purposeOtherText = ""
  @State private var habitOtherText = ""
  @State private var selectedPhoneTime: String?
  @State private var navigatingBack = false
  @State private var restoredAnswers = false

  private let totalPages = 12

  private var phoneTimeOptions: [(id: String, label: String)] {
    [
      ("under_1h", String(localized: "1 小時以內")), ("2_3h", String(localized: "2 - 3 小時")),
      ("4_5h", String(localized: "4 - 5 小時")), ("6_7h", String(localized: "6 - 7 小時")),
      ("8h_plus", String(localized: "8 小時以上")),
    ]
  }

  private var draftAnswers: OnboardingAnswers {
    OnboardingAnswers(
      purposes: selectedPurposes, habits: selectedHabits,
      purposeOtherText: purposeOtherText, habitOtherText: habitOtherText,
      dailyPhoneTime: phoneTimeOptions.first { $0.label == selectedPhoneTime }?.id)
  }

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
            otherText: $purposeOtherText,
            onContinue: { _ in confirmQuestion("purposes") }
          )
          .id("purposes")
          .transition(pageTransition)
        case 5:
          OnboardingMultiSelectPage(
            question: String(localized: "哪個符合你滑手機的經驗呢"),
            options: [
              .init(
                id: "automatic_checking", emoji: "📱",
                text: String(localized: "習慣性地打開手機")),
              .init(
                id: "boredom", emoji: "⏳",
                text: String(localized: "無聊時就想滑手機")),
              .init(
                id: "task_avoidance", emoji: "📋",
                text: String(localized: "不想做事時就滑手機")),
              .init(
                id: "emotional_relief", emoji: "☁️",
                text: String(localized: "靠滑手機紓解壓力")),
              .init(
                id: "notification_cue", emoji: "🔔",
                text: String(localized: "看到通知就想查看")),
              .init(
                id: "lost_time_awareness", emoji: "🌀",
                text: String(localized: "不知不覺滑了很久")),
              .init(id: "other", emoji: "＋", text: String(localized: "其他")),
            ],
            currentStep: 2,
            totalSteps: 3,
            selectedIds: $selectedHabits,
            otherText: $habitOtherText,
            onContinue: { _ in confirmQuestion("habits") }
          )
          .id("habits")
          .transition(pageTransition)
        case 6:
          OnboardingSurveyPage(
            question: String(localized: "你每天花多少時間\n在手機上？"),
            options: phoneTimeOptions.map(\.label),
            currentStep: 3,
            totalSteps: 3,
            selectedOption: $selectedPhoneTime,
            onOptionSelected: { _ in confirmQuestion("daily_phone_time") }
          )
          .transition(pageTransition)
        case 7:
          OnboardingPermissionPage(onContinue: { nextPage() })
            .transition(pageTransition)
        case 8:
          OnboardingDistractionAppsPage(
            onContinue: { selection in
              handleDistractionSelection(selection)
              nextPage()
            }
          )
          .transition(pageTransition)
        case 9:
          OnboardingDOCardPairingPage(
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 10:
          OnboardingPhotoGalleryPage(
            onContinue: { nextPage() }
          )
          .transition(pageTransition)
        case 11:
          OnboardingPromoPage(
            onComplete: {
              finishOnboarding()
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
    .onAppear {
      guard !restoredAnswers else { return }
      if let saved = OnboardingTracking.shared.restore() {
        selectedPurposes = saved.purposes
        selectedHabits = saved.habits
        purposeOtherText = saved.purposeOtherText
        habitOtherText = saved.habitOtherText
        selectedPhoneTime = phoneTimeOptions.first { $0.id == saved.dailyPhoneTime }?.label
      }
      restoredAnswers = true
    }
    .onChange(of: draftAnswers) { _, answers in
      if restoredAnswers { OnboardingTracking.shared.saveDraft(answers) }
    }
  }

  private func confirmQuestion(_ question: String) {
    OnboardingTracking.shared.confirm(question, answers: draftAnswers)
    nextPage()
  }

  private func finishOnboarding() {
    OnboardingTracking.shared.completeStep("offer")
    OnboardingTracking.shared.complete()
    onboardingManager.completeOnboarding()
  }

  private func nextPage() {
    let setupSteps = [0: "welcome", 1: "intro_feeling", 2: "intro_context", 3: "card_introduction",
                      7: "permissions", 8: "app_selection", 9: "card_pairing", 10: "gallery"]
    if let step = setupSteps[currentPage] { OnboardingTracking.shared.completeStep(step) }
    navigatingBack = false
    if currentPage < totalPages - 1 {
      currentPage += 1
    } else {
      finishOnboarding()
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
