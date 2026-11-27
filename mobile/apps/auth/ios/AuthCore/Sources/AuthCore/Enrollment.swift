import CryptoKit
import Foundation

enum CipherSuite: String, Codable, Sendable {
  case p256 = "p256-aes256gcm"
  case xwing = "xwing-aes256gcm"

  static var supported: [CipherSuite] {
    if #available(iOS 26, macOS 26, watchOS 26, *) { return [.xwing, .p256] }
    if #available(iOS 17, macOS 14, watchOS 10, *) { return [.p256] }
    return []
  }

  @available(iOS 17, macOS 14, watchOS 10, *)
  var hpke: HPKE.Ciphersuite {
    get throws {
      switch self {
      case .p256: return .P256_SHA256_AES_GCM_256
      case .xwing:
        guard #available(iOS 26, macOS 26, watchOS 26, *) else {
          throw WatchError.invalidData
        }
        return .XWingMLKEM768X25519_SHA256_AES_GCM_256
      }
    }
  }
}

public struct Enrollment: Codable, Equatable, Sendable {
  let suite: CipherSuite
  let publicKey: Data

  var id: String {
    SHA256.hash(data: Data(suite.rawValue.utf8) + publicKey)
      .map { String(format: "%02x", $0) }.joined()
  }

  @available(iOS 17, macOS 14, watchOS 10, *)
  func validate() throws {
    _ = try sender(info: Envelope.context)
  }

  @available(iOS 17, macOS 14, watchOS 10, *)
  func sender(info: Data) throws -> HPKE.Sender {
    switch suite {
    case .p256:
      return try HPKE.Sender(
        recipientKey: P256.KeyAgreement.PublicKey(x963Representation: publicKey),
        ciphersuite: suite.hpke, info: info
      )
    case .xwing:
      guard #available(iOS 26, macOS 26, watchOS 26, *) else { throw WatchError.invalidData }
      return try HPKE.Sender(
        recipientKey: XWingMLKEM768X25519.PublicKey(rawRepresentation: publicKey),
        ciphersuite: suite.hpke, info: info
      )
    }
  }
}

@available(iOS 17, macOS 14, watchOS 10, *)
struct PrivateKey: Codable, Sendable {
  let suite: CipherSuite
  let representation: Data

  static func generate(suite: CipherSuite) throws -> PrivateKey {
    switch suite {
    case .p256:
      return PrivateKey(
        suite: suite, representation: P256.KeyAgreement.PrivateKey().rawRepresentation)
    case .xwing:
      guard #available(iOS 26, macOS 26, watchOS 26, *) else {
        throw WatchError.invalidData
      }
      return try PrivateKey(
        suite: suite,
        representation: XWingMLKEM768X25519.PrivateKey().integrityCheckedRepresentation
      )
    }
  }

  var enrollment: Enrollment {
    get throws {
      let publicKey: Data
      switch suite {
      case .p256:
        publicKey = try P256.KeyAgreement.PrivateKey(rawRepresentation: representation)
          .publicKey.x963Representation
      case .xwing:
        guard #available(iOS 26, macOS 26, watchOS 26, *) else {
          throw WatchError.invalidData
        }
        publicKey = try XWingMLKEM768X25519.PrivateKey(
          integrityCheckedRepresentation: representation
        )
        .publicKey.rawRepresentation
      }
      return Enrollment(suite: suite, publicKey: publicKey)
    }
  }

  func recipient(for envelope: Envelope) throws -> HPKE.Recipient {
    guard envelope.header.enrollment == (try enrollment.id), envelope.header.suite == suite else {
      throw WatchError.wrongEnrollment
    }
    switch suite {
    case .p256:
      return try HPKE.Recipient(
        privateKey: P256.KeyAgreement.PrivateKey(rawRepresentation: representation),
        ciphersuite: suite.hpke, info: Envelope.context, encapsulatedKey: envelope.encapsulatedKey
      )
    case .xwing:
      guard #available(iOS 26, macOS 26, watchOS 26, *) else {
        throw WatchError.invalidData
      }
      return try HPKE.Recipient(
        privateKey: XWingMLKEM768X25519.PrivateKey(integrityCheckedRepresentation: representation),
        ciphersuite: suite.hpke, info: Envelope.context, encapsulatedKey: envelope.encapsulatedKey
      )
    }
  }
}
