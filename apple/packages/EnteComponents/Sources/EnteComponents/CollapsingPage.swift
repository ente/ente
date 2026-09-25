import EnteFonts
import SwiftUI

public struct CollapsingPage<Actions: View, Content: View>: View {
    @Environment(\.entePalette) private var palette
    @State private var progress: CGFloat = 0
    @ScaledMetric(relativeTo: .title) private var titleHeight: CGFloat = 32
    @ScaledMetric(relativeTo: .title) private var eyebrowHeight: CGFloat = 30
    @ScaledMetric(relativeTo: .title) private var collapsedTitleHeight: CGFloat = 24
    @ScaledMetric(relativeTo: .caption) private var subtitleHeight: CGFloat = 16
    private let title: String
    private let eyebrow: String?
    private let subtitle: String?
    private let identifier: String?
    private let backLabel: String
    private let back: () -> Void
    private let actions: Actions
    private let content: Content

    public init(
        _ title: String,
        eyebrow: String? = nil,
        subtitle: String? = nil,
        identifier: String? = nil,
        backLabel: String,
        back: @escaping () -> Void,
        @ViewBuilder actions: () -> Actions = { EmptyView() },
        @ViewBuilder content: () -> Content,
    ) {
        self.title = title
        self.eyebrow = eyebrow
        self.subtitle = subtitle
        self.identifier = identifier
        self.backLabel = backLabel
        self.back = back
        self.actions = actions()
        self.content = content()
    }

    public var body: some View {
        let metrics = HeaderMetrics(
            titleHeight: titleHeight, eyebrowHeight: eyebrowHeight,
            collapsedTitleHeight: collapsedTitleHeight, subtitleHeight: subtitleHeight,
            hasEyebrow: eyebrow != nil, hasSubtitle: subtitle != nil)
        GeometryReader { viewport in
            ZStack(alignment: .top) {
                CollapsingScrollView(
                    expansion: metrics.expansion,
                    identifier: identifier.map { "\($0).scroll" },
                    onScroll: { value in
                        if progress != value { progress = value }
                    }
                ) {
                    VStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: metrics.expansion)
                        content.padding(.horizontal, EnteSpacing.lg).padding(
                            .bottom, EnteSpacing.lg)
                    }
                    .frame(
                        minHeight: max(0, viewport.size.height - metrics.toolbarHeight)
                            + metrics.expansion,
                        alignment: .top)
                }
                .padding(.top, metrics.toolbarHeight)
                .ignoresSafeArea(.container, edges: .bottom)
                CollapsingHeader(
                    progress: $progress, title: title, eyebrow: eyebrow, subtitle: subtitle,
                    identifier: identifier, backLabel: backLabel, back: back, actions: actions,
                    metrics: metrics)
            }
        }
        .foregroundStyle(palette.text)
        .background(palette.background)
    }
}

private struct CollapsingHeader<Actions: View>: View {
    @Environment(\.entePalette) private var palette
    @Binding var progress: CGFloat
    let title: String
    let eyebrow: String?
    let subtitle: String?
    let identifier: String?
    let backLabel: String
    let back: () -> Void
    let actions: Actions
    let metrics: HeaderMetrics

    var body: some View {
        let eased = headerEase(progress, firstControlX: 0.42, secondControlX: 0.58)
        let titleTop =
            metrics.contentTop
            + ((metrics.toolbarHeight - metrics.collapsedTitleHeight) / 2 - metrics.contentTop)
            * eased
        let titleHeight =
            metrics.expandedTitleHeight
            + (metrics.collapsedTitleHeight - metrics.expandedTitleHeight) * eased
        let rowHeight = max(metrics.toolbarHeight, titleHeight)
        ZStack(alignment: .topLeading) {
            IconAction(kind: .unfilled, size: 48, action: back) {
                Glyph.back.image.resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .flipsForRightToLeftLayoutDirection(true)
            }
            .frame(height: metrics.toolbarHeight)
            .padding(.leading, 4)
            .accessibilityLabel(backLabel)
            .accessibilityIdentifier(identifier.map { "\($0).back" } ?? "")
            HStack(spacing: EnteSpacing.sm) {
                titleView(progress: eased)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: titleHeight, alignment: .top)
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier(identifier.map { "\($0).title" } ?? "")
                actions
            }
            .frame(height: rowHeight)
            .padding(.leading, EnteSpacing.lg + 36 * eased)
            .padding(.trailing, EnteSpacing.lg)
            .offset(y: titleTop - (rowHeight - titleHeight) / 2)
            if let subtitle {
                Text(subtitle)
                    .font(EnteTypography.mini)
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(2)
                    .padding(.leading, EnteSpacing.lg + 36 * eased)
                    .padding(.trailing, EnteSpacing.lg)
                    .offset(y: metrics.contentTop + metrics.expandedTitleHeight + 2)
                    .opacity(1 - eased)
                    .accessibilityHidden(progress >= 0.99)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: metrics.expandedHeight - metrics.expansion * progress, alignment: .top)
        .clipped()
        .background(palette.background)
    }

