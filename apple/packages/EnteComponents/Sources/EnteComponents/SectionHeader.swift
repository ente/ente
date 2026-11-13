import EnteFonts
import SwiftUI

public struct SectionHeader: View {
    @Environment(\.entePalette) private var palette
    @Environment(\.isEnabled) private var enabled
    private let title: String
    private let action: (() -> Void)?

    public init(_ title: String, action: (() -> Void)? = nil) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Group {
            if let action {
                Button(action: action) { content }
                    .buttonStyle(.plain)
            } else {
                content
            }
        }
        .accessibilityAddTraits(.isHeader)
    }

    private var content: some View {
        HStack(spacing: 0) {
            Text(title)
                .font(EnteFont.outfit(size: 20, relativeTo: .title2))
                .foregroundStyle(enabled ? palette.text : palette.disabledText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if action != nil {
                Glyph.chevron.image.resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .flipsForRightToLeftLayoutDirection(true)
                    .frame(width: 38, height: 38)
                    .foregroundStyle(enabled ? palette.mutedText : palette.disabledText)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
