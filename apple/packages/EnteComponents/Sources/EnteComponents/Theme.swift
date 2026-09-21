import EnteFonts
import SwiftUI

public enum EnteApp: Sendable {
    case photos
    case auth
    case locker
}

public struct Palette: Sendable {
    public let isDark: Bool
    public let primary: Color
    public let primaryDarker: Color
    public let text: Color
    public let mutedText: Color
    public let hintText: Color
    public let disabledText: Color
    public let reverseText: Color
    public let surface: Color
    public let fill: Color
    public let fillDarker: Color
    public let fillDarkest: Color
    public let faintBorder: Color
    public let danger: Color
    public let dangerDarker: Color

    fileprivate static func make(app: EnteApp, dark: Bool) -> Palette {
        let primary: Color
        let primaryDarker: Color
        switch app {
        case .photos:
            primary = Color(hex: 0x08C225)
            primaryDarker = Color(hex: 0x057C18)
        case .auth:
            primary = Color(hex: 0x9610D6)
            primaryDarker = Color(hex: 0x5D0884)
        case .locker:
            primary = Color(hex: 0x1071FF)
            primaryDarker = Color(hex: 0x0B4CAD)
        }
        return Palette(
            isDark: dark,
            primary: primary,
            primaryDarker: primaryDarker,
            text: dark ? .white : .black,
            mutedText: Color(hex: dark ? 0x999999 : 0x666666),
            hintText: Color(hex: 0x969696),
            disabledText: Color(hex: dark ? 0x414141 : 0xD6D6D6),
            reverseText: dark ? .black : .white,
            surface: Color(hex: dark ? 0x212121 : 0xFFFFFF),
            fill: Color(hex: dark ? 0x0A0A0A : 0xEAEAEA),
            fillDarker: Color(hex: dark ? 0x141414 : 0xDEDEDE),
            fillDarkest: Color(hex: dark ? 0x292929 : 0xD2D2D2),
            faintBorder: Color(hex: dark ? 0x2A2A2A : 0xEBEBEB),
            danger: Color(hex: 0xF63A3A),
            dangerDarker: Color(hex: 0xC52E2E)
        )
    }
}

public enum EnteSpacing {
    public static let xs: CGFloat = 4
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 16
    public static let xl: CGFloat = 20
}

public enum EnteRadius {
    public static let medium: CGFloat = 12
    public static let button: CGFloat = 20
}

public enum EnteMotion {
    public static let quick = 0.12
}

public enum EnteTypography {
    public static let display2 = EnteFont.outfit(size: 24, relativeTo: .title)
    public static let body = EnteFont.inter(size: 14, weight: .medium, relativeTo: .body)
    public static let bodyBold = EnteFont.inter(size: 14, weight: .semibold, relativeTo: .body)
    public static let mini = EnteFont.inter(size: 12, weight: .medium, relativeTo: .caption)
}

public struct EnteTheme<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let app: EnteApp
    private let content: Content

    public init(app: EnteApp = .photos, @ViewBuilder content: () -> Content) {
        self.app = app
        self.content = content()
    }

    public var body: some View {
        let palette = Palette.make(app: app, dark: colorScheme == .dark)
        content.environment(\.entePalette, palette)
    }
}

private struct EntePaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make(app: .photos, dark: false)
}

public extension EnvironmentValues {
    var entePalette: Palette {
        get { self[EntePaletteKey.self] }
        set { self[EntePaletteKey.self] = newValue }
    }
}

private extension Color {
    init(hex: UInt) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
