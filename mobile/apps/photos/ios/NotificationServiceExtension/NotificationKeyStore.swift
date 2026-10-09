import Foundation
import Security

struct NotificationRecipient: Codable {
  let schemaVersion: Int
  let privateKey: String

  var isValid: Bool {
    schemaVersion == 1 && Data(base64Encoded: privateKey)?.count == 32
  }

  var publicKey: String? {
    guard let privateKey = Data(base64Encoded: privateKey), privateKey.count == 32,
      sodium_init() >= 0 else { return nil }
    var publicKey = [UInt8](repeating: 0, count: 32)
    guard crypto_scalarmult_base(&publicKey, Array(privateKey)) == 0 else { return nil }
    return Data(publicKey).base64EncodedString()
  }

  static func generate() throws -> Self {
    guard sodium_init() >= 0 else { throw NotificationKeyStore.StoreError.invalidRecord }
    var publicKey = [UInt8](repeating: 0, count: 32)
    var privateKey = [UInt8](repeating: 0, count: 32)
    guard crypto_box_keypair(&publicKey, &privateKey) == 0 else {
      throw NotificationKeyStore.StoreError.invalidRecord
    }
    return Self(schemaVersion: 1, privateKey: Data(privateKey).base64EncodedString())
  }
}

enum NotificationKeyStore {
  static let accessGroup = "group.io.ente.frame.notifications"
  static let service = "io.ente.frame.notifications"
  #if DEBUG
  static let account = "recipient.debug"
  static let preferenceKey = "notifications_enabled_shared_photos.debug"
  #else
  static let account = "recipient"
  static let preferenceKey = "notifications_enabled_shared_photos"
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

  // The main app serialises all writes. The NSE only reads this complete item.
  static func getOrCreate() throws -> NotificationRecipient {
    if preferences.bool(forKey: resetPendingKey) || !UserDefaults.standard.bool(forKey: preparedKey) {
      try clear()
    }
    var replacing = false
    do {
      if let record = try read() { return record }
    } catch StoreError.invalidRecord {
      replacing = true
    } catch is DecodingError {
      replacing = true
    }
    let record = try NotificationRecipient.generate()
    let data = try JSONEncoder().encode(record)
    let status: OSStatus
    if replacing {
      status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    } else {
      var attributes = query
      attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      attributes[kSecValueData as String] = data
      status = SecItemAdd(attributes as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw StoreError.keychain(status) }
    UserDefaults.standard.set(true, forKey: preparedKey)
    return record
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
