import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG (1080×1920) of the focus session result.
///
/// Layout (top → bottom):
///   1. Profile / mode name — white text inside a hairline rounded pill
///   2. Big duration — `H:MM` mono bold (or `M` when < 1h), the visual anchor
///   3. Units line — `小時 · 分鐘` (or `分鐘`) in smaller white text
///   4. DO logo — orange transparent asset, anchored near the bottom of the canvas
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

      // --- Fonts ---
      let nameFont = UIFont.systemFont(ofSize: 64, weight: .semibold)
      let numberFont: UIFont = {
        if let mono = UIFont(name: "SFMono-Bold", size: 380) { return mono }
        return UIFont.monospacedSystemFont(ofSize: 380, weight: .bold)
      }()
      let unitsFont = UIFont.systemFont(ofSize: 56, weight: .regular)

      // --- 1. Profile name in pill ---
      let nameAttrs: [NSAttributedString.Key: Any] = [
        .font: nameFont,
        .foregroundColor: white,
        .kern: 1.5,
      ]
      let nameStr = NSAttributedString(string: profileName, attributes: nameAttrs)
      let nameSize = nameStr.size()

      let pillHorizontalPadding: CGFloat = 56
      let pillVerticalPadding: CGFloat = 26
      let pillWidth = nameSize.width + pillHorizontalPadding * 2
      let pillHeight = nameSize.height + pillVerticalPadding * 2
      // Anchor the pill just above the number, so name → number → units form
      // one tight vertical cluster centred near the canvas middle.
      let pillToNumberGap: CGFloat = 80
      let numberY: CGFloat = 760
      let pillY: CGFloat = numberY - pillToNumberGap - pillHeight
      let pillRect = CGRect(
        x: (canvasWidth - pillWidth) / 2,
        y: pillY,
        width: pillWidth,
        height: pillHeight
      )

      let pillPath = UIBezierPath(
        roundedRect: pillRect,
        cornerRadius: pillHeight / 2
      )
      // Hairline white stroke at low opacity — looks like a subtle ring on transparent PNG
      cg.saveGState()
      cg.setStrokeColor(UIColor.white.withAlphaComponent(0.55).cgColor)
      cg.setLineWidth(3)
      cg.addPath(pillPath.cgPath)
      cg.strokePath()
      cg.restoreGState()

      let nameOrigin = CGPoint(
        x: pillRect.midX - nameSize.width / 2,
        y: pillRect.midY - nameSize.height / 2
      )
      nameStr.draw(at: nameOrigin)

      // --- 2. Big duration number ---
      let numberAttrs: [NSAttributedString.Key: Any] = [
        .font: numberFont,
        .foregroundColor: white,
      ]
      let numberStr = NSAttributedString(string: numberText, attributes: numberAttrs)
      let numberSize = numberStr.size()

      // numberY was defined above (used to anchor the pill).
      let numberOrigin = CGPoint(
        x: (canvasWidth - numberSize.width) / 2,
        y: numberY
      )
      numberStr.draw(at: numberOrigin)

      // --- 3. Units row ---
      let unitsAttrs: [NSAttributedString.Key: Any] = [
        .font: unitsFont,
        .foregroundColor: UIColor.white.withAlphaComponent(0.7),
        .kern: 6.0,
      ]
      let unitsStr = NSAttributedString(string: unitsText, attributes: unitsAttrs)
      let unitsSize = unitsStr.size()

      let unitsY = numberY + numberSize.height + 24
      let unitsOrigin = CGPoint(
        x: (canvasWidth - unitsSize.width) / 2,
        y: unitsY
      )
      unitsStr.draw(at: unitsOrigin)

      // --- 4. Logo near bottom ---
      let logoImage = UIImage(named: "DOLogo")
      let logoBottomMargin: CGFloat = 200
      if let img = logoImage, img.size.width > 0 {
        let targetWidth = canvasWidth * 0.18
        let scale = targetWidth / img.size.width
        let logoSize = CGSize(width: targetWidth, height: img.size.height * scale)
        let logoRect = CGRect(
          x: (canvasWidth - logoSize.width) / 2,
          y: canvasHeight - logoBottomMargin - logoSize.height,
          width: logoSize.width,
          height: logoSize.height
        )
        img.draw(in: logoRect)
      } else {
        let fallbackFont = UIFont.systemFont(ofSize: 80, weight: .bold)
        let fallback = NSAttributedString(
          string: "DO",
          attributes: [.font: fallbackFont, .foregroundColor: white]
        )
        let fSize = fallback.size()
        fallback.draw(at: CGPoint(
          x: (canvasWidth - fSize.width) / 2,
          y: canvasHeight - logoBottomMargin - fSize.height
        ))
      }
    }
  }
}
