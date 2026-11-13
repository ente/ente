import SwiftUI

public struct SettingsFooter<Links: View>: View {
    @Environment(\.entePalette) private var palette
    private let version: String
    private let links: Links

    public init(version: String, @ViewBuilder links: () -> Links) {
        self.version = version
        self.links = links()
    }

    public var body: some View {
        VStack(spacing: EnteSpacing.lg) {
            links
            Text(version)
                .font(EnteTypography.mini)
                .foregroundStyle(palette.mutedText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, EnteSpacing.xl)
    }
}
