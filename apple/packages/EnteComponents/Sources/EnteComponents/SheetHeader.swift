import EnteFonts
import SwiftUI

public struct SheetHeader<Leading: View, Trailing: View>: View {
    @Environment(\.entePalette) private var palette
    private let title: String
    private let leading: Leading
    private let trailing: Trailing

    public init(
        _ title: String,
        @ViewBuilder leading: () -> Leading = { EmptyView() },
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: EnteSpacing.md) {
            leading
            Text(title)
                .font(EnteFont.inter(size: 18, weight: .semibold, relativeTo: .title3))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            trailing
        }
        .foregroundStyle(palette.text)
    }
}
