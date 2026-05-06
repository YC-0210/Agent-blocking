import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG (1080×1920) of the focus session result.
///
/// Layout uses absolute box bounds per the designer spec — each element is positioned
/// at its declared top-Y rather than via gap math, so font-metric variation cannot
/// shift the layout.
///
///   Element   Box top   Box bottom   Notes
///   --------  --------  -----------  --------------------------------------
///   Pill      496       584          (88 high) fill rgba(0.06), stroke 1px
///   Number    580       1020         440pt SF Pro Rounded bold, tabular,
///                                    kern -17.6 (-0.04em), line-height 1.0
///   Caption   1040      1080         40pt medium, kern 16 (0.4em), 50% white
///   Logo      1760      1856         (96 high) bottom-anchored at canvas-64
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

      // --- Spec: font sizes ---
      let nameFontSize: CGFloat = 44
      let numberFontSize: CGFloat = 440
      let captionFontSize: CGFloat = 40

      // --- Spec: absolute box bounds (canvas-Y) ---
      let pillTop: CGFloat = 496
      let pillHeight: CGFloat = 88

      let numberTop: CGFloat = 580

      let captionTop: CGFloat = 1040

      let logoTop: CGFloat = 1760
      let logoHeight: CGFloat = 96

      // Pill padding/style
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
      let nameFont = UIFont.systemFont(ofSize: nameFontSize, weight: .semibold)

      // Main number — SF Pro Rounded bold + tabular-nums (CoreText feature 6/0)
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

      let captionFont = UIFont.systemFont(ofSize: captionFontSize, weight: .medium)

      // --- Attributed strings ---
      let nameStr = NSAttributedString(string: profileName, attributes: [
        .font: nameFont,
        .foregroundColor: UIColor.white,
      ])

      let numberParagraph = NSMutableParagraphStyle()
      numberParagraph.lineHeightMultiple = 1.0
      let numberStr = NSAttributedString(string: numberText, attributes: [
        .font: numberFont,
        .foregroundColor: UIColor.white,
        .kern: -numberFontSize * 0.04,  // -17.6pt for -0.04em
        .paragraphStyle: numberParagraph,
      ])

      let captionStr = NSAttributedString(string: unitsText, attributes: [
        .font: captionFont,
        .foregroundColor: UIColor.white.withAlphaComponent(0.5),
        .kern: captionFontSize * 0.4,  // 16pt for 0.4em
      ])

      let nameSize = nameStr.size()
      let numberSize = numberStr.size()
      let captionSize = captionStr.size()

      // --- 1. Pill (absolute box 496–584) ---
      let pillW = nameSize.width + pillHorizontalPadding * 2
      let pillRect = CGRect(
        x: (canvasWidth - pillW) / 2,
        y: pillTop,
        width: pillW,
        height: pillHeight
      )
      let pillPath = UIBezierPath(roundedRect: pillRect, cornerRadius: pillHeight / 2)

      cg.saveGState()
      cg.setFillColor(pillFillColor.cgColor)
      cg.addPath(pillPath.cgPath)
      cg.fillPath()

      cg.setStrokeColor(pillStrokeColor.cgColor)
      cg.setLineWidth(pillStrokeWidth)
      cg.addPath(pillPath.cgPath)
      cg.strokePath()
      cg.restoreGState()

      // Centre the pill name inside the rect
      let nameOrigin = CGPoint(
        x: pillRect.midX - nameSize.width / 2,
        y: pillRect.midY - nameSize.height / 2
      )
      nameStr.draw(at: nameOrigin)

      // --- 2. Number (typographic top at y=580 per spec) ---
      let numberOrigin = CGPoint(
        x: (canvasWidth - numberSize.width) / 2,
        y: numberTop
      )
      numberStr.draw(at: numberOrigin)

      // --- 3. Caption (typographic top at y=1040 per spec) ---
      let captionOrigin = CGPoint(
        x: (canvasWidth - captionSize.width) / 2,
        y: captionTop
      )
      captionStr.draw(at: captionOrigin)

      // --- 4. Logo (absolute box 1760–1856) ---
      let logoImage = UIImage(named: "DOLogo")
      let logoSize: CGSize = {
        if let img = logoImage, img.size.width > 0 {
          let scale = logoHeight / img.size.height
          return CGSize(width: img.size.width * scale, height: logoHeight)
        }
        return CGSize(width: 200, height: logoHeight)
      }()
      if let img = logoImage {
        let logoRect = CGRect(
          x: (canvasWidth - logoSize.width) / 2,
          y: logoTop,
          width: logoSize.width,
          height: logoSize.height
        )
        img.draw(in: logoRect)
      } else {
        let fallbackFont = UIFont.systemFont(ofSize: logoHeight, weight: .bold)
        let fallback = NSAttributedString(
          string: "DO",
          attributes: [.font: fallbackFont, .foregroundColor: UIColor.white]
        )
        let fSize = fallback.size()
        fallback.draw(at: CGPoint(x: (canvasWidth - fSize.width) / 2, y: logoTop))
      }
    }
  }
}
