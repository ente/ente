import SwiftUI

public struct SheetContent<Content: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let message: String?
    private let back: (() -> Void)?
    private let dismiss: (() -> Void)?
    private let backLabel: String
    private let dismissLabel: String
    private let content: Content

    public init(
        title: String,
        message: String? = nil,
        back: (() -> Void)? = nil,
        dismiss: (() -> Void)? = nil,
        backLabel: String = "Back",
        dismissLabel: String = "Close",
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.message = message
        self.back = back
        self.dismiss = dismiss
        self.backLabel = backLabel
        self.dismissLabel = dismissLabel
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EnteSpacing.lg) {
            SheetHeader(title) {
                if let back {
                    IconAction(kind: .circular, size: 40, action: back) {
                        Glyph.back.image.resizable().scaledToFit()
                            .frame(width: 24, height: 24)
                            .flipsForRightToLeftLayoutDirection(true)
                    }
                    .accessibilityLabel(backLabel)
                }
            } trailing: {
                if let dismiss {
                    IconAction(kind: .circular, size: 40, action: dismiss) {
                        Glyph.close.image.resizable().scaledToFit()
                            .frame(width: 18, height: 18)
                    }
                    .accessibilityLabel(dismissLabel)
                }
            }
            if let message {
                Text(message)
                    .font(EnteTypography.body)
                    .foregroundStyle(palette.mutedText)
            }
            content
        }
        .padding(EnteSpacing.xl)
        .background(palette.background)
    }
}
