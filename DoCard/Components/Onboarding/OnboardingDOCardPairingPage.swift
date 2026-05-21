import AVKit
import SwiftUI

struct OnboardingDOCardPairingPage: View {
  @EnvironmentObject var onboardingManager: OnboardingManager

  let onContinue: () -> Void

  private enum ScanState {
    case idle
    case scanning
    case success
    case error(String)
  }

  @State private var showContent = false
  @State private var showButton = false
  @State private var scanState: ScanState = .idle
  @State private var isVideoPlaying = true
  @State private var cardName: String = ""

  private let nfcScanner = NFCScannerUtil()

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      // Title
      Text(String(localized: "配對你的 DO Card"))
        .font(.system(size: 28, weight: .bold))
        .foregroundColor(.white)
        .multilineTextAlignment(.center)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)
        .padding(.bottom, 8)

      // Subtitle
      Text(String(localized: "將 DO Card 靠近手機背面\n完成配對"))
        .font(.system(size: 16, weight: .regular))
        .foregroundColor(.white.opacity(0.5))
        .multilineTextAlignment(.center)
        .lineSpacing(4)
        .opacity(showContent ? 1.0 : 0)
        .offset(y: showContent ? 0 : 10)
        .padding(.bottom, 40)

      // DO Card tapping video
      ControllableLoopingVideoPlayer(
        fileName: "DOCardTappingVideo",
        fileExtension: "mp4",
        isPlaying: $isVideoPlaying
      )
      .aspectRatio(1.585, contentMode: .fit)
      .frame(maxWidth: 300)
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .scaleEffect(showContent ? 1.0 : 0.85)
      .opacity(showContent ? 1.0 : 0)

      // Status text
      statusText
        .padding(.top, 24)
        .opacity(showContent ? 1.0 : 0)

      Spacer()
      Spacer()

      // Bottom buttons
      VStack(spacing: 12) {
        // Card name input — shown in idle and error states
        if shouldShowNameField {
          TextField(String(localized: "例：彥丞的 DO Card"), text: $cardName)
            .font(.system(size: 16))
            .foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
              RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.1))
                .overlay(
                  RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
            )
            .colorScheme(.dark)
            .onChange(of: cardName) { _, newValue in
              if newValue.count > 20 {
                cardName = String(newValue.prefix(20))
              }
            }
        }

        Button(action: {
          UIImpactFeedbackGenerator(style: .medium).impactOccurred()
          handleButtonTap()
        }) {
          Text(buttonTitle)
            .font(.system(size: 18, weight: .semibold))
            .foregroundColor(isButtonDisabled ? .black.opacity(0.4) : .black)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
              Capsule()
                .fill(isButtonDisabled ? Color.white.opacity(0.4) : Color.white)
            )
        }
        .disabled(isButtonDisabled)

        // Skip button — allows users without a DO Card to go directly to the main app
        if case .success = scanState {
          // Hide skip after successful scan
        } else {
          Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onContinue()
          }) {
            Text(String(localized: "使用他人卡片"))
              .font(.system(size: 15, weight: .medium))
              .foregroundColor(.white.opacity(0.5))
          }
          .frame(minHeight: 44)
        }
      }
      .padding(.horizontal, 24)
      .padding(.bottom, 30)
      .opacity(showButton ? 1.0 : 0)
      .offset(y: showButton ? 0 : 20)
    }
    .onAppear {
      withAnimation(.spring(response: 0.8, dampingFraction: 0.75).delay(0.2)) {
        showContent = true
      }
      withAnimation(.easeOut(duration: 0.7).delay(0.8)) {
        showButton = true
      }
    }
  }

  private var shouldShowNameField: Bool {
    switch scanState {
    case .idle, .error: return true
    default: return false
    }
  }

  private var isButtonDisabled: Bool {
    switch scanState {
    case .scanning: return true
    case .idle, .error: return cardName.trimmingCharacters(in: .whitespaces).isEmpty
    case .success: return false
    }
  }

  private var buttonTitle: String {
    switch scanState {
    case .idle, .error:
      return String(localized: "開始配對")
    case .scanning:
      return String(localized: "掃描中...")
    case .success:
      return String(localized: "繼續")
    }
  }

  @ViewBuilder
  private var statusText: some View {
    switch scanState {
    case .idle:
      Text(String(localized: "輸入卡片名稱後點擊配對"))
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(.white.opacity(0.4))
    case .scanning:
      Text(String(localized: "請將 DO Card 靠近手機..."))
        .font(.system(size: 15, weight: .medium))
        .foregroundColor(.white.opacity(0.6))
    case .success:
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .foregroundColor(.green)
        Text(String(localized: "配對成功"))
          .foregroundColor(.green)
      }
      .font(.system(size: 15, weight: .semibold))
    case .error(let message):
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.circle.fill")
          .foregroundColor(.red)
        Text(message)
          .foregroundColor(.red)
      }
      .font(.system(size: 15, weight: .medium))
    }
  }

  // MARK: - Actions

  private func handleButtonTap() {
    switch scanState {
    case .success:
      onContinue()
    case .scanning:
      break
    default:
      startScanning()
    }
  }

  private func startScanning() {
    let name = cardName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }

    scanState = .scanning
    isVideoPlaying = false

    nfcScanner.onTagScanned = { result in
      guard result.payload != nil else {
        withAnimation(.easeOut(duration: 0.3)) {
          scanState = .error(String(localized: "這不是有效的 DO Card"))
        }
        isVideoPlaying = true
        return
      }

      onboardingManager.pairDOCard(tagId: result.id)
      // Persist the card name (scanned from tag, or the name we just wrote)
      onboardingManager.doCardName = result.cardName ?? name

      withAnimation(.easeOut(duration: 0.3)) {
        scanState = .success
      }

      // Auto-advance after brief success animation
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
        onContinue()
      }
    }

    nfcScanner.onError = { _ in
      withAnimation(.easeOut(duration: 0.3)) {
        scanState = .idle
      }
      isVideoPlaying = true
    }

    nfcScanner.onCancel = {
      withAnimation(.easeOut(duration: 0.3)) {
        scanState = .idle
      }
      isVideoPlaying = true
    }

    // Single-session: read to verify + write new JSON payload with name.
    // requirePaired: false — this is initial pairing, the card is not in the paired list yet.
    nfcScanner.scanAndWrite(name: name, requirePaired: false)
  }
}

// MARK: - Controllable Looping Video Player

struct ControllableLoopingVideoPlayer: UIViewRepresentable {
  let fileName: String
  let fileExtension: String
  @Binding var isPlaying: Bool

  func makeUIView(context: Context) -> ControllablePlayerUIView {
    ControllablePlayerUIView(fileName: fileName, fileExtension: fileExtension)
  }

  func updateUIView(_ uiView: ControllablePlayerUIView, context: Context) {
    if isPlaying {
      uiView.play()
    } else {
      uiView.pause()
    }
  }
}

class ControllablePlayerUIView: UIView {
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
    playerLayer.videoGravity = .resizeAspectFill
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

  func play() {
    queuePlayer?.play()
  }

  func pause() {
    queuePlayer?.pause()
  }
}

#Preview {
  ZStack {
    Color.black.ignoresSafeArea()
    OnboardingDOCardPairingPage(onContinue: {})
  }
  .environmentObject(ThemeManager.shared)
  .environmentObject(OnboardingManager.shared)
  .preferredColorScheme(.dark)
}
