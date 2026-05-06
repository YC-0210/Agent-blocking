import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG (1080×1920) of the focus session result.
///
/// Layout per designer spec — block centred horizontally, biased toward upper half
/// of the canvas with empty whitespace below the logo.
///
///   Element   Box top   Box bottom   Notes
///   --------  --------  -----------  -------------------------------------------
///   Pill      388       472          (h 84) fill rgba(0.06), stroke 1px 0.25
///   Number    528       924          (h 396 = 440×0.9) cap-aligned to box top
///   Caption   940       980          (h 40) Chinese text, drawn at typographic top
///   Logo      1036      1132         (h 96) box-aligned, stays in upper-mid canvas
///
/// Visual gaps (box-edge to box-edge): pill→number 56, number→caption 16,
/// caption→logo 56. The number uses cap-aligned drawing because SF Pro's natural
/// ascent leaves ~25% leading above the cap that would otherwise push the visible
/// glyph far below the spec box top.
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

      // --- Spec: absolute box bounds ---
      let pillTop: CGFloat = 388
      let pillHeight: CGFloat = 84

      let numberBoxTop: CGFloat = 528  // cap-align target for visible glyph top
      let captionBoxTop: CGFloat = 940  // typographic top (Chinese text)

      let logoTop: CGFloat = 1036
      let logoHeight: CGFloat = 96

      // Pill style
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

      // Main number: SF Pro Rounded bold + tabular-nums (CoreText feature 6/0)
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

      let numberStr = NSAttributedString(string: numberText, attributes: [
        .font: numberFont,
        .foregroundColor: UIColor.white,
        .kern: -numberFontSize * 0.04,  // -17.6pt for -0.04em
      ])

      let captionStr = NSAttributedString(string: unitsText, attributes: [
        .font: captionFont,
        .foregroundColor: UIColor.white.withAlphaComponent(0.5),
        .kern: captionFontSize * 0.4,  // 16pt for 0.4em
      ])

      let nameSize = nameStr.size()
      let numberSize = numberStr.size()
      let captionSize = captionStr.size()

      // --- 1. Pill (absolute box 388–472) ---
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

      let nameOrigin = CGPoint(
        x: pillRect.midX - nameSize.width / 2,
        y: pillRect.midY - nameSize.height / 2
      )
      nameStr.draw(at: nameOrigin)

      // --- 2. Number (cap-aligned: visible glyph top at numberBoxTop) ---
      // SF Pro Rounded reserves ~(ascender - capHeight) of leading above the cap;
      // subtract that so the visible "3", "1", etc. start exactly at y=528.
      let numberLeadingTop = numberFont.ascender - numberFont.capHeight
      let numberDrawY = numberBoxTop - numberLeadingTop
      let numberOrigin = CGPoint(
        x: (canvasWidth - numberSize.width) / 2,
        y: numberDrawY
      )
      numberStr.draw(at: numberOrigin)

      // --- 3. Caption (Chinese text drawn at typographic top y=940) ---
      // Chinese glyphs sit close to the ascender line, so literal draw matches the
      // box top closely without cap-align tricks.
      let captionOrigin = CGPoint(
        x: (canvasWidth - captionSize.width) / 2,
        y: captionBoxTop
      )
      captionStr.draw(at: captionOrigin)

      // --- 4. Logo (absolute box 1036–1132) ---
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
