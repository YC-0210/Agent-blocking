import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG sticker (1080×1920) showing the focus session result.
/// Layout (vertically centered):
///   1. Profile name — SF Pro Display Bold ~60pt, white, wide tracking
///   2. Duration — SF Mono Bold ~220pt, white (visual anchor)
///   3. DO logo — asset or text fallback, near bottom
enum FocusShareCardGenerator {

  static let canvasWidth: CGFloat = 1080
  static let canvasHeight: CGFloat = 1920

  // MARK: - Public

  static func render(profileName: String, duration: TimeInterval) -> UIImage {
    let size = CGSize(width: canvasWidth, height: canvasHeight)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1 // exact pixel dimensions
    format.opaque = false // transparent background

    let renderer = UIGraphicsImageRenderer(size: size, format: format)

    return renderer.image { ctx in
      // Background is fully transparent — nothing to fill.

      let white = UIColor.white

      // --- 1. Profile name ---
      let profileFont = UIFont.systemFont(ofSize: 60, weight: .bold)
      let profileAttrs: [NSAttributedString.Key: Any] = [
        .font: profileFont,
        .foregroundColor: white,
        .kern: 2.0,
      ]
      let profileStr = NSAttributedString(string: profileName, attributes: profileAttrs)
      let profileSize = profileStr.size()

      // --- 2. Duration (main) ---
      let durationText = Self.formatDuration(duration)
      let monoFont: UIFont = {
        if let mono = UIFont(name: "SFMono-Bold", size: 220) { return mono }
        return UIFont.monospacedSystemFont(ofSize: 220, weight: .bold)
      }()
      let durationAttrs: [NSAttributedString.Key: Any] = [
        .font: monoFont,
        .foregroundColor: white,
      ]
      let durationStr = NSAttributedString(string: durationText, attributes: durationAttrs)
      let durationSize = durationStr.size()

      // --- 3. Logo ---
      let logoHeight: CGFloat = 60
      let logoImage = UIImage(named: "DOLogo")
      let logoSize: CGSize
      let logoIsImage: Bool

      if let img = logoImage, img.size.width > 0 {
        let targetWidth = canvasWidth * 0.20
        let scale = targetWidth / img.size.width
        logoSize = CGSize(width: targetWidth, height: img.size.height * scale)
        logoIsImage = true
      } else {
        // Text fallback "DO"
        logoSize = CGSize(width: 120, height: logoHeight)
        logoIsImage = false
      }

      // --- Vertical layout (centred group): logo → profile name → duration ---
      let spacing: CGFloat = 40
      let groupHeight = logoSize.height + spacing + profileSize.height + spacing + durationSize.height
      let startY = (canvasHeight - groupHeight) / 2

      // Draw logo
      let logoY = startY
      if logoIsImage, let img = logoImage {
        let logoRect = CGRect(
          x: (canvasWidth - logoSize.width) / 2,
          y: logoY,
          width: logoSize.width,
          height: logoSize.height
        )
        // Draw original image (transparent PNG with orange colour)
        img.draw(in: logoRect)
      } else {
        // Text fallback
        let logoFont = UIFont.systemFont(ofSize: 80, weight: .bold)
        let logoAttrs: [NSAttributedString.Key: Any] = [
          .font: logoFont,
          .foregroundColor: white,
        ]
        let logoStr = NSAttributedString(string: "DO", attributes: logoAttrs)
        let actualLogoSize = logoStr.size()
        let logoOrigin = CGPoint(
          x: (canvasWidth - actualLogoSize.width) / 2,
          y: logoY
        )
        logoStr.draw(at: logoOrigin)
      }

      // Draw profile name
      let profileOrigin = CGPoint(
        x: (canvasWidth - profileSize.width) / 2,
        y: logoY + logoSize.height + spacing
      )
      profileStr.draw(at: profileOrigin)

      // Draw duration
      let durationOrigin = CGPoint(
        x: (canvasWidth - durationSize.width) / 2,
        y: logoY + logoSize.height + spacing + profileSize.height + spacing
      )
      durationStr.draw(at: durationOrigin)
    }
  }

  // MARK: - Helpers

  /// Formats duration as `H:MM:SS`
  static func formatDuration(_ duration: TimeInterval) -> String {
    let totalSeconds = Int(max(0, duration))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let seconds = totalSeconds % 60
    return String(format: "%d:%02d:%02d", hours, minutes, seconds)
  }
}
