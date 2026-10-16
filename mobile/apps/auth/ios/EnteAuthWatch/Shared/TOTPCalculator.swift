import CryptoKit
import Foundation

/// RFC 4226 HOTP and RFC 6238 TOTP. The watch clock is `date`; this type does not read a phone time offset.
internal enum TOTPCalculator {
    internal static func modulus(digits: Int) -> UInt64 {
        precondition((1...10).contains(digits))
        var value: UInt64 = 1
        for _ in 0..<digits {
            value *= 10
        }
        return value
    }

    internal static func hotp(
        key: Data,
        counter: UInt64,
        algorithm: WatchToken.HashAlgorithm,
        digits: Int
    ) -> String {
        let secret = SecretBuffer(data: key)
        return hotp(secret: secret, counter: counter, algorithm: algorithm, digits: digits)
    }

    internal static func hotp(
        secret: SecretBuffer,
        counter: UInt64,
        algorithm: WatchToken.HashAlgorithm,
        digits: Int
    ) -> String {
        precondition((1...10).contains(digits))
        precondition(secret.count > 0)
        let message = counterData(counter)
        let hashData = secret.withUnsafeBytes { raw -> Data in
            let key = SymmetricKey(data: raw)
            return hmac(algorithm: algorithm, key: key, message: message)
        }
        return truncate(hashData, digits: digits)
    }

    internal static func generateCode(
        secret: SecretBuffer,
        algorithm: WatchToken.HashAlgorithm,
        digits: Int,
        period: Int,
        date: Date = Date()
    ) -> (current: String, next: String, remainingSeconds: Int) {
        precondition(period > 0)
        let interval = date.timeIntervalSince1970
        precondition(interval >= 0)
        let unix = UInt64(interval)
        let step = UInt64(period)
        let counter = unix / step
        let modulo = unix % step
        // If unix % period == 0, the window just started, so remainingSeconds is a full period.
        let remainingSeconds = modulo == 0 ? period : period - Int(modulo)
        let current = hotp(secret: secret, counter: counter, algorithm: algorithm, digits: digits)
        let next = hotp(secret: secret, counter: counter &+ 1, algorithm: algorithm, digits: digits)
        return (current, next, remainingSeconds)
    }

    private static func counterData(_ counter: UInt64) -> Data {
        var data = Data(count: 8)
        var value = counter
        for index in stride(from: 7, through: 0, by: -1) {
            data[index] = UInt8(truncatingIfNeeded: value)
            value >>= 8
        }
        return data
    }

    private static func hmac(
        algorithm: WatchToken.HashAlgorithm,
        key: SymmetricKey,
        message: Data
    ) -> Data {
        switch algorithm {
        case .sha1:
            return Data(HMAC<Insecure.SHA1>.authenticationCode(for: message, using: key))
        case .sha256:
            return Data(HMAC<SHA256>.authenticationCode(for: message, using: key))
        case .sha512:
            return Data(HMAC<SHA512>.authenticationCode(for: message, using: key))
        }
    }

    private static func truncate(_ hashData: Data, digits: Int) -> String {
        precondition(hashData.count >= 4)
        let offset = Int(hashData[hashData.count - 1] & 0x0f)
        precondition(offset + 4 <= hashData.count)
        let b0 = UInt32(hashData[offset])
        let b1 = UInt32(hashData[offset + 1])
        let b2 = UInt32(hashData[offset + 2])
        let b3 = UInt32(hashData[offset + 3])
        let number = ((b0 << 24) | (b1 << 16) | (b2 << 8) | b3) & 0x7fff_ffff
        let reduced = UInt64(number) % modulus(digits: digits)
        return formatOTP(reduced, digits: digits)
    }

    private static func formatOTP(_ value: UInt64, digits: Int) -> String {
        let text = String(value)
        if text.count >= digits {
            return text
        }
        return String(repeating: "0", count: digits - text.count) + text
    }
}
