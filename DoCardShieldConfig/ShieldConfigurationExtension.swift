//
//  ShieldConfigurationExtension.swift
//  DoCardShieldConfig
//
//  Created by Ali Waseem on 2025-08-11.
//

import ManagedSettings
import ManagedSettingsUI
import SwiftUI
import UIKit

// Override the functions below to customize the shields used in various situations.
// The system provides a default appearance for any methods that your subclass doesn't override.
// Make sure that your class name matches the NSExtensionPrincipalClass in your Info.plist.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    return createCustomShieldConfiguration(
      for: .app, title: application.localizedDisplayName ?? String(localized: "App"))
  }

  override func configuration(shielding application: Application, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    return createCustomShieldConfiguration(
      for: .app, title: application.localizedDisplayName ?? String(localized: "App"))
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    return createCustomShieldConfiguration(for: .website, title: webDomain.domain ?? String(localized: "Website"))
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    return createCustomShieldConfiguration(for: .website, title: webDomain.domain ?? String(localized: "Website"))
  }

  private func createCustomShieldConfiguration(for type: BlockedContentType, title: String)
    -> ShieldConfiguration
  {
    // Use user's selected theme color for the button
    let brandColor = UIColor(ThemeManager.shared.themeColor)

    // Get random fun message
    let randomMessage = getFunBlockMessage(for: type, title: title)

    // TODO: Once DOLogoShield.png (transparent-background) is added to
    // DoCardShieldConfig/Assets.xcassets/DOLogoShield.imageset/, switch to makeDOLogoIcon().
    // Until then, the emoji icon is used as a fallback.
    let icon = makeDOLogoIcon() ?? makeEmojiIcon(randomMessage.emoji, size: 96)

    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: .black,
      icon: icon,
      title: ShieldConfiguration.Label(
        text: randomMessage.title,
        color: .white
      ),
      subtitle: ShieldConfiguration.Label(
        text: randomMessage.subtitle,
        color: UIColor.white.withAlphaComponent(0.88)
      ),
      primaryButtonLabel: ShieldConfiguration.Label(
        text: randomMessage.buttonText,
        color: .white
      ),
      primaryButtonBackgroundColor: brandColor,
      secondaryButtonLabel: nil
    )
  }

  private func getFunBlockMessage(for _: BlockedContentType, title: String) -> (
    emoji: String, title: String, subtitle: String, buttonText: String
  ) {
    typealias FunMessage = (emoji: String, title: String, subtitle: String, buttonText: String)

    // Curated message "bundles" where the emoji and copy are designed to match.
    // This keeps things fun without feeling chaotic or mismatched.
    // Using String(localized:) for all user-facing text to support localization.
    let messages: [FunMessage] = [
      ("📵", String(localized: "認真的？"), String(localized: "做完再說。"), String(localized: "好啦好啦")),
      ("🧠", String(localized: "先做完"), String(format: String(localized: "%@ 哪都不會去。"), title), String(localized: "好")),
      (
        "🎯", String(localized: "你自己設的"), String(localized: "還記得當時的承諾嗎？"),
        String(localized: "記得")
      ),
      (
        "⏳", String(localized: "不行喔"), String(localized: "現在不行。先把事做完。"),
        String(localized: "好吧")
      ),
      ("🛡️", String(localized: "快了"), String(localized: "再一下下，你做得到。"), String(localized: "繼續")),
      ("🔒", String(localized: "撐一下"), String(localized: "快到了"), String(localized: "好啦")),
      ("🧱", String(localized: "被抓到了"), String(localized: "沒事，回去吧。"), String(localized: "回去")),
      ("✨", String(localized: "嘿"), String(localized: "這不在你的計畫裡。"), String(localized: "好好")),
      ("🫶", String(localized: "還沒"), String(localized: "做完再用，想用多久都行。"), String(localized: "好啦好啦")),
      (
        "🌐", String(localized: "去做你的事"), String(format: String(localized: "%@ 在這裡等你。"), title),
        String(localized: "好")
      ),
      (
        "🕸️", String(localized: "喂！"), String(localized: "你自己設定的欸，別搞"),
        String(localized: "我知道")
      ),
      ("🛡️", String(localized: "快到了"), String(localized: "撐著，快完成了。"), String(localized: "繼續")),
      ("🔒", String(localized: "現在嗎？"), String(localized: "要確定欸？"), String(localized: "好好")),
      (
        "🎯", String(localized: "你說的"), String(localized: "「做就對了」——你說的話。"),
        String(localized: "對對對")
      ),
      (
        "⏳", String(localized: "放著"), String(localized: "先把這件事做完。"),
        String(localized: "好啦好啦")
      ),
      ("📵", String(localized: "等一下"), String(localized: "快到了，再久一點點。"), String(localized: "好啦")),
      ("✨", String(localized: "急什麼"), String(localized: "先做完正事，再回來。"), String(localized: "好吧")),
    ]
    guard !messages.isEmpty else { return ("🧠", String(localized: "認真的？"), String(localized: "現在不行。"), String(localized: "好啦好啦")) }

    let comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    let dayKey =
      (comps.year ?? 0) * 10_000
      + (comps.month ?? 0) * 100
      + (comps.day ?? 0)

    let seed = Int(stableSeed(for: title) % UInt64(Int.max)) ^ dayKey
    let idx = abs(seed) % messages.count

    return messages[idx]
  }

  private func stableSeed(for title: String) -> UInt64 {
    // FNV-1a 64-bit over unicode scalars (deterministic across runs/devices).
    var hash: UInt64 = 14_695_981_039_346_656_037
    for scalar in title.unicodeScalars {
      hash ^= UInt64(scalar.value)
      hash &*= 1_099_511_628_211
    }
    return hash
  }

  /// Loads the DO logo from the shield extension's own asset catalog and resizes to 96×96 pt.
  /// Returns nil if the asset hasn't been added yet, so callers can fall back to the emoji icon.
  private func makeDOLogoIcon() -> UIImage? {
    guard let logo = UIImage(named: "DOLogoShield", in: Bundle.main, compatibleWith: nil) else {
      return nil
    }
    let size: CGFloat = 96
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { _ in
      logo.draw(in: CGRect(x: 0, y: 0, width: size, height: size))
    }
  }

  private func makeEmojiIcon(_ emoji: String, size: CGFloat) -> UIImage? {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size))
    return renderer.image { _ in
      let paragraph = NSMutableParagraphStyle()
      paragraph.alignment = .center

      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: size * 0.78),
        .paragraphStyle: paragraph,
      ]

      let rect = CGRect(x: 0, y: 0, width: size, height: size)
      let attributed = NSAttributedString(string: emoji, attributes: attributes)
      let bounds = attributed.boundingRect(
        with: rect.size,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        context: nil
      )

      // Vertically center emoji
      let drawRect = CGRect(
        x: rect.minX,
        y: rect.minY + (rect.height - bounds.height) / 2,
        width: rect.width,
        height: bounds.height
      )
      attributed.draw(in: drawRect)
    }
  }
}

enum BlockedContentType {
  case app
  case website
}
