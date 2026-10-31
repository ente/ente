import CryptoKit
import Foundation
import Security

// Compiled into both Runner and the extension. No account or sync keys are shared.
enum AutoFillStore {
    static let group = "group.io.ente.auth.autofill"
    private static let service = "io.ente.auth.autofill"

    enum StoreError: Error {
        case unavailable, invalidSnapshot, keychain(OSStatus)
    }

    private static func fileURL() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group
        ) else { throw StoreError.unavailable }
        return container.appendingPathComponent("autofill.enc")
    }

    private static func keyQuery() throws -> [String: Any] {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "AutoFillKeychainGroup") as? String,
              !group.contains("$(") else { throw StoreError.unavailable }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "snapshot-key",
            kSecAttrAccessGroup as String: group,
        ]
    }

    private static func key(create: Bool) throws -> SymmetricKey {
        var query = try keyQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            guard data.count == 32 else { throw StoreError.invalidSnapshot }
            return SymmetricKey(data: data)
        }
        guard status == errSecItemNotFound, create else {
            throw StoreError.keychain(status)
        }
        let key = SymmetricKey(size: .bits256)
        var attributes = try keyQuery()
        attributes[kSecValueData as String] = key.withUnsafeBytes { Data($0) }
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let added = SecItemAdd(attributes as CFDictionary, nil)
        guard added == errSecSuccess else { throw StoreError.keychain(added) }
        return key
    }

    static func write(_ snapshot: AutoFillSnapshot) throws {
        guard snapshot.version == 1 else { throw StoreError.invalidSnapshot }
        // Validate all entries before replacing a previously valid snapshot.
        for entry in snapshot.entries { _ = try TOTP.generate(entry, time: 0) }
        let data = try JSONEncoder().encode(snapshot)
        let sealed = try AES.GCM.seal(data, using: key(create: true))
        guard let combined = sealed.combined else { throw StoreError.invalidSnapshot }
        let url = try fileURL()
        try combined.write(to: url, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    static func read() throws -> AutoFillSnapshot {
        let encrypted = try Data(contentsOf: fileURL())
        let data = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: key(create: false))
        let snapshot = try JSONDecoder().decode(AutoFillSnapshot.self, from: data)
        guard snapshot.version == 1 else { throw StoreError.invalidSnapshot }
        return snapshot
    }

    static func clear() throws {
        // Delete the key even if removing the file fails; leftover ciphertext is unusable.
        let status = SecItemDelete(try keyQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
        let url = try fileURL()
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }
}
