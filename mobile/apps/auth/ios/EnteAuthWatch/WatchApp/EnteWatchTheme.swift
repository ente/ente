import SwiftUI

/// Colors copied from the phone Auth theme. Light and dark follow the system,
/// which is the phone default (`ThemeMode.system` in `auth_theme_preferences.dart`).
///
/// Sources:
/// - `lib/theme/colors.dart` — `primary700` `0xFF722ED1`, backgrounds, text, pinned fills
/// - `lib/ente_theme_data.dart` — `codeCardBackgroundColor`
/// - `lib/ui/code_timer_progress.dart` — bar is `primary700` while
///   `timeRemaining / period > 0.4`, otherwise `Colors.orange` (`0xFFFF9800`)
/// - `lib/ui/code_widget.dart` — account and next code use `Colors.grey`
enum EnteWatchColor {
    /// `_primary700` in `colors.dart`.
    static let primary700Red: Double = 114.0 / 255.0
    static let primary700Green: Double = 46.0 / 255.0
    static let primary700Blue: Double = 209.0 / 255.0

    /// Flutter `Colors.orange`.
    static let timerWarningRed: Double = 255.0 / 255.0
    static let timerWarningGreen: Double = 152.0 / 255.0
    static let timerWarningBlue: Double = 0

    /// Material `Colors.grey`.
    static let greyRed: Double = 158.0 / 255.0
    static let greyGreen: Double = 158.0 / 255.0
    static let greyBlue: Double = 158.0 / 255.0

    static let primary700 = Color(red: primary700Red, green: primary700Green, blue: primary700Blue)
    static let timerWarning = Color(red: timerWarningRed, green: timerWarningGreen, blue: timerWarningBlue)
    static let grey = Color(red: greyRed, green: greyGreen, blue: greyBlue)

    /// Pin glyph in `assets/svg/pin-card.svg` (`#9610D6`, `primaryColor` in `ente_theme_data.dart`).
    static let pinGlyphRed: Double = 150.0 / 255.0
    static let pinGlyphGreen: Double = 16.0 / 255.0
    static let pinGlyphBlue: Double = 214.0 / 255.0
    static let pinGlyph = Color(red: pinGlyphRed, green: pinGlyphGreen, blue: pinGlyphBlue)

    /// Filled primary button on the phone (`ButtonComponent` primary).
    /// `purpleDefaultLight` and `purpleDefaultDark` in `ente_components` `colors.dart`:
    /// `Color.fromRGBO(150, 16, 214, 1)` (`#9610D6`). Same RGB as the pin glyph.
    /// Code progress stays `primary700` (`#722ED1`), which is a different purple.
    static let buttonPrimaryRed: Double = 150.0 / 255.0
    static let buttonPrimaryGreen: Double = 16.0 / 255.0
    static let buttonPrimaryBlue: Double = 214.0 / 255.0
    static let buttonPrimary = Color(
        red: buttonPrimaryRed,
        green: buttonPrimaryGreen,
        blue: buttonPrimaryBlue
    )

    static let backgroundBaseLight = Color(red: 1, green: 1, blue: 1)
    static let backgroundBaseDark = Color(red: 0, green: 0, blue: 0)
    static let textBaseLight = Color(red: 0, green: 0, blue: 0)
    static let textBaseDark = Color(red: 1, green: 1, blue: 1)
    static let codeCardLight = Color(red: 246.0 / 255.0, green: 246.0 / 255.0, blue: 246.0 / 255.0)
    static let codeCardDark = Color(red: 40.0 / 255.0, green: 40.0 / 255.0, blue: 40.0 / 255.0).opacity(0.6)
    static let pinnedLight = Color(red: 249.0 / 255.0, green: 236.0 / 255.0, blue: 1)
    static let pinnedDark = Color(red: 57.0 / 255.0, green: 12.0 / 255.0, blue: 79.0 / 255.0)
    static let fillFaintLight = Color.black.opacity(0.04)
    static let fillFaintDark = Color.white.opacity(0.12)

    /// Phone card corner radius in `code_widget.dart`.
    static let cardCornerRadius: CGFloat = 8
}

struct EnteWatchPalette {
    let scheme: ColorScheme

    var isDark: Bool { scheme == .dark }

    var backgroundBase: Color {
        isDark ? EnteWatchColor.backgroundBaseDark : EnteWatchColor.backgroundBaseLight
    }

    var textBase: Color {
        isDark ? EnteWatchColor.textBaseDark : EnteWatchColor.textBaseLight
    }

    var codeCard: Color {
        isDark ? EnteWatchColor.codeCardDark : EnteWatchColor.codeCardLight
    }

    var pinnedFill: Color {
        isDark ? EnteWatchColor.pinnedDark : EnteWatchColor.pinnedLight
    }

