import Foundation
import Security

/// Both the app and notification extension use the explicitly shared Keychain group.
enum AgentFocusPairingStore {
  enum Failure: Error { case keychain(OSStatus) }
  private static var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "online.do.card.agent",
      kSecAttrAccount as String: "docard-agent-pairing-v1",
      kSecAttrAccessGroup as String: KeychainHelper.sharedAccessGroup,
    ]
  }
  static func load() throws -> AgentFocusPairing {
    var attributes = query
    attributes[kSecReturnData as String] = true
    var result: CFTypeRef?
    let status = SecItemCopyMatching(attributes as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      throw Failure.keychain(status)
    }
    return try JSONDecoder().decode(AgentFocusPairing.self, from: data)
  }
  static func save(_ pairing: AgentFocusPairing) throws {
    let data = try JSONEncoder().encode(pairing)
    let status = SecItemUpdate(
      query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var attributes = query
      attributes[kSecValueData as String] = data
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      let result = SecItemAdd(attributes as CFDictionary, nil)
      guard result == errSecSuccess else { throw Failure.keychain(result) }
    } else if status != errSecSuccess {
      throw Failure.keychain(status)
    }
  }
}
