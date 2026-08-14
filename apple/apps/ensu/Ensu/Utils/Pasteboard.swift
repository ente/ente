import Foundation

import UIKit

func copyToPasteboard(_ value: String) {
    UIPasteboard.general.string = value
}