    @ViewBuilder
    private func titleView(progress: CGFloat) -> some View {
        if let eyebrow {
            HeaderTitleLayout(progress: progress, eyebrowHeight: metrics.eyebrowHeight) {
                Text(eyebrow)
                    .font(EnteFont.outfit(size: 16 + 4 * progress, relativeTo: .title))
                    .foregroundStyle(palette.mutedText)
                    .lineLimit(1)
                Text(title)
                    .font(EnteFont.outfit(size: 24 - 4 * progress, relativeTo: .title))
                    .lineLimit(1)
            }
        } else {
            Text(title)
                .font(EnteFont.outfit(size: 24 - 4 * progress, relativeTo: .title))
                .lineLimit(1)
        }
    }
}

private struct HeaderMetrics {
    let titleHeight: CGFloat
    let eyebrowHeight: CGFloat
    let collapsedTitleHeight: CGFloat
    let subtitleHeight: CGFloat
    let hasEyebrow: Bool
    let hasSubtitle: Bool

    var toolbarHeight: CGFloat { max(56, collapsedTitleHeight) }
    var expandedTitleHeight: CGFloat { titleHeight + (hasEyebrow ? eyebrowHeight : 0) }
    var expandedHeight: CGFloat {
        max(
            hasSubtitle ? 110 : 92,
            48 + expandedTitleHeight + (hasSubtitle ? 2 + subtitleHeight * 2 : 0) + 16)
    }
    var expansion: CGFloat { expandedHeight - toolbarHeight }
    var contentTop: CGFloat {
        48 + (hasSubtitle ? min(subtitleHeight, max(0, toolbarHeight - expandedTitleHeight)) : 0)
    }
}

private struct HeaderTitleLayout: Layout {
    let progress: CGFloat
    let eyebrowHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let title = subviews[1].sizeThatFits(proposal)
        return CGSize(
            width: proposal.width ?? title.width,
            height: title.height + eyebrowHeight * (1 - progress))
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let prefixWidth = min(
            subviews[0].sizeThatFits(.unspecified).width + 6, max(0, bounds.width - 24))
        let horizontal = headerEase(progress, firstControlX: 0, secondControlX: 0.58)
        let titleX = prefixWidth * horizontal
        let titleY =
            eyebrowHeight * (1 - headerEase(progress, firstControlX: 0.42, secondControlX: 1))
        subviews[0].place(
            at: bounds.origin,
            proposal: ProposedViewSize(
                width: bounds.width + (max(0, prefixWidth - 6) - bounds.width) * horizontal,
                height: nil))
        subviews[1].place(
            at: CGPoint(x: bounds.minX + titleX, y: bounds.minY + titleY),
            proposal: ProposedViewSize(width: bounds.width - titleX, height: nil))
    }
}

private func headerEase(_ progress: CGFloat, firstControlX: CGFloat, secondControlX: CGFloat)
    -> CGFloat
{
    if progress <= 0 { return 0 }
    if progress >= 1 { return 1 }
    var lower: CGFloat = 0
    var upper: CGFloat = 1
    for _ in 0..<14 {
        let t = (lower + upper) / 2
        let remaining = 1 - t
        let x =
            3 * remaining * remaining * t * firstControlX
            + 3 * remaining * t * t * secondControlX + t * t * t
        if x < progress {
            lower = t
        } else {
            upper = t
        }
    }
    let t = (lower + upper) / 2
    return t * t * (3 - 2 * t)
}
