import AVKit
import SwiftUI

struct OnboardingWelcomePage: View {
  @EnvironmentObject var themeManager: ThemeManager

  let onContinue: () -> Void

  // Animation states
  @State private var showVideo = false
  @State private var showTitle = false
  @State private var showSubtitle = false
  @State private var showButton = false

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      // Brand video — large, centered
      LoopingVideoPlayer(fileName: "DOCardBrandVideo", fileExtension: "mp4")
        .frame(maxWidth: 300, maxHeight: 300)
        .clipShape(RoundedRectangle(cornerRadius: 0))
        .scaleEffect(showVideo ? 1.0 : 0.8)
        .opacity(showVideo ? 1.0 : 0)

      Spacer()

      // Title: "歡迎來到 DO"
      HStack(spacing: 0) {
        Text(String(localized: "歡迎來到 "))
          .font(.system(size: 32, weight: .bold))
          .foregroundColor(.white)

        Text("DO")
          .font(.system(size: 32, weight: .bold))
          .foregroundStyle(
            LinearGradient(
              colors: [
                themeManager.themeColor,
                themeManager.themeColor.opacity(0.7),
              ],
              startPoint: .leading,
              endPoint: .trailing
            )
          )
      }
      .opacity(showTitle ? 1.0 : 0)
      .offset(y: showTitle ? 0 : 10)
      .padding(.bottom, 14)

      // Subtitle
      Text(String(localized: "你應該有想完成的事情吧"))
        .font(.system(size: 16, weight: .regular))
        .foregroundColor(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .opacity(showSubtitle ? 1.0 : 0)
        .offset(y: showSubtitle ? 0 : 10)

      Spacer()

      // "繼續" button
      Button(action: {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onContinue()
      }) {
        Text(String(localized: "繼續"))
          .font(.system(size: 18, weight: .semibold))
          .foregroundColor(.black)
          .frame(maxWidth: .infinity)
          .frame(height: 58)
          .background(
            Capsule()
              .fill(Color.white)
          )
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .opacity(showButton ? 1.0 : 0)
      .offset(y: showButton ? 0 : 20)
    }
    .onAppear {
      withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
        showVideo = true
      }
      withAnimation(.easeOut(duration: 0.6).delay(0.5)) {
        showTitle = true
      }
      withAnimation(.easeOut(duration: 0.6).delay(0.7)) {
        showSubtitle = true
      }
      withAnimation(.easeOut(duration: 0.6).delay(0.9)) {
        showButton = true
      }
    }
  }
}

// MARK: - Looping Video Player

struct LoopingVideoPlayer: UIViewRepresentable {
  let fileName: String
  let fileExtension: String

  func makeUIView(context: Context) -> UIView {
    let view = PlayerUIView(fileName: fileName, fileExtension: fileExtension)
    return view
  }

  func updateUIView(_ uiView: UIView, context: Context) {}
}

private class PlayerUIView: UIView {
  private var playerLayer = AVPlayerLayer()
  private var playerLooper: AVPlayerLooper?
  private var queuePlayer: AVQueuePlayer?

  init(fileName: String, fileExtension: String) {
    super.init(frame: .zero)

    guard let url = Bundle.main.url(forResource: fileName, withExtension: fileExtension) else {
      return
    }

    let playerItem = AVPlayerItem(url: url)
    let player = AVQueuePlayer(playerItem: playerItem)
    playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
    queuePlayer = player

    playerLayer.player = player
    playerLayer.videoGravity = .resizeAspect
    layer.addSublayer(playerLayer)

    player.isMuted = true
    player.play()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    playerLayer.frame = bounds
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingWelcomePage(onContinue: {})
  }
  .environmentObject(ThemeManager.shared)
  .preferredColorScheme(.dark)
}
