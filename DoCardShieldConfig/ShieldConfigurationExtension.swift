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

    // Emoji "icon" (rendered to an image so it works with ShieldConfiguration.icon)
    let emojiIcon = makeEmojiIcon(randomMessage.emoji, size: 96)

    return ShieldConfiguration(
      backgroundBlurStyle: .dark,
      backgroundColor: .black,
      icon: emojiIcon,
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
      ("📵", String(localized: "Not right now"), String(format: String(localized: "%@ can wait. You're choosing your time on purpose."), title), String(localized: "Back")),
      ("🧠", String(localized: "Brain check"), String(format: String(localized: "Do you actually want %@… or was it autopilot?"), title), String(localized: "Return")),
      (
        "🎯", String(localized: "Stay on target"), String(format: String(localized: "One small step toward your goal first. Then decide on %@."), title),
        String(localized: "Continue")
      ),
      (
        "⏳", String(localized: "Give it 2 minutes"), String(format: String(localized: "Finish the next tiny thing. %@ will still be there after."), title),
        String(localized: "Keep going")
      ),
      ("🛡️", String(localized: "Shield up"), String(localized: "Focus is protected. You've got this."), String(localized: "Onward")),
      ("🔒", String(localized: "Locked in"), String(localized: "This block is temporary. Your momentum isn't."), String(localized: "Stay here")),
      ("🧱", String(localized: "Boundary set"), String(localized: "You made a plan. This is you sticking to it."), String(localized: "Back")),
      ("✨", String(localized: "Glow mode"), String(localized: "You're building attention — that's the real flex."), String(localized: "Nice")),
      ("🫶", String(localized: "Be kind to you"), String(localized: "No shame. Just a gentle nudge back to what matters."), String(localized: "Got it")),
      (
        "🌐", String(localized: "Not this detour"), String(format: String(localized: "%@ isn't part of the mission right now."), title), String(localized: "Return")
      ),
      (
        "🕸️", String(localized: "Avoid the trap"), String(localized: "One click turns into twenty. Let's not."), String(localized: "Back")
      ),
      ("🛡️", String(localized: "Protected zone"), String(localized: "We're keeping your attention where you wanted it."), String(localized: "Got it")),
      ("🔒", String(localized: "Locked in"), String(localized: "This is a temporary block for a long-term win."), String(localized: "Return")),
      (
        "🎯", String(localized: "Back to the task"), String(localized: "Close the detour. Finish the task. Then come back on purpose."),
        String(localized: "Back to work")
      ),
      (
        "⏳", String(localized: "Protect the time"), String(localized: "A few minutes can become an hour. Keep your momentum."),
        String(localized: "Stay focused")
      ),
      ("📵", String(localized: "Not missing anything"), String(localized: "You're not missing anything important right now."), String(localized: "Back")),
      ("✨", String(localized: "Momentum mode"), String(localized: "Tiny choices like this add up fast."), String(localized: "Continue")),
    ]
    guard !messages.isEmpty else { return ("🧠", String(localized: "Quick pause"), String(localized: "Not right now."), String(localized: "Back")) }

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
