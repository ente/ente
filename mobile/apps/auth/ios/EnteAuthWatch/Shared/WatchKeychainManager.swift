import Foundation
import Security

internal enum WatchKeychainError: Error, Equatable {
    case passcodeRequired
    /// Keychain exists, but the watch is locked. Not the same as a missing passcode.
    case locked
    case unexpectedStatus(OSStatus)
}

@MainActor
internal protocol WatchSeedStoring: AnyObject {
    var canStoreSecrets: Bool { get }
    func save(id: String, seed: SecretBuffer) throws
    func load(id: String) -> SecretBuffer?
    func delete(id: String)
    /// Deletes every item for this service even when a passcode is no longer set.
    func purgeAll() throws
    func allAccountIDs() throws -> [String]
}

/// Query shape and protection flags the production Keychain calls actually use.
/// Tests assert this dictionary. The simulator cannot prove the stored item's flags.
enum WatchKeychainContract {
    static let service = "io.ente.auth.watch"
    static let protection = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    static let flags: SecAccessControlCreateFlags = .devicePasscode

    static func accountQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func purgeQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
    }

    static func makeAccessControl() -> SecAccessControl? {
        var error: Unmanaged<CFError>?
        let control = SecAccessControlCreateWithFlags(
            nil,
            protection,
            flags,
            &error
        )
        if let error {
            _ = error.takeRetainedValue()
        }
        return control
    }
}

@MainActor
internal final class WatchKeychainManager: WatchSeedStoring {
    internal static let shared = WatchKeychainManager()
    internal static let service = WatchKeychainContract.service
    internal static let passcodeRequiredMessage = "Passcode required on Apple Watch to sync tokens"

    internal var canStoreSecrets: Bool {
        WatchKeychainContract.makeAccessControl() != nil
    }

    internal func save(id: String, seed: SecretBuffer) throws {
        guard let accessControl = WatchKeychainContract.makeAccessControl() else {
            throw WatchKeychainError.passcodeRequired
        }
        let status: OSStatus = seed.withUnsafeBytes { raw in
            let data = Data(raw)
            var match = WatchKeychainContract.accountQuery(account: id)
            let update: [String: Any] = [
                kSecValueData as String: data,
            ]
            let updateStatus = SecItemUpdate(match as CFDictionary, update as CFDictionary)
            if updateStatus == errSecSuccess {
                return errSecSuccess
            }
            if updateStatus != errSecItemNotFound {
                return updateStatus
            }
            match[kSecValueData as String] = data
            match[kSecAttrAccessControl as String] = accessControl
            return SecItemAdd(match as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw Self.classify(status)
        }
    }

    internal func load(id: String) -> SecretBuffer? {
        guard canStoreSecrets else { return nil }
        var query = WatchKeychainContract.accountQuery(account: id)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return SecretBuffer(data: data)
    }

    /// Best-effort. Deleting an id that is not stored is success. Does nothing when no passcode is set.
    internal func delete(id: String) {
        guard canStoreSecrets else { return }
        let query = WatchKeychainContract.accountQuery(account: id)
        _ = SecItemDelete(query as CFDictionary)
    }

    /// Best-effort wipe of `io.ente.auth.watch`. Does not require a passcode.
    /// Used when the passcode is removed or the iPhone companion goes away.
    /// `SecItemDelete` may still fail if the OS will not touch a passcode item;
    /// the call is still made.
    internal func purgeAll() throws {
        _ = SecItemDelete(WatchKeychainContract.purgeQuery() as CFDictionary)
    }

    internal func allAccountIDs() throws -> [String] {
        guard canStoreSecrets else {
            throw WatchKeychainError.passcodeRequired
        }
        var query = WatchKeychainContract.purgeQuery()
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw Self.classify(status)
        }
        guard let rows = item as? [[String: Any]] else {
            return []
        }
        return rows.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private static func classify(_ status: OSStatus) -> WatchKeychainError {
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed {
            return .locked
        }
        return .unexpectedStatus(status)
    }
}
