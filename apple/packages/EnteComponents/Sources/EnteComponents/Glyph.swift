import SwiftUI

enum Glyph: String {
    case back
    case chevron
    case check
    case checkRounded = "check-rounded"
    case close

    var image: Image {
        Image("component-\(rawValue)", bundle: .module)
    }
}
