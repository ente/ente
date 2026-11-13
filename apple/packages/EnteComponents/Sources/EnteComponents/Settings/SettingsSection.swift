import SwiftUI

public struct SettingsSection<Content: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String?
    private let footer: String?
    private let content: Content

    public init(
        _ title: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: EnteSpacing.sm) {
            if let title {
                Text(title)
                    .font(EnteTypography.heading2)
                    .foregroundStyle(palette.text)
                    .padding(.vertical, EnteSpacing.sm)
                    .accessibilityAddTraits(.isHeader)
            }
            content
            if let footer {
                Text(footer)
                    .font(EnteTypography.mini)
                    .foregroundStyle(palette.mutedText)
                    .padding(EnteSpacing.sm)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
