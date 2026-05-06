import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG (1080×1920) of the focus session result.
///
/// Layout follows the original HTML reference, scaled 1.73× from a 220px design number
/// to the 380pt rendered number. The four elements (pill → number → caption → logo) form
/// one vertical group flex-centred in the canvas, leaving equal top/bottom whitespace.
///
///   Element     Spec (HTML px)          Rendered (pt)
///   -------     -----------------       -------------
///   Pill name   font 22, pad 10/22      font 38, pad 17/38
///   Number      font 220, lh 0.9        font 380, mono bold
///   Caption     font 18, ls 0.4em       font 31, kern 12
///   Logo        height 48               height 83
///   Gaps        28 / 8 / 28             48 / 14 / 48
enum FocusShareCardGenerator {

  static let canvasWidth: CGFloat = 1080
  static let canvasHeight: CGFloat = 1920

  // MARK: - Public

  static func render(profileName: String, duration: TimeInterval) -> UIImage {
    let size = CGSize(width: canvasWidth, height: canvasHeight)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = false  // transparent background

    let renderer = UIGraphicsImageRenderer(size: size, format: format)

    return renderer.image { ctx in
      let cg = ctx.cgContext
      let white = UIColor.white

      // --- Spec-driven sizes (scaled 1.73× from HTML reference) ---
      let nameFontSize: CGFloat = 38
      let numberFontSize: CGFloat = 380
      let captionFontSize: CGFloat = 31

      let pillVerticalPadding: CGFloat = 17
      let pillHorizontalPadding: CGFloat = 38
      let pillStrokeWidth: CGFloat = 3

      let logoTargetHeight: CGFloat = 83

      let pillToNumberGap: CGFloat = 48
      let numberToCaptionGap: CGFloat = 14
      let captionToLogoGap: CGFloat = 48

      // --- Compute duration text + units ---
      let totalSeconds = Int(max(0, duration))
      let hours = totalSeconds / 3600
      let minutes = (totalSeconds % 3600) / 60

      let numberText: String
      let unitsText: String
      if hours >= 1 {
        numberText = "\(hours):\(String(format: "%02d", minutes))"
        unitsText = String(localized: "小時 · 分鐘")
      } else {
        numberText = "\(minutes)"
        unitsText = String(localized: "分鐘")
      }

      // --- Build attributed strings ---
      let nameFont = UIFont.systemFont(ofSize: nameFontSize, weight: .semibold)
      let numberFont: UIFont = {
        if let mono = UIFont(name: "SFMono-Bold", size: numberFontSize) { return mono }
        return UIFont.monospacedSystemFont(ofSize: numberFontSize, weight: .bold)
      }()
      let captionFont = UIFont.systemFont(ofSize: captionFontSize, weight: .regular)

      let nameStr = NSAttributedString(string: profileName, attributes: [
        .font: nameFont,
        .foregroundColor: white,
        .kern: 1.0,
      ])
      let numberStr = NSAttributedString(string: numberText, attributes: [
        .font: numberFont,
        .foregroundColor: white,
      ])
      let captionStr = NSAttributedString(string: unitsText, attributes: [
        .font: captionFont,
        .foregroundColor: UIColor.white.withAlphaComponent(0.7),
        .kern: 12.0,  // 0.4em × 31pt
      ])

      let nameSize = nameStr.size()
      let numberSize = numberStr.size()
      let captionSize = captionStr.size()

      // Pill
      let pillW = nameSize.width + pillHorizontalPadding * 2
      let pillH = nameSize.height + pillVerticalPadding * 2

      // Logo
      let logoImage = UIImage(named: "DOLogo")
      let logoSize: CGSize = {
        if let img = logoImage, img.size.width > 0 {
          let scale = logoTargetHeight / img.size.height
          return CGSize(width: img.size.width * scale, height: logoTargetHeight)
        }
        return CGSize(width: 200, height: logoTargetHeight)
      }()

      // --- Group layout (flex-centred vertically) ---
      let groupHeight =
        pillH
        + pillToNumberGap
        + numberSize.height
        + numberToCaptionGap
        + captionSize.height
        + captionToLogoGap
        + logoSize.height
      let groupTop = (canvasHeight - groupHeight) / 2

      // --- 1. Profile-name pill ---
      let pillRect = CGRect(
        x: (canvasWidth - pillW) / 2,
        y: groupTop,
        width: pillW,
        height: pillH
      )
      let pillPath = UIBezierPath(
        roundedRect: pillRect,
        cornerRadius: pillH / 2
      )
      cg.saveGState()
      cg.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
      cg.setLineWidth(pillStrokeWidth)
      cg.addPath(pillPath.cgPath)
      cg.strokePath()
      cg.restoreGState()

      let nameOrigin = CGPoint(
        x: pillRect.midX - nameSize.width / 2,
        y: pillRect.midY - nameSize.height / 2
      )
      nameStr.draw(at: nameOrigin)

      // --- 2. Number ---
      let numberY = pillRect.maxY + pillToNumberGap
      let numberOrigin = CGPoint(x: (canvasWidth - numberSize.width) / 2, y: numberY)
      numberStr.draw(at: numberOrigin)

      // --- 3. Caption ---
      let captionY = numberY + numberSize.height + numberToCaptionGap
      let captionOrigin = CGPoint(x: (canvasWidth - captionSize.width) / 2, y: captionY)
      captionStr.draw(at: captionOrigin)

      // --- 4. Logo ---
      let logoY = captionY + captionSize.height + captionToLogoGap
      if let img = logoImage {
        let logoRect = CGRect(
          x: (canvasWidth - logoSize.width) / 2,
          y: logoY,
          width: logoSize.width,
          height: logoSize.height
        )
        img.draw(in: logoRect)
      } else {
        let fallbackFont = UIFont.systemFont(ofSize: logoTargetHeight, weight: .bold)
        let fallback = NSAttributedString(
          string: "DO",
          attributes: [.font: fallbackFont, .foregroundColor: white]
        )
        let fSize = fallback.size()
        fallback.draw(at: CGPoint(x: (canvasWidth - fSize.width) / 2, y: logoY))
      }
    }
  }
}
