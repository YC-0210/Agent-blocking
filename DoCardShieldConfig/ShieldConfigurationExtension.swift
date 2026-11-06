import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The chosen Quiet design, composed using Apple's native shield fields.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
  override func configuration(shielding application: Application) -> ShieldConfiguration {
    quietConfiguration()
  }

  override func configuration(shielding application: Application, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    configuration(shielding: application)
  }

  override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
    quietConfiguration()
  }

  override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory)
    -> ShieldConfiguration
  {
    configuration(shielding: webDomain)
  }

  private func quietConfiguration() -> ShieldConfiguration {
    let ink = UIColor(red: 45 / 255, green: 40 / 255, blue: 31 / 255, alpha: 1)
    let paper = UIColor(red: 1, green: 245 / 255, blue: 230 / 255, alpha: 1)
    return ShieldConfiguration(
      backgroundBlurStyle: nil,
      backgroundColor: UIColor(red: 242 / 255, green: 91 / 255, blue: 54 / 255, alpha: 1),
      icon: nil,
      title: .init(text: copy("Go back to work."), color: ink),
      subtitle: nil,
      primaryButtonLabel: .init(
        text: copy("Close app"), color: paper),
      primaryButtonBackgroundColor: ink,
      secondaryButtonLabel: nil)
  }

  private func copy(_ key: String) -> String {
    #if DEBUG && DO_CARD_ENGLISH_DEMO
      guard let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
        let english = Bundle(path: path)
      else { return key }
      return english.localizedString(forKey: key, value: key, table: "AgentFocus")
    #else
      return Bundle.main.localizedString(forKey: key, value: key, table: "AgentFocus")
    #endif
  }
}
