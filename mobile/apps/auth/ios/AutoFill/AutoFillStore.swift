import CryptoKit
import Foundation
import Security

// Compiled into both Runner and the extension. No account or sync keys are shared.
enum AutoFillStore {
    static let group = "group.io.ente.auth.autofill"
    private static let service = "io.ente.auth.autofill"

    enum StoreError: Error {
        case unavailable, invalidSnapshot, revoked, keychain(OSStatus)
    }

    private static func containerURL() throws -> URL {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: group
        ) else { throw StoreError.unavailable }
        return container
    }

    // Keychain Services supplies the default access group from the signed
    // entitlements. AppIdentifierPrefix is not reliably expanded in Info.plist,
    // and a legacy App ID prefix need not equal DEVELOPMENT_TEAM. Probe with an
    // empty, uniquely named item so neither target's account keys are touched.
    static func resolveKeychainAccessGroup(
        addItem: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemAdd,
        deleteItem: (CFDictionary) -> OSStatus = SecItemDelete
    ) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service + ".access-group-probe",
            kSecAttrAccount as String: UUID().uuidString,
        ]
        var attributes = query
        attributes[kSecValueData as String] = Data()
        // This item contains no secret. Allow resolution during locked-device
        // cleanup; the actual snapshot key remains WhenUnlockedThisDeviceOnly.
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attributes[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = addItem(attributes as CFDictionary, &result)
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        defer { _ = deleteItem(query as CFDictionary) }
        guard let attributes = result as? [String: Any],
              let defaultGroup = attributes[kSecAttrAccessGroup as String] as? String,
              let separator = defaultGroup.firstIndex(of: "."),
              separator != defaultGroup.startIndex else { throw StoreError.unavailable }
        return String(defaultGroup[..<separator]) + "." + service
    }

    private static func keyQuery() throws -> [String: Any] {
        let group = try resolveKeychainAccessGroup()
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

    private static let storage = AutoFillStorage(
        container: containerURL,
        loadKey: key,
        deleteKey: {
            let status = SecItemDelete(try keyQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw StoreError.keychain(status)
            }
        }
    )

    static func invalidate() throws -> String { try storage.invalidate() }
    static func write(_ snapshot: AutoFillSnapshot) throws -> Int { try storage.write(snapshot) }
    static func read() throws -> AutoFillSnapshot { try storage.read() }
    static func clear() throws { try storage.clear() }
}

// File/encryption logic is shared with the macOS test target. Production is the
// only caller supplying an App Group container and the real shared Keychain.
final class AutoFillStorage {
    private struct State: Codable, Equatable {
        let generation: String
        let enabled: Bool
    }

    private let container: () throws -> URL
    private let loadKey: (Bool) throws -> SymmetricKey
    private let deleteKey: () throws -> Void
    private let removeFile: (URL) throws -> Void

    init(container: @escaping () throws -> URL,
         loadKey: @escaping (Bool) throws -> SymmetricKey,
         deleteKey: @escaping () throws -> Void,
         removeFile: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }) {
        self.container = container
        self.loadKey = loadKey
        self.deleteKey = deleteKey
        self.removeFile = removeFile
    }

    private func url(_ name: String) throws -> URL { try container().appendingPathComponent(name) }

    private func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private func state() throws -> State {
        try JSONDecoder().decode(State.self, from: Data(contentsOf: url("autofill.state")))
    }

    private func setState(_ state: State) throws {
        try writeProtected(JSONEncoder().encode(state), to: url("autofill.state"))
    }

    // Persisted before a destructive mutation, independently of snapshot/key
    // deletion. A delayed publication cannot reactivate a revoked generation.
    func invalidate() throws -> String {
        let generation = UUID().uuidString
        try setState(State(generation: generation, enabled: false))
        return generation
    }

    func write(_ snapshot: AutoFillSnapshot) throws -> Int {
        guard snapshot.version == 1 else { throw AutoFillStore.StoreError.invalidSnapshot }
        let expected = try state()
        guard expected.generation == snapshot.generation else { throw AutoFillStore.StoreError.revoked }
        let entries = snapshot.entries.filter { (try? TOTP.generate($0, time: 0)) != nil }
        let validated = AutoFillSnapshot(version: snapshot.version, generation: snapshot.generation,
                                        timeOffsetMilliseconds: snapshot.timeOffsetMilliseconds, entries: entries)
        let sealed = try AES.GCM.seal(JSONEncoder().encode(validated), using: loadKey(true))
        guard let combined = sealed.combined else { throw AutoFillStore.StoreError.invalidSnapshot }
        try writeProtected(combined, to: url("autofill.enc"))
        guard try state() == expected else { throw AutoFillStore.StoreError.revoked }
        try setState(State(generation: snapshot.generation, enabled: true))
        return snapshot.entries.count - entries.count
    }

    func read() throws -> AutoFillSnapshot {
        let expected = try state()
        guard expected.enabled else { throw AutoFillStore.StoreError.revoked }
        let encrypted = try Data(contentsOf: url("autofill.enc"))
        let data = try AES.GCM.open(AES.GCM.SealedBox(combined: encrypted), using: loadKey(false))
        let snapshot = try JSONDecoder().decode(AutoFillSnapshot.self, from: data)
        guard snapshot.version == 1, snapshot.generation == expected.generation,
              try state() == expected else { throw AutoFillStore.StoreError.revoked }
        return snapshot
    }

    func clear() throws {
        var failure: Error?
        do { _ = try invalidate() } catch { failure = error }
        // Try every revocation mechanism even when an earlier operation fails.
        // In particular, Keychain errors must not prevent deleting ciphertext.
        do { try deleteKey() } catch { failure = failure ?? error }
        do {
            let file = try url("autofill.enc")
            if FileManager.default.fileExists(atPath: file.path) { try removeFile(file) }
        } catch {
            failure = failure ?? error
        }
        if let failure { throw failure }
    }
}
