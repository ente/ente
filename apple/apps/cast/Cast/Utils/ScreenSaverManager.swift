import Foundation
import UIKit

@MainActor
class ScreenSaverManager: ObservableObject {
    private static let shared = ScreenSaverManager()
    private var isDisabled = false
    private var refreshTimer: Timer?

    static func preventScreenSaver() {
        shared.startPrevention()
    }

    static func allowScreenSaver() {
        shared.stopPrevention()
    }

    private func startPrevention() {
        guard !isDisabled else {
            return
        }

        UIApplication.shared.isIdleTimerDisabled = true
        isDisabled = true

        // Fallback for problematic tvOS versions where isIdleTimerDisabled doesn't work reliably
        // This timer periodically refreshes the setting to ensure it stays disabled
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { _ in
            UIApplication.shared.isIdleTimerDisabled = false
            UIApplication.shared.isIdleTimerDisabled = true
        }
    }

    private func stopPrevention() {
        guard isDisabled else {
            return
        }

        refreshTimer?.invalidate()
        refreshTimer = nil
        UIApplication.shared.isIdleTimerDisabled = false
        isDisabled = false
    }

    static func cleanup() {
        shared.stopPrevention()
    }
}
