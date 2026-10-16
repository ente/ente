import Foundation

enum CodeFormatting {
    /// Groups a code the way `_getFormattedCode` does in `code_widget.dart`.
    /// Six digits become `123 456`. Seven, eight, and nine digits use the same splits.
    /// Shorter strings are left-padded with zeros up to `digits` before grouping.
    static func display(_ code: String, digits: Int) -> String {
        grouped(leftPad(code, digits: digits))
    }

    /// Shielded placeholder. The phone replaces every non-whitespace character with `•`,
    /// then applies the same length-based grouping.
    static func masked(digits: Int) -> String {
        guard digits > 0 else { return "" }
        return grouped(String(repeating: "•", count: digits))
    }

    static func grouped(_ code: String) -> String {
        let cuts: [Int]
        switch code.count {
        case 6:
            cuts = [3]
        case 7:
            cuts = [3, 4]
        case 8:
            cuts = [3, 5]
        case 9:
            cuts = [3, 6]
        default:
            return code
        }
        var parts: [String] = []
        var start = code.startIndex
        for cut in cuts {
            let end = code.index(code.startIndex, offsetBy: cut)
            parts.append(String(code[start..<end]))
            start = end
        }
        parts.append(String(code[start...]))
        return parts.joined(separator: " ")
    }

    private static func leftPad(_ code: String, digits: Int) -> String {
        guard digits > code.count else { return code }
        return String(repeating: "0", count: digits - code.count) + code
    }
}
