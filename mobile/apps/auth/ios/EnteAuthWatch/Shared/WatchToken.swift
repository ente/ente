import Foundation

/// Incoming sync token. `secret` exists so the payload can be decoded.
/// Copy it into a `SecretBuffer`, store the raw seed in the Keychain, and do not log it.
internal struct WatchToken: Identifiable, Codable, Sendable {
    internal let id: String
    internal let issuer: String
    internal let account: String
    internal let secret: String
    internal let algorithm: HashAlgorithm
    internal let digits: Int
    internal let period: Int
    internal let isFavorite: Bool
    internal let sortOrder: Int

    internal enum HashAlgorithm: String, Codable, Sendable {
        case sha1 = "SHA1"
        case sha256 = "SHA256"
        case sha512 = "SHA512"
    }

    internal enum CodingKeys: String, CodingKey {
        case id
        case issuer
        case account
        case secret
        case algorithm
        case digits
        case period
        case isFavorite
        case sortOrder
    }
}

internal struct WatchSyncEnvelope: Codable, Sendable {
    internal let version: Int
    internal let timestamp: Int
    internal let syncType: String
    internal let tokens: [WatchToken]
    internal let deletedIds: [String]

    internal enum CodingKeys: String, CodingKey {
        case version
        case timestamp
        case syncType
        case tokens
        case deletedIds
    }
}

/// Metadata for the watch UI. There is no secret field; load the seed from the Keychain.
internal struct WatchTokenDisplay: Identifiable, Hashable, Sendable {
    internal let id: String
    internal let issuer: String
    internal let account: String
    internal let algorithm: WatchToken.HashAlgorithm
    internal let digits: Int
    internal let period: Int
    internal let sortOrder: Int
    internal let isFavorite: Bool
}
