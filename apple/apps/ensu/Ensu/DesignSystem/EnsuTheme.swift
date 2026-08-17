import SwiftUI
import UIKit
typealias PlatformColor = UIColor

enum EnsuColor {
    static let backgroundBase = Color(PlatformColor.dynamic(light: "#F8F5F0", dark: "#141414"))
    static let textPrimary = Color(PlatformColor.dynamic(light: "#1A1A1A", dark: "#E8E4DF"))
    static let textMuted = Color(PlatformColor.dynamic(light: "#8A8680", dark: "#777777"))
    static let border = Color(PlatformColor.dynamic(light: "#D4D0C8", dark: "#2A2A2A"))
    static let fillFaint = Color(PlatformColor.dynamic(light: "#F0EBE4", dark: "#1E1E1E"))
    static let accent = Color(PlatformColor.dynamic(light: "#FDCE13", dark: "#FDCE13"))
    static let action = Color(PlatformColor.dynamic(light: "#1A1A1A", dark: "#FDCE13"))
    static let userMessageText = Color(PlatformColor.dynamic(light: "#555555", dark: "#999999"))

    static let error = Color(hex: "#FF4444")
    static let success = Color(hex: "#4CAF50")
    static let stopButton = Color(hex: "#FF0000")

    static let toastBackground = Color(PlatformColor.dynamic(light: "#1A1A1A", dark: "#F8F5F0"))
    static let toastText = Color(PlatformColor.dynamic(light: "#F8F5F0", dark: "#1A1A1A"))

    static var accentGradient: LinearGradient {
        LinearGradient(
            colors: [accent, accent.opacity(0.85)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum EnsuSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32

    static let pageHorizontal: CGFloat = 24
    static let pageVertical: CGFloat = 24
    static let inputHorizontal: CGFloat = 16
    static let inputVertical: CGFloat = 16
    static let buttonVertical: CGFloat = 18
    static let cardPadding: CGFloat = 12
    static let messageBubbleInset: CGFloat = 80
}

enum EnsuCornerRadius {
    static let button: CGFloat = 8
    static let input: CGFloat = 8
    static let card: CGFloat = 12
    static let toast: CGFloat = 12
    static let codeBlock: CGFloat = 10
}

enum EnsuLineHeight {
    static func spacing(fontSize: CGFloat, lineHeight: CGFloat) -> CGFloat {
        max(0, fontSize * lineHeight - fontSize)
    }
}

enum EnsuTypography {
    static let h1 = EnsuFont.serif(size: 48, weight: .medium)
    static let h2 = EnsuFont.serif(size: 32, weight: .medium)
    static let h3 = EnsuFont.serif(size: 24, weight: .medium)
    static let large = EnsuFont.serif(size: 18, weight: .medium)

    static let h1Bold = EnsuFont.serif(size: 48, weight: .semibold)
    static let h2Bold = EnsuFont.serif(size: 32, weight: .semibold)
    static let h3Bold = EnsuFont.serif(size: 24, weight: .semibold)

    static let body = EnsuFont.ui(size: 16, weight: .medium)
    static let small = EnsuFont.ui(size: 14, weight: .medium)
    static let mini = EnsuFont.ui(size: 12, weight: .medium)
    static let tiny = EnsuFont.ui(size: 10, weight: .medium)

    static let message = EnsuFont.message(size: 15, weight: .regular)
    static let code = EnsuFont.code(size: 13, weight: .regular)
}

enum EnsuFont {
    static func serif(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func ui(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func message(size: CGFloat, weight: Font.Weight) -> Font {
        ui(size: size, weight: weight)
    }

    static func code(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: String) {
        self.init(PlatformColor(hex: hex))
    }
}

extension PlatformColor {
    convenience init(hex: String) {
        let hexString = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexString).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hexString.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }

    static func dynamic(light: String, dark: String) -> PlatformColor {
        return PlatformColor { trait in
            trait.userInterfaceStyle == .dark ? PlatformColor(hex: dark) : PlatformColor(hex: light)
        }
    }
}
