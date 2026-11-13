import Foundation

import UIKit

@MainActor
func hapticTap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

@MainActor
func hapticMedium() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

@MainActor
func hapticHeavy() {
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
}

@MainActor
func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

@MainActor
func hapticWarning() {
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
}

@MainActor
func hapticError() {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
}
