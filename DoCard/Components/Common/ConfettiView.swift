import SwiftUI

struct ConfettiParticle: Identifiable {
  let id = UUID()
  var x: CGFloat
  var y: CGFloat
  let color: Color
  let size: CGFloat
  let rotation: Double
  let rotationSpeed: Double
  let xVelocity: CGFloat
  let yVelocity: CGFloat
  let shape: ParticleShape

  enum ParticleShape: CaseIterable {
    case circle, rectangle, triangle
  }
}

struct ConfettiView: View {
  @Binding var isActive: Bool
  var themeColor: Color = .orange

  @State private var particles: [ConfettiParticle] = []
  @State private var elapsed: TimeInterval = 0

  private let particleCount = 40
  private let duration: TimeInterval = 2.0

  var body: some View {
    GeometryReader { geometry in
      TimelineView(.animation) { timeline in
        Canvas { context, size in
          for particle in particles {
            let age = elapsed
            let gravity: CGFloat = 400
            let drag: CGFloat = 0.97

            let currentX = particle.x + particle.xVelocity * CGFloat(age) * drag
            let currentY = particle.y + particle.yVelocity * CGFloat(age) * drag + 0.5 * gravity * CGFloat(age * age)
            let currentRotation = particle.rotation + particle.rotationSpeed * age
            let alpha = max(0, 1.0 - age / duration)

            guard alpha > 0 else { continue }

            context.opacity = alpha
            var transform = CGAffineTransform.identity
            transform = transform.translatedBy(x: currentX, y: currentY)
            transform = transform.rotated(by: currentRotation)

            let rect = CGRect(
              x: -particle.size / 2,
              y: -particle.size / 2,
              width: particle.size,
              height: particle.size * 0.6
            )

            var path: Path
            switch particle.shape {
            case .circle:
              path = Path(ellipseIn: rect)
            case .rectangle:
              path = Path(rect)
            case .triangle:
              path = Path()
              path.move(to: CGPoint(x: 0, y: -particle.size / 2))
              path.addLine(to: CGPoint(x: particle.size / 2, y: particle.size / 2))
              path.addLine(to: CGPoint(x: -particle.size / 2, y: particle.size / 2))
              path.closeSubpath()
            }

            let transformedPath = path.applying(transform)
            context.fill(transformedPath, with: .color(particle.color))
          }
        }
        .onChange(of: timeline.date) { _, newDate in
          if isActive {
            elapsed += 1.0 / 60.0
            if elapsed >= duration {
              isActive = false
              particles = []
              elapsed = 0
            }
          }
        }
      }
      .onChange(of: isActive) { _, newValue in
        if newValue {
          elapsed = 0
          particles = generateParticles(in: geometry.size)
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func generateParticles(in size: CGSize) -> [ConfettiParticle] {
    let colors: [Color] = [
      themeColor,
      themeColor.opacity(0.7),
      .white,
      .yellow,
      .mint,
      themeColor.opacity(0.5),
    ]

    return (0..<particleCount).map { _ in
      let startX = size.width / 2 + CGFloat.random(in: -30...30)
      let startY = size.height * 0.4

      return ConfettiParticle(
        x: startX,
        y: startY,
        color: colors.randomElement()!,
        size: CGFloat.random(in: 4...10),
        rotation: Double.random(in: 0...(2 * .pi)),
        rotationSpeed: Double.random(in: -8...8),
        xVelocity: CGFloat.random(in: -180...180),
        yVelocity: CGFloat.random(in: -350 ... -150),
        shape: ConfettiParticle.ParticleShape.allCases.randomElement()!
      )
    }
  }
}
