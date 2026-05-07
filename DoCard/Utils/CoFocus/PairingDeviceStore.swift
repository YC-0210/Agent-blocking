import Combine
import Foundation

/// App Group UserDefaults wrapper for co-focus local-only state.
/// Spec section 9: device_id is replaced by Supabase Anonymous Auth uid;
/// only the user's own nickname and the per-partner display-name overrides
/// live on-device.
@MainActor
final class PairingDeviceStore: ObservableObject {
  static let shared = PairingDeviceStore()

  private static let suiteName = "group.DO.version3"
  private static let myNicknameKey = "focusPairing_myNickname"
  private static let partnerNicknamesKey = "focusPairing_partnerNicknames"

  private let defaults: UserDefaults

  @Published private(set) var myNickname: String?

  private init() {
    self.defaults = UserDefaults(suiteName: Self.suiteName)!
    self.myNickname = defaults.string(forKey: Self.myNicknameKey)
  }

  // MARK: - Self nickname

  /// Persists the user's display name. Trimmed; rejects empty / >40 chars.
  /// Returns the normalized stored value, or nil if the input was rejected.
  @discardableResult
  func setMyNickname(_ nickname: String) -> String? {
    let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.count <= 40 else { return nil }
    defaults.set(trimmed, forKey: Self.myNicknameKey)
    self.myNickname = trimmed
    return trimmed
  }

  var hasMyNickname: Bool {
    guard let value = myNickname else { return false }
    return !value.isEmpty
  }

  // MARK: - Partner nickname overrides

  /// User's local override for a partner's display name, falling back to the
  /// partner's broadcast nickname when no override exists.
  func displayName(forPartner partnerUserId: UUID, defaultNickname: String) -> String {
    let map = readPartnerMap()
    return map[partnerUserId.uuidString] ?? defaultNickname
  }

  /// Sets (or clears, if empty) the local override for a partner's display name.
  func setPartnerNickname(_ nickname: String, for partnerUserId: UUID) {
    var map = readPartnerMap()
    let trimmed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      map.removeValue(forKey: partnerUserId.uuidString)
    } else {
      let bounded = String(trimmed.prefix(40))
      map[partnerUserId.uuidString] = bounded
    }
    defaults.set(map, forKey: Self.partnerNicknamesKey)
  }

  private func readPartnerMap() -> [String: String] {
    (defaults.dictionary(forKey: Self.partnerNicknamesKey) as? [String: String]) ?? [:]
  }
}