    var track: Color {
        isDark ? EnteWatchColor.fillFaintDark : EnteWatchColor.fillFaintLight
    }
}

/// Phone timer rule from `CodeTimerProgress`: warning when the remaining
/// fraction is `<= 0.4`. The watch next-code hint is a separate rule
/// (`remainingSeconds <= 5`) from the watch spec; the phone shows next for
/// the whole period.
enum CodeTimerStyle {
    static let warningFraction = 0.4

    static func usesWarningColor(remainingSeconds: Int, period: Int) -> Bool {
        guard period > 0 else { return false }
        let span = min(max(remainingSeconds, 0), period)
        return Double(span) / Double(period) <= warningFraction
    }

    static func color(remainingSeconds: Int, period: Int) -> Color {
        usesWarningColor(remainingSeconds: remainingSeconds, period: period)
            ? EnteWatchColor.timerWarning
            : EnteWatchColor.primary700
    }

    static func fraction(remainingSeconds: Int, period: Int) -> CGFloat {
        guard period > 0 else { return 0 }
        let span = min(max(remainingSeconds, 0), period)
        return CGFloat(span) / CGFloat(period)
    }
}

/// Wrist-down and Always On dimming both hide codes. `.privacySensitive()` is the
/// system redaction; this flag also removes the digits from the view tree.
enum WatchPrivacyMask {
    static func hidesSecrets(isActive: Bool, isLuminanceReduced: Bool) -> Bool {
        !isActive || isLuminanceReduced
    }
}

enum NextCodeHint {
    /// Visible only in the last five seconds. At 6 the label is absent; at 5 it is shown.
    static func isVisible(remainingSeconds: Int, nextIsEmpty: Bool) -> Bool {
        remainingSeconds <= 5 && !nextIsEmpty
    }
}

/// Phone faces from `ente_components` `TextStyles` and `ente_theme_data.dart`.
/// Sizes are smaller than the phone so the same faces fit the watch.
/// Digits stay on the system monospaced face.
enum EnteWatchType {
    /// `TextStyles.h1`: Inter, weight 700. File `Inter-Bold.ttf`.
    static func headline(_ size: CGFloat = 16) -> Font {
        .custom("Inter-Bold", size: size)
    }

    /// Issuer line is `titleLarge`: Inter, weight 600. File `Inter-SemiBold.ttf`.
    static func semibold(_ size: CGFloat = 14) -> Font {
        .custom("Inter-SemiBold", size: size)
    }

    /// Account and body copy: Inter, weight 500. File `Inter-Medium.ttf`.
    static func body(_ size: CGFloat = 12) -> Font {
        .custom("Inter-Medium", size: size)
    }
}

/// Phone home title is `AuthLogoWidget`: `assets/svg/app-logo.svg`, height 18,
/// tinted with `textBase`. That file is the word "Auth", not the Ente mark.
/// The watch image is that SVG rasterized in black so template tint can follow
/// light and dark.
struct AuthWordmark: View {
    var height: CGFloat = 15

    var body: some View {
        Image("AuthWordmark")
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: height * 53 / 18, height: height)
            .accessibilityLabel("Auth")
    }
}

/// Settings footer from `MoreFromEnteSection` / `_MoreFromEnteBrand`.
/// The phone brand is text plus the wordmark, with no tap, URL, or route.
/// "More from" is Gochi Hand at 26.279, letter-spacing -1.0512, color
/// `purpleDefault` `#9610D6`. The wordmark is
/// `packages/ente_components/assets/ente_wordmark.svg` at 62×18.43, tinted
/// with `textBase` (black in light, white in dark). The catalog images are
/// that stack rasterized with those colors.
struct MoreFromEnteMark: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(colorScheme == .dark ? "MoreFromEnteDark" : "MoreFromEnteLight")
            .renderingMode(.original)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 80)
            .accessibilityLabel("More from ente")
    }
}

enum WatchListCopy {
    static let emptyTitle = "No accounts yet"
    static let emptyDetail = "Pin an account, or tag #watch, on iPhone."
    static let passcodeTitle = "Passcode required"
    static let lockedTitle = "Watch is locked"
    static let lockedDetail = "Raise your wrist to show codes."
}

/// VoiceOver strings. A shielded row names the issuer and account and does not include the OTP.
enum TokenRowAccessibility {
    static func shieldedLabel(issuer: String, account: String) -> String {
        var parts: [String] = []
        let issuerText = issuer.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountText = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if !issuerText.isEmpty { parts.append(issuerText) }
        if !accountText.isEmpty { parts.append(accountText) }
        if parts.isEmpty { parts.append("Account") }
        parts.append("Hidden code")
        return parts.joined(separator: ", ")
    }

    static func codeLabel(masked: Bool, code: String) -> String {
        masked ? "Hidden code" : code
    }
}
