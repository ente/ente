import CoreText
import SwiftUI
import UIKit

public enum EnteFont {
    public enum InterWeight {
        case light
        case regular
        case medium
        case semibold
        case bold

        fileprivate var name: String {
            switch self {
            case .light: "Inter-Light"
            case .regular: "Inter-Regular"
            case .medium: "Inter-Medium"
            case .semibold: "Inter-SemiBold"
            case .bold: "Inter-Bold"
            }
        }
    }

    public static func inter(
        size: CGFloat,
        weight: InterWeight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        _ = registration
        return .custom(weight.name, size: size, relativeTo: textStyle)
    }

    public static func inter(fixedSize: CGFloat, weight: InterWeight = .regular) -> Font {
        _ = registration
        return .custom(weight.name, fixedSize: fixedSize)
    }

    public static func montserrat(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        _ = registration
        return .custom("Montserrat-Bold", size: size, relativeTo: textStyle)
    }

    public static func montserrat(fixedSize: CGFloat) -> Font {
        _ = registration
        return .custom("Montserrat-Bold", fixedSize: fixedSize)
    }

    public static func outfit(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        _ = registration
        return .custom("Outfit-SemiBold", size: size, relativeTo: textStyle)
    }

    fileprivate static let registration: Void = {
        for url in Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            var error: Unmanaged<CFError>?
            let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
            let errorCode = error.map { CFErrorGetCode($0.takeRetainedValue()) }
            assert(
                registered || errorCode == CTFontManagerError.alreadyRegistered.rawValue,
                "Failed to register font: \(url.lastPathComponent)"
            )
        }
    }()
}

public extension UIFont {
    static func inter(
        size: CGFloat,
        weight: EnteFont.InterWeight = .regular,
        relativeTo textStyle: UIFont.TextStyle = .body
    ) -> UIFont {
        _ = EnteFont.registration
        let descriptor = UIFontDescriptor(name: weight.name, size: size)
        let font = UIFont(descriptor: descriptor, size: size)
        return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
    }
}
