import SwiftUI

/// Direction the tooltip arrow points
enum TooltipArrowDirection {
    case up
    case down
    case left
    case right
}

/// A floating tooltip bubble with an arrow pointing to a target element
struct TooltipBubble: View {
    let text: String
    let arrowDirection: TooltipArrowDirection
    let stepIndicator: String?
    let onSkip: (() -> Void)?

    @EnvironmentObject var themeManager: ThemeManager

    private let cornerRadius: CGFloat = 16
    private let arrowSize: CGFloat = 12
    private let horizontalPadding: CGFloat = 20
    private let verticalPadding: CGFloat = 16

    init(
        text: String,
        arrowDirection: TooltipArrowDirection = .up,
        stepIndicator: String? = nil,
        onSkip: (() -> Void)? = nil
    ) {
        self.text = text
        self.arrowDirection = arrowDirection
        self.stepIndicator = stepIndicator
        self.onSkip = onSkip
    }

    var body: some View {
        VStack(spacing: 0) {
            if arrowDirection == .up {
                arrow
            }

            HStack(spacing: 0) {
                if arrowDirection == .left {
                    arrow
                }

                bubbleContent

                if arrowDirection == .right {
                    arrow
                }
            }

            if arrowDirection == .down {
                arrow
            }
        }
    }

    private var bubbleContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Step indicator and skip button row
            if stepIndicator != nil || onSkip != nil {
                HStack {
                    if let step = stepIndicator {
                        Text(step)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(themeManager.themeColor)
                    }

                    Spacer()

                    if let skip = onSkip {
                        Button(action: skip) {
                            Text(String(localized: "Skip Tutorial"))
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            // Tooltip text
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(UIColor.secondarySystemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(themeManager.themeColor.opacity(0.5), lineWidth: 2)
                )
        )
    }

    private var arrow: some View {
        Group {
            switch arrowDirection {
            case .up:
                Triangle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: arrowSize * 2, height: arrowSize)
                    .overlay(
                        Triangle()
                            .stroke(themeManager.themeColor.opacity(0.5), lineWidth: 2)
                    )
                    .offset(y: 1) // Overlap slightly with bubble
            case .down:
                Triangle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: arrowSize * 2, height: arrowSize)
                    .rotationEffect(.degrees(180))
                    .overlay(
                        Triangle()
                            .stroke(themeManager.themeColor.opacity(0.5), lineWidth: 2)
                            .rotationEffect(.degrees(180))
                    )
                    .offset(y: -1) // Overlap slightly with bubble
            case .left:
                Triangle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: arrowSize, height: arrowSize * 2)
                    .rotationEffect(.degrees(-90))
                    .overlay(
                        Triangle()
                            .stroke(themeManager.themeColor.opacity(0.5), lineWidth: 2)
                            .rotationEffect(.degrees(-90))
                    )
                    .offset(x: 1)
            case .right:
                Triangle()
                    .fill(Color(UIColor.secondarySystemBackground))
                    .frame(width: arrowSize, height: arrowSize * 2)
                    .rotationEffect(.degrees(90))
                    .overlay(
                        Triangle()
                            .stroke(themeManager.themeColor.opacity(0.5), lineWidth: 2)
                            .rotationEffect(.degrees(90))
                    )
                    .offset(x: -1)
            }
        }
    }
}

/// Triangle shape for tooltip arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// Modifier to add a pulsing highlight effect to target elements
struct PulsingHighlight: ViewModifier {
    let isActive: Bool
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isPulsing: Bool = false

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(themeManager.themeColor, lineWidth: 3)
                            .scaleEffect(isPulsing ? 1.02 : 1.0)
                            .opacity(isPulsing ? 0.6 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: isPulsing
                            )
                    }
                }
            )
            .onAppear {
                if isActive {
                    isPulsing = true
                }
            }
            .onChange(of: isActive) { _, newValue in
                isPulsing = newValue
            }
    }
}

extension View {
    func pulsingHighlight(isActive: Bool) -> some View {
        modifier(PulsingHighlight(isActive: isActive))
    }
}

#Preview {
    VStack(spacing: 40) {
        TooltipBubble(
            text: "Tap here to start setting up your blocking preferences",
            arrowDirection: .up,
            stepIndicator: "Step 1/4",
            onSkip: { print("Skip tapped") }
        )

        TooltipBubble(
            text: "Enter your profile name to personalize your DO experience",
            arrowDirection: .down,
            stepIndicator: "Step 2/4"
        )

        TooltipBubble(
            text: "Choose which apps you want to control with DO",
            arrowDirection: .left,
            stepIndicator: "Step 3/4"
        )
    }
    .padding()
    .environmentObject(ThemeManager.shared)
}
