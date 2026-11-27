import Foundation
import Security

struct KeychainError: Error {
  let status: OSStatus
}

@available(iOS 17, macOS 14, watchOS 10, *)
struct PasscodeKeychain {
  private var query: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "io.ente.auth.watch",
      kSecAttrAccount as String: "enrollment",
      kSecAttrSynchronizable as String: false,
    ]
  }

  func read() throws -> PrivateKey? {
    var request = query
    request[kSecReturnData as String] = true
    request[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(request as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainError(status: status)
    }
    return try JSONDecoder().decode(PrivateKey.self, from: data)
  }

  func write(_ key: PrivateKey) throws {
    var request = query
    request[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
    request[kSecValueData as String] = try JSONEncoder().encode(key)
    let status = SecItemAdd(request as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  func remove() throws {
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }
}
