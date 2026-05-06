import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG (1080×1920, 9:16) of the focus session result.
///
/// Per spec, the layout uses absolute Y-centre positions on the canvas:
///
///   Element   Centre Y    Font / size
///   --------  ----------  -------------------------------------------
///   Pill      762 (39.7%) SF Pro 44pt semibold, padding 20×44,
///                         fill rgba(255,255,255,0.06), stroke rgba(0.25)
///   Number    960 (50.0%) SF Pro Rounded 440pt bold, tabular-nums,
///                         letter-spacing -0.04em, line-height 0.9
///   Caption   1294 (67.4%) SF Pro 40pt medium, kern 16 (0.4em),
///                         colour rgba(255,255,255,0.5)
///   Logo      bottom-anchored 64pt above canvas bottom, height 96pt
///
/// Note: backdrop-blur from the spec is not modelled — PNG output is transparent
/// so there is nothing behind the pill to blur. The translucent fill alone
/// reads correctly when pasted onto an IG Story background.
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

      // --- Spec ---
      let nameFontSize: CGFloat = 44
      let numberFontSize: CGFloat = 440
      let captionFontSize: CGFloat = 40

      let pillCenterY: CGFloat = 762   // 39.7%
      let numberCenterY: CGFloat = 960  // 50.0% — canvas centre
      let captionCenterY: CGFloat = 1294  // 67.4%

      let logoTargetHeight: CGFloat = 96
      let logoBottomMargin: CGFloat = 64  // distance from canvas bottom

      let pillVerticalPadding: CGFloat = 20
      let pillHorizontalPadding: CGFloat = 44
      let pillFillColor = UIColor.white.withAlphaComponent(0.06)
      let pillStrokeColor = UIColor.white.withAlphaComponent(0.25)
      let pillStrokeWidth: CGFloat = 1

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
      // Pill name — SF Pro semibold (weight 600)
      let nameFont = UIFont.systemFont(ofSize: nameFontSize, weight: .semibold)

      // Main number — SF Pro Rounded bold (700) + tabular-nums + line-height 0.9
      // Tabular numbers via CoreText feature: kNumberSpacingType(6) / kMonospacedNumbersSelector(0).
      let numberFont: UIFont = {
        let base = UIFont.systemFont(ofSize: numberFontSize, weight: .bold)
        let roundedDescriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let tabularDescriptor = roundedDescriptor.addingAttributes([
          UIFontDescriptor.AttributeName.featureSettings: [
            [
              UIFontDescriptor.FeatureKey.type: 6,
              UIFontDescriptor.FeatureKey.selector: 0,
            ]
          ]
        ])
        return UIFont(descriptor: tabularDescriptor, size: numberFontSize)
      }()

      // Caption — SF Pro medium (500)
      let captionFont = UIFont.systemFont(ofSize: captionFontSize, weight: .medium)

      // --- Attributed strings ---
      // Number: letter-spacing -0.04em → kern -17.6pt on 440pt font.
      // line-height 0.9 → tight paragraph, but for a single-line draw-at-point
      // it has no effect on glyph metrics; documented for fidelity to spec.
      let numberParagraph = NSMutableParagraphStyle()
      numberParagraph.alignment = .center
      numberParagraph.lineHeightMultiple = 0.9
      let numberStr = NSAttributedString(string: numberText, attributes: [
        .font: numberFont,
        .foregroundColor: UIColor.white,
        .kern: -numberFontSize * 0.04,
        .paragraphStyle: numberParagraph,
      ])

      let nameStr = NSAttributedString(string: profileName, attributes: [
        .font: nameFont,
        .foregroundColor: UIColor.white,
      ])

      let captionStr = NSAttributedString(string: unitsText, attributes: [
        .font: captionFont,
        .foregroundColor: UIColor.white.withAlphaComponent(0.5),
        .kern: captionFontSize * 0.4,  // 0.4em letter-spacing
      ])

      let nameSize = nameStr.size()
      let numberSize = numberStr.size()
      let captionSize = captionStr.size()

      // --- 1. Pill (centre Y = 762) ---
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
      cg.setFillColor(pillFillColor.cgColor)
      cg.addPath(pillPath.cgPath)
      cg.fillPath()

      cg.setStrokeColor(pillStrokeColor.cgColor)
      cg.setLineWidth(pillStrokeWidth)
      cg.addPath(pillPath.cgPath)
      cg.strokePath()
      cg.restoreGState()

      let nameOrigin = CGPoint(
        x: pillRect.midX - nameSize.width / 2,
        y: pillRect.midY - nameSize.height / 2
      )
      nameStr.draw(at: nameOrigin)

      // --- 2. Number (centre Y = 960) ---
      let numberOrigin = CGPoint(
        x: (canvasWidth - numberSize.width) / 2,
        y: numberCenterY - numberSize.height / 2
      )
      numberStr.draw(at: numberOrigin)

      // --- 3. Caption (centre Y = 1294) ---
      let captionOrigin = CGPoint(
        x: (canvasWidth - captionSize.width) / 2,
        y: captionCenterY - captionSize.height / 2
      )
      captionStr.draw(at: captionOrigin)

      // --- 4. Logo (bottom-anchored 64pt above canvas bottom) ---
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
          attributes: [.font: fallbackFont, .foregroundColor: UIColor.white]
        )
        let fSize = fallback.size()
        fallback.draw(at: CGPoint(x: (canvasWidth - fSize.width) / 2, y: logoY))
      }
    }
  }
}
