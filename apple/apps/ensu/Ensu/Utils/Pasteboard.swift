import Foundation

import UIKit

@MainActor
func copyToPasteboard(_ value: String) {
    UIPasteboard.general.string = value
}
