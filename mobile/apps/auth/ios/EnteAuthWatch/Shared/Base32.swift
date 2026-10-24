import Foundation

/// RFC 4648 base32 (`A`–`Z`, `2`–`7`). Accepts omitted `=` padding. Does not log the input.
internal enum Base32 {
    private static let values: [Int8] = {
        var table = [Int8](repeating: -1, count: 128)
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
        for (index, byte) in alphabet.enumerated() {
            table[Int(byte)] = Int8(index)
        }
        // otpauth secrets are often lowercase. `getSanitizedSecret` uppercases on the phone;
        // accept the same alphabet here so a lowercase payload still decodes.
        for (index, byte) in Array("abcdefghijklmnopqrstuvwxyz".utf8).enumerated() {
            table[Int(byte)] = Int8(index)
        }
        return table
    }()

    internal static func decode(_ sanitized: String) -> SecretBuffer? {
        var dataBytes: [UInt8] = []
        dataBytes.reserveCapacity(sanitized.unicodeScalars.count)
        defer { SecretBuffer.wipe(&dataBytes) }
        var padding = 0
        var inPadding = false
        for scalar in sanitized.unicodeScalars {
            if scalar == "=" {
                inPadding = true
                padding += 1
                continue
            }
            if inPadding || scalar.value > 127 {
                return nil
            }
            let byte = UInt8(scalar.value)
            guard values[Int(byte)] >= 0 else { return nil }
            dataBytes.append(byte)
        }

        let count = dataBytes.count
        guard isValidBodyLength(count) else { return nil }
        if padding > 0 {
            guard padding == expectedPadding(forBodyLength: count) else { return nil }
        }

        var output: [UInt8] = []
        output.reserveCapacity(count * 5 / 8)
        defer { SecretBuffer.wipe(&output) }

        var accumulator: UInt64 = 0
        var bits = 0
        for byte in dataBytes {
            let value = UInt64(values[Int(byte)])
            accumulator = (accumulator << 5) | value
            bits += 5
            if bits >= 8 {
                bits -= 8
                output.append(UInt8((accumulator >> bits) & 0xff))
            }
        }
        if bits > 0 {
            let leftoverMask = (UInt64(1) << bits) - 1
            if accumulator & leftoverMask != 0 {
                return nil
            }
        }
        return SecretBuffer(bytes: output)
    }

    private static func isValidBodyLength(_ count: Int) -> Bool {
        switch count % 8 {
        case 0, 2, 4, 5, 7:
            return true
        default:
            return false
        }
    }

    private static func expectedPadding(forBodyLength count: Int) -> Int {
        switch count % 8 {
        case 0: return 0
        case 2: return 6
        case 4: return 4
        case 5: return 3
        case 7: return 1
        default: return -1
        }
    }
}
