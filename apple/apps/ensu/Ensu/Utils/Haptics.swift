import Foundation

import UIKit

func hapticTap() {
    UIImpactFeedbackGenerator(style: .light).impactOccurred()
}

func hapticMedium() {
    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
}

func hapticHeavy() {
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
}

func hapticSuccess() {
    UINotificationFeedbackGenerator().notificationOccurred(.success)
}

func hapticWarning() {
    UINotificationFeedbackGenerator().notificationOccurred(.warning)
}

func hapticError() {
    UINotificationFeedbackGenerator().notificationOccurred(.error)
}

