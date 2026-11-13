import EnteFonts
import SwiftUI

public struct IllustratedPage<Illustration: View, Actions: View, Footer: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let message: String
    private let illustration: Illustration
    private let actions: Actions
    private let footer: Footer

    public init(
        _ title: String,
        message: String,
        @ViewBuilder illustration: () -> Illustration,
        @ViewBuilder actions: () -> Actions,
        @ViewBuilder footer: () -> Footer,
    ) {
        self.title = title
        self.message = message
        self.illustration = illustration()
        self.actions = actions()
        self.footer = footer()
    }

    public var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    illustration
                        .frame(height: min(220, geometry.size.height * 0.28))
                        .accessibilityHidden(true)
                    Text(title)
                        .font(EnteFont.outfit(size: 32, relativeTo: .largeTitle))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .font(EnteTypography.body)
                        .foregroundStyle(palette.mutedText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, EnteSpacing.lg)
                    actions
                    footer.font(EnteTypography.mini).foregroundStyle(palette.mutedText)
                }
                .padding(EnteSpacing.lg)
                .frame(maxWidth: 480)
                .frame(minHeight: geometry.size.height)
                .frame(maxWidth: .infinity)
            }
        }
        .foregroundStyle(palette.text)
    }
}
