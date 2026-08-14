import SwiftUI
import UIKit

struct FontUtils {
    
    // MARK: - Safe Font Creation
    
    private static func safeFont(name: String, size: CGFloat, fallback: Font) -> Font {
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size)
        } else {
            return fallback
        }
    }
    
    // MARK: - Font Presets
    
    static func montserratBold(size: CGFloat) -> Font {
        return safeFont(name: "Montserrat-Bold", size: size, fallback: .system(size: size, weight: .bold))
    }
    
    static func montserratExtraBold(size: CGFloat) -> Font {
        return safeFont(name: "Montserrat-Bold", size: size, fallback: .system(size: size, weight: .heavy))
    }
    
    static func interRegular(size: CGFloat) -> Font {
        return safeFont(name: "Inter-Regular", size: size, fallback: .system(size: size, weight: .regular))
    }
    
    static func interMedium(size: CGFloat) -> Font {
        return safeFont(name: "Inter-Medium", size: size, fallback: .system(size: size, weight: .medium))
    }
    
    static func interSemiBold(size: CGFloat) -> Font {
        return safeFont(name: "Inter-SemiBold", size: size, fallback: .system(size: size, weight: .semibold))
    }
    
    static func interBold(size: CGFloat) -> Font {
        return safeFont(name: "Inter-Bold", size: size, fallback: .system(size: size, weight: .bold))
    }
}
