import FamilyControls
import SwiftUI

struct BlockedProfileCard: View {
  @EnvironmentObject var themeManager: ThemeManager

  let profile: BlockedProfiles

  var isActive: Bool = false
  var isBreakAvailable: Bool = false
  var isBreakActive: Bool = false

  var elapsedTime: TimeInterval? = nil

  var onStartTapped: () -> Void
  var onStopTapped: () -> Void
  var onEditTapped: () -> Void
  var onStatsTapped: () -> Void = {}
  var onBreakTapped: () -> Void

  // 3D tilt press state
  @State private var pressLocation: CGPoint = .zero
  @State private var isPressed: Bool = false

  // Track previous active state for transition haptics
  @State private var wasActive: Bool = false

  // Keep a reference to the CardBackground to access color
  private var cardBackground: CardBackground {
    CardBackground(isActive: isActive, customColor: themeManager.themeColor)
  }

  // Compute 3D rotation angles from press location
  private func rotationX(in size: CGSize) -> Double {
    guard isPressed, size.height > 0 else { return 0 }
    let normalizedY = (pressLocation.y / size.height) - 0.5
    return normalizedY * 4 // subtle tilt, max ~2 degrees
  }

  private func rotationY(in size: CGSize) -> Double {
    guard isPressed, size.width > 0 else { return 0 }
    let normalizedX = (pressLocation.x / size.width) - 0.5
    return -normalizedX * 4
  }

  var body: some View {
    GeometryReader { geometry in
      ZStack {
        // Use the CardBackground component
        cardBackground

        // Content
        VStack(alignment: .leading, spacing: 12) {
          // Header section - Profile name, edit button, and indicators
          HStack {
            VStack(alignment: .leading, spacing: 10) {
              Text(profile.name)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)

              // Using the new ProfileIndicators component
              ProfileIndicators(
                enableLiveActivity: profile.enableLiveActivity,
                hasReminders: profile.reminderTimeInSeconds != nil,
                enableBreaks: profile.enableBreaks,
                isActive: isActive
              )
            }

            Spacer()

            // Menu button moved to top right
            Menu {
              Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onEditTapped()
              }) {
                Label(String(localized: "Edit"), systemImage: "pencil")
              }
              Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onStatsTapped()
              }) {
                Label(String(localized: "Stats for Nerds"), systemImage: "eyeglasses")
              }

              Divider()

              if isActive && profile.showStopButton(elapsedTime: elapsedTime ?? 0) {
                Button(action: {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  onStopTapped()
                }) {
                  Label(String(localized: "Stop"), systemImage: "stop.fill")
                }
              } else if !isActive {
                Button(action: {
                  UIImpactFeedbackGenerator(style: .light).impactOccurred()
                  onStartTapped()
                }) {
                  Label(String(localized: "Start"), systemImage: "play.fill")
                }
              }
            } label: {
              Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)
                .padding(10)
                .background(
                  Circle()
                    .fill(.thinMaterial)
                    .overlay(
                      Circle()
                        .stroke(
                          Color.primary.opacity(0.2),
                          lineWidth: 1
                        )
                    )
                )
            }
          }

          // Middle section - Strategy and apps info
          VStack(alignment: .leading, spacing: 16) {
            StrategyInfoView(strategyId: profile.blockingStrategyId)

            // Using the new ProfileStatsRow component
            ProfileStatsRow(
              selectedActivity: profile.selectedActivity,
              sessionCount: profile.sessions.count,
              domainsCount: profile.domains?.count ?? 0
            )
          }

          Spacer(minLength: 4)

          ProfileTimerButton(
            isActive: isActive,
            isBreakAvailable: isBreakAvailable,
            isBreakActive: isBreakActive,
            elapsedTime: elapsedTime,
            showStopButton: profile.showStopButton(elapsedTime: elapsedTime ?? 0),
            onStartTapped: onStartTapped,
            onStopTapped: onStopTapped,
            onBreakTapped: onBreakTapped
          )
        }
        .padding(16)
      }
      // 3D tilt on press
      .rotation3DEffect(
        .degrees(rotationX(in: geometry.size)),
        axis: (x: 1, y: 0, z: 0),
        perspective: 0.5
      )
      .rotation3DEffect(
        .degrees(rotationY(in: geometry.size)),
        axis: (x: 0, y: 1, z: 0),
        perspective: 0.5
      )
      .scaleEffect(isPressed ? 0.97 : 1.0)
      .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isPressed)
      .simultaneousGesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            pressLocation = value.location
            if !isPressed {
              isPressed = true
              UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.5)
            }
          }
          .onEnded { _ in
            isPressed = false
          }
      )
      // State transition haptics
      .onChange(of: isActive) { _, newValue in
        if newValue && !wasActive {
          UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else if !newValue && wasActive {
          UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        wasActive = newValue
      }
      .onAppear {
        wasActive = isActive
      }
    }
  }
}

#Preview {
  ZStack {
    Color(.systemGroupedBackground).ignoresSafeArea()

    VStack(spacing: 40) {
      // Inactive card
      BlockedProfileCard(
        profile: BlockedProfiles(
          id: UUID(),
          name: "Work",
          selectedActivity: FamilyActivitySelection(),
          blockingStrategyId: NFCBlockingStrategy.id,
          enableLiveActivity: true,
          reminderTimeInSeconds: 3600
        ),
        onStartTapped: {},
        onStopTapped: {},
        onEditTapped: {},
        onBreakTapped: {}
      )

      // Active card with timer
      BlockedProfileCard(
        profile: BlockedProfiles(
          id: UUID(),
          name: "Gaming",
          selectedActivity: FamilyActivitySelection(),
          blockingStrategyId: NFCBlockingStrategy.id,
          enableLiveActivity: true,
          reminderTimeInSeconds: 3600
        ),
        isActive: true,
        isBreakAvailable: true,
        elapsedTime: 1845,  // 30 minutes and 45 seconds
        onStartTapped: {},
        onStopTapped: {},
        onEditTapped: {},
        onBreakTapped: {}
      )
    }
  }
}
