import CoreText
import SwiftUI

// SwiftUI App lifecycle: no WKExtensionDelegate and no storyboard.
// Bundle id, companion id, and display name belong on the watch target as
// INFOPLIST_KEY_CFBundleIdentifier, INFOPLIST_KEY_WKCompanionAppBundleIdentifier,
// and INFOPLIST_KEY_CFBundleDisplayName. Generate the plist from build settings.

@main
struct EnteAuthWatchApp: App {
    init() {
        EnteWatchFonts.register()
        // Activate before the list appears so a context delivered at launch
        // is applied. TokenListView also activates when the scene is shown.
        #if DEBUG
        _ = WatchSessionManager.shared.installScreenshotFixtureIfNeeded()
        #endif
        WatchSessionManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            TokenListView()
        }
    }
}

#if DEBUG
/// Debug screenshot and UI-test launch. Reads `-ente-screenshot <mode>` only.
/// The mode is a screen name. It is not stored, and it is not a seed.
enum ScreenshotLaunch {
    static func mode() -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-ente-screenshot"), index + 1 < args.count else {
            return nil
        }
        let value = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    static var shieldsCodes: Bool {
        mode() == "shielded"
    }
}
#endif

/// Inter files from `mobile/apps/auth/fonts`, the same faces `pubspec.yaml` registers.
/// PostScript names: Inter-Regular, Inter-Medium, Inter-SemiBold, Inter-Bold.
enum EnteWatchFonts {
    static let fileNames = ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold"]

    static func register() {
        for name in fileNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
