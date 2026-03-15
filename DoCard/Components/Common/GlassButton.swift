import SwiftUI

struct GlassButton: View {
  let title: String
  let icon: String
  var fullWidth: Bool = true
  var equalWidth: Bool = false
  var longPressEnabled: Bool = false
  var longPressDuration: Double = 0.8
  var color: Color? = nil
  let action: () -> Void

  var body: some View {
    if longPressEnabled {
      longPressButton
    } else {
      standardButton
    }
  }

  private var standardButton: some View {
    Button(action: action) {
      buttonContent
    }
    .buttonStyle(PressableButtonStyle())
    .frame(minWidth: 0, maxWidth: equalWidth ? .infinity : nil)
  }

  @State private var isPressed = false
  @State private var holdProgress: CGFloat = 0

  private var longPressButton: some View {
    ZStack {
      buttonContent
        .overlay(
          // Progress fill during long press
          GeometryReader { geometry in
            RoundedRectangle(cornerRadius: 16)
              .fill((color ?? Color.primary).opacity(0.12))
              .frame(width: geometry.size.width * holdProgress)
              .animation(.linear(duration: longPressDuration), value: holdProgress)
          }
          .allowsHitTesting(false)
          .clipShape(RoundedRectangle(cornerRadius: 16))
        )
    }
    .contentShape(Rectangle())
    .frame(minWidth: 0, maxWidth: equalWidth ? .infinity : nil)
    .scaleEffect(isPressed ? 0.96 : 1.0)
    .animation(.spring(response: 0.3), value: isPressed)
    .onLongPressGesture(
        minimumDuration: longPressDuration,
        pressing: { pressing in
          isPressed = pressing
          if pressing {
            holdProgress = 1.0
            UIImpactFeedbackGenerator(style: .light).impactOccurred(intensity: 0.6)
          } else {
            holdProgress = 0
          }
        },
        perform: {
          holdProgress = 0
          let generator = UIImpactFeedbackGenerator(style: .heavy)
          generator.impactOccurred()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            generator.impactOccurred(intensity: 0.7)
          }
          action()
          isPressed = false
        }
      )

  }

  private var buttonContent: some View {
    HStack(spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 16, weight: .medium))
      Text(title)
        .fontWeight(.semibold)
        .font(.subheadline)
    }
    .frame(
      minWidth: 0,
      maxWidth: fullWidth ? .infinity : (equalWidth ? .infinity : nil)
    )
    .padding(.vertical, 12)
    .padding(.horizontal, fullWidth ? nil : 24)
    .background(
      RoundedRectangle(cornerRadius: 16)
        .fill(.thinMaterial)
        .overlay(
          RoundedRectangle(cornerRadius: 16)
            .stroke((color ?? Color.primary).opacity(0.2), lineWidth: 1)
        )
    )
    .foregroundColor(color ?? .primary)
  }
}

private struct PressableButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())
      .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
      .animation(.spring(response: 0.3), value: configuration.isPressed)
  }
}

#Preview {
  VStack(spacing: 20) {
    GlassButton(
      title: "Regular Button",
      icon: "play.fill"
    ) {
      print("Regular button tapped")
    }

    GlassButton(
      title: "Blue Button",
      icon: "star.fill",
      color: .blue
    ) {
      print("Blue button tapped")
    }

    GlassButton(
      title: "Hold to Start",
      icon: "play.fill",
      longPressEnabled: true,
      color: .green
    ) {
      print("Long press completed")
    }
  }
  .padding()
  .background(Color(.systemGroupedBackground))
}
