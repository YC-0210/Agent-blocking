import ManagedSettings
import ManagedSettingsUI
import UIKit

/// iOS owns shield composition. Match Bold's material and copy within that native layout.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    configuration(for: application.localizedDisplayName ?? String(localized: "This app"))
  }

  override func configuration(shielding application: Application, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    configuration(shielding: application)
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    configuration(for: webDomain.domain ?? String(localized: "This website"))
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    configuration(shielding: webDomain)
  }

  private func configuration(for name: String) -> ShieldConfiguration {
    let ink = UIColor(red: 45 / 255, green: 40 / 255, blue: 31 / 255, alpha: 1)
    let paper = UIColor(red: 1, green: 245 / 255, blue: 230 / 255, alpha: 1)
    let icon = UIImage(
      systemName: "arrow.up.right",
      withConfiguration:
        UIImage.SymbolConfiguration(pointSize: 52, weight: .bold))?
      .withTintColor(ink, renderingMode: .alwaysOriginal)
    return ShieldConfiguration(
      backgroundBlurStyle: .light,
      backgroundColor: UIColor(red: 242 / 255, green: 91 / 255, blue: 54 / 255, alpha: 1),
      icon: icon,
      title: .init(text: String(localized: "NOT RIGHT NOW."), color: ink),
      subtitle: .init(
        text: String(format: String(localized: "%@ can wait. You chose this time to focus."), name)
          + "\n\n"
          + String(localized: "Need to end the session? Open DO Card for Emergency Unlock."),
        color: ink),
      primaryButtonLabel: .init(text: String(localized: "Back to what matters"), color: paper),
      primaryButtonBackgroundColor: ink,
      secondaryButtonLabel: nil)
  }
}
