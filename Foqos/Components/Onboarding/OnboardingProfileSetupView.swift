import FamilyControls
import SwiftData
import SwiftUI

/// The main onboarding view that guides users through profile setup
struct OnboardingProfileSetupView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var onboardingManager: OnboardingManager

    /// Callback when onboarding completes with a profile
    var onComplete: ((BlockedProfiles?) -> Void)?

    // Profile configuration state
    @State private var profileName: String = ""
    @State private var selectedActivity = FamilyActivitySelection()
    @State private var selectedStrategy: BlockingStrategy = NFCBlockingStrategy()

    // UI state
    @State private var currentStep: Int = 0
    @State private var showingActivityPicker: Bool = false
    @State private var isAnimating: Bool = false

    // Geometry for tooltip positioning
    @State private var welcomeFrame: CGRect = .zero
    @State private var nameFieldFrame: CGRect = .zero
    @State private var appSelectorFrame: CGRect = .zero
    @State private var strategySelectorFrame: CGRect = .zero

    // Focus state for text field
    @FocusState private var isNameFieldFocused: Bool

    private let totalSteps = 4

    var body: some View {
        ZStack {
            // Background
            Color.black.ignoresSafeArea()

            // Main content
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header with progress
                    headerView

                    // Step content
                    stepContent
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 100)
            }

            // Overlay for steps 0 (Welcome tap)
            if currentStep == 0 {
                overlayForStep0
            }

            // Bottom navigation
            VStack {
                Spacer()
                bottomNavigation
            }
        }
        .interactiveDismissDisabled()
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(String(localized: "Set Up Your First Profile"))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: skipOnboarding) {
                    Text(String(localized: "Skip"))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }

            // Progress bar
            OnboardingProgressBar(currentStep: currentStep, totalSteps: totalSteps)
                .padding(.top, 4)

            Text("Step \(currentStep + 1) of \(totalSteps)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch currentStep {
        case 0:
            welcomeStep
        case 1:
            nameStep
        case 2:
            appSelectionStep
        case 3:
            strategySelectionStep
        default:
            SwiftUI.EmptyView()
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            welcomeCard
                .background(
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            welcomeFrame = geometry.frame(in: .global)
                        }
                    }
                )
        }
    }

    private var welcomeCard: some View {
        Button(action: advanceFromWelcome) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(String(localized: "Physically block distracting apps"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "hand.tap.fill")
                        .font(.title2)
                        .foregroundColor(themeManager.themeColor)
                }

                Spacer().frame(height: 8)

                Text(String(localized: "Welcome to DO"))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)

                Text(String(localized: "Tap this card to begin setting up your first blocking profile"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(themeManager.themeColor.opacity(0.5), lineWidth: 2)
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .pulsingHighlight(isActive: currentStep == 0)
    }

    private var overlayForStep0: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Tooltip positioned below welcome card
            if welcomeFrame != .zero {
                VStack {
                    Spacer()
                        .frame(height: welcomeFrame.maxY + 20)

                    TooltipBubble(
                        text: String(localized: "Tap here to start setting up your blocking preferences"),
                        arrowDirection: .up,
                        stepIndicator: String(localized: "Step 1/4"),
                        onSkip: skipOnboarding
                    )
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 20)
                    .transition(.opacity.combined(with: .move(edge: .top)))

                    Spacer()
                }
            }
        }
        .animation(.easeOut(duration: 0.3), value: welcomeFrame)
    }

    // MARK: - Step 1: Name Entry

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Instruction tooltip
            TooltipBubble(
                text: String(localized: "Enter your profile name to personalize your DO experience"),
                arrowDirection: .down,
                stepIndicator: String(localized: "Step 2/4"),
                onSkip: skipOnboarding
            )
            .frame(maxWidth: .infinity)

            // Name input card
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Profile Name"))
                    .font(.headline)
                    .foregroundColor(.primary)

                TextField(String(localized: "e.g., Work Focus, Study Mode"), text: $profileName)
                    .font(.body)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                isNameFieldFocused ? themeManager.themeColor : Color.gray.opacity(0.3),
                                lineWidth: isNameFieldFocused ? 2 : 1
                            )
                    )
                    .focused($isNameFieldFocused)
                    .textContentType(.none)
                    .submitLabel(.done)
                    .onSubmit {
                        if !profileName.isEmpty {
                            advanceFromName()
                        }
                    }
                    .background(
                        GeometryReader { geometry in
                            Color.clear.onAppear {
                                nameFieldFrame = geometry.frame(in: .global)
                            }
                        }
                    )

                Text(String(localized: "Give your profile a name that reflects when you'll use it"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .pulsingHighlight(isActive: currentStep == 1)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                isNameFieldFocused = true
            }
        }
    }

    // MARK: - Step 2: App Selection

    private var appSelectionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Instruction tooltip
            TooltipBubble(
                text: String(localized: "Choose which apps you want to control with DO"),
                arrowDirection: .down,
                stepIndicator: String(localized: "Step 3/4"),
                onSkip: skipOnboarding
            )
            .frame(maxWidth: .infinity)

            // App selector card
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Select Apps to Block"))
                    .font(.headline)
                    .foregroundColor(.primary)

                Button(action: { showingActivityPicker = true }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(appSelectionLabel)
                                .font(.body)
                                .foregroundColor(hasSelectedApps ? .primary : .secondary)

                            if hasSelectedApps {
                                Text(String(localized: "\(selectedAppCount) apps selected"))
                                    .font(.caption)
                                    .foregroundColor(themeManager.themeColor)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(
                                hasSelectedApps ? themeManager.themeColor : Color.gray.opacity(0.3),
                                lineWidth: hasSelectedApps ? 2 : 1
                            )
                    )
                }
                .background(
                    GeometryReader { geometry in
                        Color.clear.onAppear {
                            appSelectorFrame = geometry.frame(in: .global)
                        }
                    }
                )

                Text(String(localized: "These apps will be blocked when you activate this profile"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .pulsingHighlight(isActive: currentStep == 2)
        }
        .sheet(isPresented: $showingActivityPicker) {
            AppPicker(
                selection: $selectedActivity,
                isPresented: $showingActivityPicker,
                allowMode: false
            )
        }
    }

    private var appSelectionLabel: String {
        if hasSelectedApps {
            return String(localized: "Apps selected")
        } else {
            return String(localized: "Tap to select apps")
        }
    }

    private var hasSelectedApps: Bool {
        return !selectedActivity.applicationTokens.isEmpty ||
               !selectedActivity.categoryTokens.isEmpty ||
               !selectedActivity.webDomainTokens.isEmpty
    }

    private var selectedAppCount: Int {
        return selectedActivity.applicationTokens.count +
               selectedActivity.categoryTokens.count +
               selectedActivity.webDomainTokens.count
    }

    // MARK: - Step 3: Strategy Selection

    private var strategySelectionStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Instruction tooltip
            TooltipBubble(
                text: String(localized: "Select your preferred blocking method"),
                arrowDirection: .down,
                stepIndicator: String(localized: "Step 4/4"),
                onSkip: skipOnboarding
            )
            .frame(maxWidth: .infinity)

            // Strategy options
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Choose Blocking Strategy"))
                    .font(.headline)
                    .foregroundColor(.primary)

                // Classic (NFC) Strategy
                strategyOptionCard(
                    strategy: NFCBlockingStrategy(),
                    title: String(localized: "Classic"),
                    description: String(localized: "Tap DO Card to your phone and start locking in. Tap DO Card again to unlock."),
                    isSelected: selectedStrategy is NFCBlockingStrategy
                )

                // Time Locked Strategy
                strategyOptionCard(
                    strategy: NFCTimerBlockingStrategy(),
                    title: String(localized: "Time Locked"),
                    description: String(localized: "Set the timer after the right click (Don't need to tap DO Card). Unlock with DO Card tapping the phone to end the timer earlier."),
                    isSelected: selectedStrategy is NFCTimerBlockingStrategy
                )
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(UIColor.secondarySystemBackground))
            )
            .pulsingHighlight(isActive: currentStep == 3)
            .background(
                GeometryReader { geometry in
                    Color.clear.onAppear {
                        strategySelectorFrame = geometry.frame(in: .global)
                    }
                }
            )
        }
    }

    private func strategyOptionCard(
        strategy: BlockingStrategy,
        title: String,
        description: String,
        isSelected: Bool
    ) -> some View {
        Button(action: { selectStrategy(strategy) }) {
            HStack(alignment: .top, spacing: 16) {
                // Selection indicator
                ZStack {
                    Circle()
                        .stroke(isSelected ? themeManager.themeColor : Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(themeManager.themeColor)
                            .frame(width: 14, height: 14)
                    }
                }
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: strategy.iconType)
                            .font(.body)
                            .foregroundColor(isSelected ? themeManager.themeColor : .secondary)

                        Text(title)
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? themeManager.themeColor.opacity(0.1) : Color(UIColor.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? themeManager.themeColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Bottom Navigation

    private var bottomNavigation: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 16) {
                // Back button (hidden on step 0)
                if currentStep > 0 {
                    Button(action: goBack) {
                        HStack {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .semibold))
                            Text(String(localized: "Back"))
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.gray.opacity(0.2))
                        )
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                // Next/Complete button
                Button(action: handleNextAction) {
                    HStack {
                        Text(nextButtonTitle)
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: currentStep == 3 ? "checkmark" : "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(isNextButtonEnabled ? themeManager.themeColor : Color.gray.opacity(0.5))
                    )
                }
                .disabled(!isNextButtonEnabled)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(UIColor.systemBackground).opacity(0.95))
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: currentStep)
    }

    private var nextButtonTitle: String {
        switch currentStep {
        case 0:
            return String(localized: "Get Started")
        case 3:
            // Step 4 (index 3) is the last step - creates profile and completes onboarding
            return String(localized: "Create Profile")
        default:
            return String(localized: "Continue")
        }
    }

    private var isNextButtonEnabled: Bool {
        switch currentStep {
        case 0:
            return true
        case 1:
            return !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case 2:
            return hasSelectedApps
        case 3:
            return true
        default:
            return false
        }
    }

    // MARK: - Actions

    private func advanceFromWelcome() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = 1
        }
    }

    private func advanceFromName() {
        guard !profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isNameFieldFocused = false
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = 2
        }
    }

    private func advanceFromAppSelection() {
        guard hasSelectedApps else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            currentStep = 3
        }
    }

    private func selectStrategy(_ strategy: BlockingStrategy) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            selectedStrategy = strategy
        }
    }

    private func handleNextAction() {
        switch currentStep {
        case 0:
            advanceFromWelcome()
        case 1:
            advanceFromName()
        case 2:
            advanceFromAppSelection()
        case 3:
            completeOnboarding()
        default:
            break
        }
    }

    private func goBack() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            if currentStep > 0 {
                currentStep -= 1
            }
        }
    }

    private func skipOnboarding() {
        onboardingManager.skipOnboarding()
        dismiss()
        onComplete?(nil)
    }

    private func completeOnboarding() {
        // Create the profile
        do {
            let newProfile = try BlockedProfiles.createProfile(
                in: modelContext,
                name: profileName.trimmingCharacters(in: .whitespacesAndNewlines),
                selection: selectedActivity,
                blockingStrategyId: selectedStrategy.getIdentifier()
            )

            // Schedule restrictions
            DeviceActivityCenterUtil.scheduleTimerActivity(for: newProfile)

            // Complete onboarding
            onboardingManager.completeOnboarding()

            // Dismiss and notify
            dismiss()
            onComplete?(newProfile)
        } catch {
            // If profile creation fails, still complete onboarding
            print("⚠️ Onboarding: Failed to create profile: \(error.localizedDescription)")
            onboardingManager.completeOnboarding()
            dismiss()
            onComplete?(nil)
        }
    }
}

#Preview {
    OnboardingProfileSetupView()
        .environmentObject(ThemeManager.shared)
        .environmentObject(OnboardingManager.shared)
        .modelContainer(for: BlockedProfiles.self, inMemory: true)
}
