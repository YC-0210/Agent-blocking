import SwiftUI

/// Semi-transparent overlay that dims inactive areas during onboarding
struct OnboardingOverlay: View {
    @EnvironmentObject var onboardingManager: OnboardingManager
    @EnvironmentObject var themeManager: ThemeManager

    let currentStep: Int
    let targetFrame: CGRect
    let tooltipText: String
    let onSkip: () -> Void

    @State private var isVisible: Bool = false

    private let overlayOpacity: CGFloat = 0.7
    private let animationDuration: CGFloat = 0.3

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Dimmed overlay with cutout for target
                overlayWithCutout(in: geometry)

                // Tooltip bubble positioned relative to target
                tooltipView(in: geometry)
            }
        }
        .ignoresSafeArea()
        .opacity(isVisible ? 1 : 0)
        .onAppear {
            withAnimation(.easeOut(duration: animationDuration)) {
                isVisible = true
            }
        }
    }

    private func overlayWithCutout(in geometry: GeometryProxy) -> some View {
        Canvas { context, size in
            // Fill the entire canvas with semi-transparent black
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(.black.opacity(overlayOpacity))
            )

            // Cut out the target area with some padding
            let padding: CGFloat = 8
            let cutoutRect = targetFrame.insetBy(dx: -padding, dy: -padding)
            let cutoutPath = Path(roundedRect: cutoutRect, cornerRadius: 20)

            // Use blend mode to cut out the target area
            context.blendMode = .destinationOut
            context.fill(cutoutPath, with: .color(.white))
        }
        .compositingGroup()
        .allowsHitTesting(false)
    }

    private func tooltipView(in geometry: GeometryProxy) -> some View {
        let tooltipWidth: CGFloat = min(300, geometry.size.width - 40)
        let arrowDirection = calculateArrowDirection(in: geometry)
        let position = calculateTooltipPosition(in: geometry, tooltipWidth: tooltipWidth, arrowDirection: arrowDirection)

        return TooltipBubble(
            text: tooltipText,
            arrowDirection: arrowDirection,
            stepIndicator: "Step \(currentStep + 1)/5",
            onSkip: onSkip
        )
        .frame(width: tooltipWidth)
        .position(position)
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
    }

    private func calculateArrowDirection(in geometry: GeometryProxy) -> TooltipArrowDirection {
        let screenHeight = geometry.size.height
        let targetCenterY = targetFrame.midY

        // If target is in the upper half, tooltip goes below (arrow points up)
        // If target is in the lower half, tooltip goes above (arrow points down)
        if targetCenterY < screenHeight / 2 {
            return .up
        } else {
            return .down
        }
    }

    private func calculateTooltipPosition(
        in geometry: GeometryProxy,
        tooltipWidth: CGFloat,
        arrowDirection: TooltipArrowDirection
    ) -> CGPoint {
        let screenWidth = geometry.size.width
        let padding: CGFloat = 20
        let tooltipOffset: CGFloat = 20 // Distance from target

        // Calculate X position (centered on target, clamped to screen edges)
        var x = targetFrame.midX
        let halfWidth = tooltipWidth / 2
        x = max(halfWidth + padding, min(x, screenWidth - halfWidth - padding))

        // Calculate Y position based on arrow direction
        let y: CGFloat
        let estimatedTooltipHeight: CGFloat = 100

        switch arrowDirection {
        case .up:
            y = targetFrame.maxY + tooltipOffset + estimatedTooltipHeight / 2
        case .down:
            y = targetFrame.minY - tooltipOffset - estimatedTooltipHeight / 2
        case .left, .right:
            y = targetFrame.midY
        }

        return CGPoint(x: x, y: y)
    }
}

/// Progress bar showing onboarding completion
struct OnboardingProgressBar: View {
    let currentStep: Int
    let totalSteps: Int

    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)

                // Progress fill
                RoundedRectangle(cornerRadius: 2)
                    .fill(themeManager.themeColor)
                    .frame(width: progressWidth(in: geometry), height: 4)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: currentStep)
            }
        }
        .frame(height: 4)
    }

    private func progressWidth(in geometry: GeometryProxy) -> CGFloat {
        let progress = CGFloat(currentStep + 1) / CGFloat(totalSteps)
        return geometry.size.width * progress
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Text("Background Content")
                .foregroundColor(.white)
        }

        OnboardingOverlay(
            currentStep: 0,
            targetFrame: CGRect(x: 50, y: 200, width: 300, height: 150),
            tooltipText: "Tap here to start setting up your blocking preferences",
            onSkip: { print("Skip tapped") }
        )
    }
    .environmentObject(OnboardingManager.shared)
    .environmentObject(ThemeManager.shared)
}
