import CryptoKit
import Foundation

enum TOTP {
    enum InvalidCode: Error { case parameters, secret, algorithm }

    static func generate(_ entry: AutoFillEntry, time: TimeInterval) throws -> String {
        guard (1...10).contains(entry.digits), entry.period > 0,
              time.isFinite, time >= 0,
              time / Double(entry.period) < Double(UInt64.max) else {
            throw InvalidCode.parameters
        }
        let key = SymmetricKey(data: try decodeBase32(entry.secret))
        var counter = UInt64(time / Double(entry.period)).bigEndian
        let message = withUnsafeBytes(of: &counter) { Data($0) }
        let digest: [UInt8]
        switch entry.algorithm.lowercased() {
        case "sha1": digest = Array(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case "sha256": digest = Array(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case "sha512": digest = Array(HMAC<SHA512>.authenticationCode(for: message, using: key))
        default: throw InvalidCode.algorithm
        }
        let offset = Int(digest[digest.count - 1] & 0x0f)
        let truncated = digest[offset..<offset + 4].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let modulus = (0..<entry.digits).reduce(UInt64(1)) { value, _ in value * 10 }
        let code = String((truncated & 0x7fffffff) % modulus)
        return String(repeating: "0", count: entry.digits - code.count) + code
    }

    private static func decodeBase32(_ secret: String) throws -> Data {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        let normalized = secret.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        var unpadded = normalized
        while unpadded.last == "=" { unpadded.removeLast() }
        guard [0, 2, 4, 5, 7].contains(unpadded.utf8.count % 8) else {
            throw InvalidCode.secret
        }
        var buffer: UInt32 = 0
        var bits = 0
        var result = Data()
        for character in unpadded.utf8 {
            guard let value = alphabet.firstIndex(of: character) else { throw InvalidCode.secret }
            buffer = (buffer << 5) | UInt32(value)
            bits += 5
            if bits >= 8 {
                bits -= 8
                result.append(UInt8((buffer >> bits) & 0xff))
            }
            buffer &= (1 << bits) - 1
        }
        guard !result.isEmpty, buffer == 0 else { throw InvalidCode.secret }
        return result
    }
}
