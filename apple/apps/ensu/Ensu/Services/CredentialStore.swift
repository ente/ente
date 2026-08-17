import Foundation
import Security

final class CredentialStore {
    static let shared = CredentialStore()

    private init() {}

    private let keychainService = "io.ente.ensu"

    private enum KeychainAccount {
        static let chatDbKey = "ensu.chatDbKey"
    }

    func getOrCreateChatDbKey(hasChatData: Bool) throws -> Data {
        if let existing = try KeychainStore.get(service: keychainService, account: KeychainAccount.chatDbKey) {
            guard existing.count == 32 else { throw KeychainStoreError.invalidItemFormat }
            return existing
        }
        guard !hasChatData else { throw KeychainStoreError.invalidItemFormat }

        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw KeychainStoreError.unexpectedStatus(status) }
        let data = Data(bytes)
        try KeychainStore.set(data, service: keychainService, account: KeychainAccount.chatDbKey)
        return data
    }
}
