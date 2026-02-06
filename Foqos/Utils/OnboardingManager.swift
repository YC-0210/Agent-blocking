import SwiftUI

/// Manages the state and persistence of the first-time user onboarding flow
class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    /// Key for storing onboarding completion status
    private static let onboardingCompletedKey = "foqosOnboardingCompleted"
    private static let onboardingSkippedKey = "foqosOnboardingSkipped"
    private static let currentOnboardingStepKey = "foqosCurrentOnboardingStep"

    /// Whether the onboarding has been completed
    @AppStorage(onboardingCompletedKey, store: UserDefaults(suiteName: "group.DO.version3"))
    var isOnboardingCompleted: Bool = false

    /// Whether the onboarding was skipped
    @AppStorage(onboardingSkippedKey, store: UserDefaults(suiteName: "group.DO.version3"))
    var isOnboardingSkipped: Bool = false

    /// Current step in the onboarding process (persisted for resuming)
    @AppStorage(currentOnboardingStepKey, store: UserDefaults(suiteName: "group.DO.version3"))
    var currentStep: Int = 0

    /// Whether to show the onboarding overlay
    @Published var showOnboarding: Bool = false

    /// Total number of onboarding steps
    let totalSteps = 4

    /// Whether onboarding should be shown (not completed and not skipped)
    var shouldShowOnboarding: Bool {
        return !isOnboardingCompleted && !isOnboardingSkipped
    }

    /// Start the onboarding flow
    func startOnboarding() {
        guard shouldShowOnboarding else { return }
        currentStep = 0
        showOnboarding = true
        objectWillChange.send()
    }

    /// Advance to the next step
    func nextStep() {
        if currentStep < totalSteps - 1 {
            currentStep += 1
            objectWillChange.send()
        } else {
            completeOnboarding()
        }
    }

    /// Go back to the previous step
    func previousStep() {
        if currentStep > 0 {
            currentStep -= 1
            objectWillChange.send()
        }
    }

    /// Skip the onboarding flow
    func skipOnboarding() {
        isOnboardingSkipped = true
        showOnboarding = false
        objectWillChange.send()
    }

    /// Complete the onboarding flow
    func completeOnboarding() {
        isOnboardingCompleted = true
        showOnboarding = false
        currentStep = 0
        objectWillChange.send()
    }

    /// Reset onboarding (for re-activation from settings)
    func resetOnboarding() {
        isOnboardingCompleted = false
        isOnboardingSkipped = false
        currentStep = 0
        objectWillChange.send()
    }
}
