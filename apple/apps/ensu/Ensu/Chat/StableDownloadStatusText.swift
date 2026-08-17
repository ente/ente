import SwiftUI

struct StableDownloadStatusText: View {
    let text: String
    let font: Font
    let color: Color

    private var widestText: String {
        guard text.hasPrefix("Downloading... "), let slashRange = text.range(of: " / ") else {
            return text
        }
        return "Downloading... 999.9 MB / \(text[slashRange.upperBound...])"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Text(widestText)
                .hidden()
                .accessibilityHidden(true)
            Text(text)
        }
        .font(font)
        .monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1)
    }
}
