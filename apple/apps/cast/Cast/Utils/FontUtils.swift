import SwiftUI
import UIKit

enum FontUtils {
    private static func safeFont(name: String, size: CGFloat, fallback: Font) -> Font {
        if UIFont(name: name, size: size) != nil {
            .custom(name, size: size)
        } else {
            fallback
        }
    }

    static func montserratBold(size: CGFloat) -> Font {
        safeFont(name: "Montserrat-Bold", size: size, fallback: .system(size: size, weight: .bold))
    }

    static func montserratExtraBold(size: CGFloat) -> Font {
        safeFont(name: "Montserrat-Bold", size: size, fallback: .system(size: size, weight: .heavy))
    }

    static func interRegular(size: CGFloat) -> Font {
        safeFont(name: "Inter-Regular", size: size, fallback: .system(size: size, weight: .regular))
    }

    static func interMedium(size: CGFloat) -> Font {
        safeFont(name: "Inter-Medium", size: size, fallback: .system(size: size, weight: .medium))
    }

    static func interSemiBold(size: CGFloat) -> Font {
        safeFont(
            name: "Inter-SemiBold",
            size: size,
            fallback: .system(size: size, weight: .semibold),
        )
    }

    static func interBold(size: CGFloat) -> Font {
        safeFont(name: "Inter-Bold", size: size, fallback: .system(size: size, weight: .bold))
    }
}
