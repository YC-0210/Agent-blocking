import OSLog
import UIKit

private let generatorLog = Logger(subsystem: "online.do.card.app", category: "FocusShareCardGenerator")

/// Renders a transparent-background PNG (1080×1920) showing the focus session result.
/// Layout (vertically centred group):
///   1. Profile / mode name — white, bold, wide tracking
///   2. Duration — two-cell `[H] 小時 · [M] 分鐘`, or single `[M] 分鐘` when < 1h
///   3. DO logo — orange transparent asset, near bottom of group
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

    return renderer.image { _ in
      let white = UIColor.white

      // --- 1. Profile name ---
      let nameFont = UIFont.systemFont(ofSize: 64, weight: .bold)
      let nameAttrs: [NSAttributedString.Key: Any] = [
        .font: nameFont,
        .foregroundColor: white,
        .kern: 2.0,
      ]
      let nameStr = NSAttributedString(string: profileName, attributes: nameAttrs)
      let nameSize = nameStr.size()

      // --- 2. Duration block ---
      let totalSeconds = Int(max(0, duration))
      let hours = totalSeconds / 3600
      let minutes = (totalSeconds % 3600) / 60

      let numberFont: UIFont = {
        if let mono = UIFont(name: "SFMono-Bold", size: 280) { return mono }
        return UIFont.monospacedSystemFont(ofSize: 280, weight: .bold)
      }()
      let unitFont = UIFont.systemFont(ofSize: 56, weight: .semibold)
      let dotFont = UIFont.systemFont(ofSize: 200, weight: .bold)

      let numberAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: white]
      let unitAttrs: [NSAttributedString.Key: Any] = [.font: unitFont, .foregroundColor: white, .kern: 2.0]
      let dotAttrs: [NSAttributedString.Key: Any] = [.font: dotFont, .foregroundColor: white]

      // Pre-measure cells
      struct DurationCell {
        let number: NSAttributedString
        let unit: NSAttributedString
        let numberSize: CGSize
        let unitSize: CGSize
        var width: CGFloat { max(numberSize.width, unitSize.width) }
        var height: CGFloat { numberSize.height + 12 + unitSize.height }
      }

      func makeCell(number: Int, unit: String) -> DurationCell {
        let numberStr = NSAttributedString(string: "\(number)", attributes: numberAttrs)
        let unitStr = NSAttributedString(string: unit, attributes: unitAttrs)
        return DurationCell(
          number: numberStr,
          unit: unitStr,
          numberSize: numberStr.size(),
          unitSize: unitStr.size()
        )
      }

      let cells: [DurationCell]
      let dotStr: NSAttributedString?
      let dotSize: CGSize
      let cellSpacing: CGFloat = 60  // gap between cell ↔ dot ↔ cell

      if hours >= 1 {
        cells = [
          makeCell(number: hours, unit: String(localized: "小時")),
          makeCell(number: minutes, unit: String(localized: "分鐘")),
        ]
        dotStr = NSAttributedString(string: "·", attributes: dotAttrs)
        dotSize = dotStr!.size()
      } else {
        cells = [makeCell(number: minutes, unit: String(localized: "分鐘"))]
        dotStr = nil
        dotSize = .zero
      }

      let durationBlockHeight = cells.map(\.height).max() ?? 0
      let durationBlockWidth: CGFloat = {
        let cellsWidth = cells.map(\.width).reduce(0, +)
        let dotWidth = dotStr != nil ? dotSize.width + cellSpacing * 2 : 0
        return cellsWidth + dotWidth
      }()

      // --- 3. Logo ---
      let logoImage = UIImage(named: "DOLogo")
      let logoSize: CGSize
      if let img = logoImage, img.size.width > 0 {
        let targetWidth = canvasWidth * 0.22
        let scale = targetWidth / img.size.width
        logoSize = CGSize(width: targetWidth, height: img.size.height * scale)
      } else {
        logoSize = CGSize(width: 200, height: 80)
      }

      // --- Vertical layout: name → duration → logo ---
      let groupSpacing: CGFloat = 100
      let totalGroupHeight = nameSize.height + groupSpacing + durationBlockHeight + groupSpacing + logoSize.height
      let startY = (canvasHeight - totalGroupHeight) / 2

      // Draw profile name
      let nameOrigin = CGPoint(x: (canvasWidth - nameSize.width) / 2, y: startY)
      nameStr.draw(at: nameOrigin)

      // Draw duration block
      let durationY = startY + nameSize.height + groupSpacing
      var cursorX = (canvasWidth - durationBlockWidth) / 2
      for (idx, cell) in cells.enumerated() {
        // Number
        let numberOrigin = CGPoint(
          x: cursorX + (cell.width - cell.numberSize.width) / 2,
          y: durationY
        )
        cell.number.draw(at: numberOrigin)

        // Unit (under number)
        let unitOrigin = CGPoint(
          x: cursorX + (cell.width - cell.unitSize.width) / 2,
          y: durationY + cell.numberSize.height + 12
        )
        cell.unit.draw(at: unitOrigin)

        cursorX += cell.width

        // Dot separator (only between two cells)
        if idx == 0, let dotStr {
          cursorX += cellSpacing
          let dotOrigin = CGPoint(
            x: cursorX,
            // align dot with number row, slight optical adjustment
            y: durationY + (cell.numberSize.height - dotSize.height) / 2 - 20
          )
          dotStr.draw(at: dotOrigin)
          cursorX += dotSize.width + cellSpacing
        }
      }

      // Draw logo
      let logoY = startY + nameSize.height + groupSpacing + durationBlockHeight + groupSpacing
      if let img = logoImage {
        let logoRect = CGRect(
          x: (canvasWidth - logoSize.width) / 2,
          y: logoY,
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
        fallback.draw(at: CGPoint(x: (canvasWidth - fSize.width) / 2, y: logoY))
      }
    }
  }
}
