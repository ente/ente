import CryptoKit
import Foundation

public enum OTP {
  public enum Algorithm: String, Codable, Sendable {
    case sha1, sha256, sha512
  }

  public static func totp(
    secret: Data, algorithm: Algorithm, digits: Int, period: Int, at date: Date
  ) -> String? {
    guard (1...10).contains(digits),
      let value = truncatedHash(secret: secret, algorithm: algorithm, period: period, at: date)
    else { return nil }
    let modulus = (0..<digits).reduce(UInt64(1)) { result, _ in result * 10 }
    let code = String(UInt64(value) % modulus)
    return String(repeating: "0", count: digits - code.count) + code
  }

  public static func steam(secret: Data, at date: Date) -> String? {
    guard var value = truncatedHash(secret: secret, algorithm: .sha1, period: 30, at: date) else {
      return nil
    }
    let alphabet = Array("23456789BCDFGHJKMNPQRTVWXY")
    return String(
      (0..<5).map { _ in
        let character = alphabet[Int(value % UInt32(alphabet.count))]
        value /= UInt32(alphabet.count)
        return character
      })
  }

  private static func truncatedHash(
    secret: Data, algorithm: Algorithm, period: Int, at date: Date
  ) -> UInt32? {
    let seconds = date.timeIntervalSince1970
    guard !secret.isEmpty, period > 0,
      seconds.isFinite, seconds >= 0, seconds < Double(Int64.max)
    else { return nil }
    var counter = (UInt64(seconds.rounded(.down)) / UInt64(period)).bigEndian
    let message = withUnsafeBytes(of: &counter) { Data($0) }
    let key = SymmetricKey(data: secret)
    let digest: [UInt8]
    switch algorithm {
    case .sha1:
      digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
    case .sha256:
      digest = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
    case .sha512:
      digest = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
    }
    let offset = Int(digest[digest.count - 1] & 0x0f)
    let value = digest[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    return value & 0x7fff_ffff
  }
}
