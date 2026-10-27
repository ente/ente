import Foundation
import Security

struct NotificationRecipient: Codable {
  let schemaVersion: Int
  let privateKey: String

  var isValid: Bool {
    schemaVersion == 1 && Data(base64Encoded: privateKey)?.count == 32
  }
}

enum NotificationKeyStore {
  static let accessGroup = "group.io.ente.frame.NotificationServiceExtension"
  static let service = "io.ente.frame.notifications"
  #if DEBUG
  static let account = "recipient.debug"
  #else
  static let account = "recipient"
  #endif

  enum StoreError: Error {
    case keychain(OSStatus)
    case invalidRecord
    case unsupportedVersion
  }

  static var preferences: UserDefaults { UserDefaults(suiteName: accessGroup)! }
  private static var resetPendingKey: String { "\(account).resetPending" }
  private static var preparedKey: String { "flutter.\(account).notificationKeyPrepared" }

  private static var query: [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccessGroup as String: accessGroup,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecAttrSynchronizable as String: false]
  }

  static func read() throws -> NotificationRecipient? {
    guard !preferences.bool(forKey: resetPendingKey) else { return nil }
    var query = query
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw StoreError.keychain(status) }
    guard let data = result as? Data else { throw StoreError.invalidRecord }
    let record = try JSONDecoder().decode(NotificationRecipient.self, from: data)
    guard record.schemaVersion == 1 else { throw StoreError.unsupportedVersion }
    guard record.isValid else { throw StoreError.invalidRecord }
    return record
  }

  static func readForPreparation() throws -> NotificationRecipient? {
    if preferences.bool(forKey: resetPendingKey) || !UserDefaults.standard.bool(forKey: preparedKey) {
      try clear()
    }
    do {
      return try read()
    } catch StoreError.invalidRecord {
      return nil
    } catch is DecodingError {
      return nil
    }
  }

  static func write(privateKey: String) throws {
    let record = NotificationRecipient(schemaVersion: 1, privateKey: privateKey)
    guard record.isValid else { throw StoreError.invalidRecord }
    _ = try readForPreparation()
    let data = try JSONEncoder().encode(record)
    var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var attributes = query
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      attributes[kSecValueData as String] = data
      status = SecItemAdd(attributes as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw StoreError.keychain(status) }
    UserDefaults.standard.set(true, forKey: preparedKey)
  }

  static func clear() throws {
    UserDefaults.standard.removeObject(forKey: preparedKey)
    preferences.set(true, forKey: resetPendingKey)
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw StoreError.keychain(status)
    }
    preferences.removeObject(forKey: resetPendingKey)
  }
}
