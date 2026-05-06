import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG (1080×1920) of the focus session result.
///
/// Layout — absolute spec on the 1080×1920 canvas (each element positioned by its
/// own Y centre, not as a flex-centred group):
///
///   Element   X centre   Y centre        Height     Font
///   --------  --------   -------------   --------   -----
///   Pill      50%        45.0% (864)     4.4% pill  44pt name
///   Number    50%        60.4% (1160)    20.6%      440pt mono bold
///   Caption   50%        72.6% (1394)    2.1%       40pt, kern 16 (0.4em)
///   Logo      50%        anchored 64pt   5.0%       — (asset)
///                        from bottom
///   Implied gaps: pill→number 56pt, number→caption 16pt
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

      // --- Spec: font sizes (1080×1920 absolute) ---
      let nameFontSize: CGFloat = 44
      let numberFontSize: CGFloat = 440
      let captionFontSize: CGFloat = 40

      // --- Spec: Y centres (% of canvas height) ---
      let pillCenterY: CGFloat = canvasHeight * 0.450
      let numberCenterY: CGFloat = canvasHeight * 0.604
      let captionCenterY: CGFloat = canvasHeight * 0.726

      // --- Spec: logo ---
      let logoTargetHeight: CGFloat = 96  // 5.0% of 1920
      let logoBottomMargin: CGFloat = 64  // 3.33% of 1920

      // --- Pill padding (proportional to name font) ---
      let pillVerticalPadding: CGFloat = 16
      let pillHorizontalPadding: CGFloat = 44
      let pillStrokeWidth: CGFloat = 3

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
        .kern: 16.0,  // 0.4em × 40pt
      ])

      let nameSize = nameStr.size()
      let numberSize = numberStr.size()
      let captionSize = captionStr.size()

      // --- 1. Profile-name pill (centred at pillCenterY) ---
      let pillW = nameSize.width + pillHorizontalPadding * 2
      let pillH = nameSize.height + pillVerticalPadding * 2
      let pillRect = CGRect(
        x: (canvasWidth - pillW) / 2,
        y: pillCenterY - pillH / 2,
        width: pillW,
        height: pillH
      )
      let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillH / 2)
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

      // --- 2. Number (centred at numberCenterY) ---
      let numberOrigin = CGPoint(
        x: (canvasWidth - numberSize.width) / 2,
        y: numberCenterY - numberSize.height / 2
      )
      numberStr.draw(at: numberOrigin)

      // --- 3. Caption (centred at captionCenterY) ---
      let captionOrigin = CGPoint(
        x: (canvasWidth - captionSize.width) / 2,
        y: captionCenterY - captionSize.height / 2
      )
      captionStr.draw(at: captionOrigin)

      // --- 4. Logo (anchored 64pt from bottom edge) ---
      let logoImage = UIImage(named: "DOLogo")
      let logoSize: CGSize = {
        if let img = logoImage, img.size.width > 0 {
          let scale = logoTargetHeight / img.size.height
          return CGSize(width: img.size.width * scale, height: logoTargetHeight)
        }
        return CGSize(width: 200, height: logoTargetHeight)
      }()
      let logoY = canvasHeight - logoBottomMargin - logoSize.height
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
