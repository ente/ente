import SwiftUI

struct FlowLayout: Layout {
    var spacing: CGFloat = EnsuSpacing.sm

    private func childSize(for subview: LayoutSubview, maxWidth: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        if ideal.width > maxWidth {
            return subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
        }
        return ideal
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = childSize(for: subview, maxWidth: maxWidth)
            let nextWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width

            if nextWidth > maxWidth && rowWidth > 0 {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, rowWidth)
                rowWidth = 0
                rowHeight = 0
            }

            rowWidth = rowWidth == 0 ? size.width : rowWidth + spacing + size.width
            rowHeight = max(rowHeight, size.height)
        }

        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, rowWidth)

        let finalWidth = maxWidth.isInfinite ? maxRowWidth : min(maxWidth, maxRowWidth)
        return CGSize(width: finalWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { childSize(for: $0, maxWidth: bounds.width) }

        struct RowItem {
            let index: Int
            let size: CGSize
            let x: CGFloat
        }
        var rows: [[RowItem]] = []
        var currentRow: [RowItem] = []
        var x: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            if x + size.width > bounds.width && !currentRow.isEmpty {
                rows.append(currentRow)
                currentRow = []
                x = 0
            }

            currentRow.append(RowItem(index: index, size: size, x: x))
            x += size.width + spacing
        }
        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        var y = bounds.minY
        for row in rows {
            let rowHeight = row.map(\.size.height).max() ?? 0
            for item in row {
                let yOffset = (rowHeight - item.size.height) / 2
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: y + yOffset),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
            }
            y += rowHeight + spacing
        }
    }
}
