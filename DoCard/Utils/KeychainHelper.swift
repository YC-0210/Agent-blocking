import Foundation
import OSLog
import Security

private let kcLogger = Logger(subsystem: "app.docard", category: "Keychain")

/// A lightweight Keychain wrapper for storing security-critical values
/// that must resist tampering via backup restoration or jailbreak.
///
/// Used for emergency unlock counters, reset timestamps, and other
/// values that enforce the app's core security promise.
struct KeychainHelper {

  private static let serviceName = "com.do-app.security"

  // MARK: - Int Storage

  static func save(_ key: String, value: Int) {
    let data = withUnsafeBytes(of: value) { Data($0) }
    save(key: key, data: data)
  }

  static func load(_ key: String, defaultValue: Int) -> Int {
    guard let data = load(key: key), data.count == MemoryLayout<Int>.size else {
      return defaultValue
    }
    return data.withUnsafeBytes { $0.load(as: Int.self) }
  }

  // MARK: - Double Storage

  static func save(_ key: String, value: Double) {
    let data = withUnsafeBytes(of: value) { Data($0) }
    save(key: key, data: data)
  }

  static func load(_ key: String, defaultValue: Double) -> Double {
    guard let data = load(key: key), data.count == MemoryLayout<Double>.size else {
      return defaultValue
    }
    return data.withUnsafeBytes { $0.load(as: Double.self) }
  }

  // MARK: - Raw Data Storage

  static func save(_ key: String, value: Data) {
    save(key: key, data: value)
  }

  static func loadData(_ key: String) -> Data? {
    return load(key: key)
  }

  // MARK: - Delete

  static func delete(_ key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
  }

  // MARK: - Private Helpers

  private static func save(key: String, data: Data) {
    // First try to update existing item
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
    ]

    let attributes: [String: Any] = [
      kSecValueData as String: data,
    ]

    let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

    if updateStatus == errSecItemNotFound {
      // Item doesn't exist yet — add it
      var newItem = query
      newItem[kSecValueData as String] = data
      // Only accessible when the device is unlocked, never migrates to other devices
      newItem[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

      let addStatus = SecItemAdd(newItem as CFDictionary, nil)
      if addStatus != errSecSuccess {
        kcLogger.error("Failed to save key '\(key, privacy: .public)', status: \(addStatus, privacy: .public)")
      }
    } else if updateStatus != errSecSuccess {
      kcLogger.error("Failed to update key '\(key, privacy: .public)', status: \(updateStatus, privacy: .public)")
    }
  }

  private static func load(key: String) -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: serviceName,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }

    return data
  }
}
