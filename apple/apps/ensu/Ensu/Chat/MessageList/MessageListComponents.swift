import SwiftUI
import QuickLook
import UIKit

struct BottomOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AttachmentPreviewItem: Identifiable {
    let url: URL
    var name: String = ""
    var id: String { url.path }
}

struct ImageAttachmentPreview: View {
    let url: URL
    let accessibilityLabel: String
    let onDismiss: () -> Void

    @State private var image: UIImage?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black.opacity(0.94)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hapticTap()
                        onDismiss()
                    }

                if let image {
                    let size = fittedPreviewSize(
                        imageSize: image.size,
                        containerSize: proxy.size,
                        padding: EnsuSpacing.md
                    )

                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: size.width, height: size.height)
                        .contentShape(Rectangle())
                        .onTapGesture {}
                        .accessibilityLabel(accessibilityLabel)
                } else {
                    Image("Attachment01Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 32, height: 32)
                        .foregroundStyle(.white.opacity(0.7))
                        .accessibilityLabel(accessibilityLabel)
                }

                Button(action: {
                    hapticTap()
                    onDismiss()
                }) {
                    Image("Cancel01Icon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .frame(width: 32, height: 32)
                .background(.black.opacity(0.35))
                .clipShape(Circle())
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(EnsuSpacing.lg)
                .accessibilityLabel("Close image preview")
            }
        }
        .ignoresSafeArea()
        .onAppear {
            image = UIImage(contentsOfFile: url.path)
        }
    }

    private func fittedPreviewSize(imageSize: CGSize, containerSize: CGSize, padding: CGFloat)
        -> CGSize
    {
        let availableWidth = max(0, containerSize.width - (padding * 2))
        let availableHeight = max(0, containerSize.height - (padding * 2))

        guard imageSize.width > 0, imageSize.height > 0, availableWidth > 0, availableHeight > 0
        else {
            return .zero
        }

        let imageAspect = imageSize.width / imageSize.height
        let availableAspect = availableWidth / availableHeight
        if imageAspect >= availableAspect {
            return CGSize(width: availableWidth, height: availableWidth / imageAspect)
        }
        return CGSize(width: availableHeight * imageAspect, height: availableHeight)
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        context.coordinator.url = url
        uiViewController.reloadData()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int)
            -> QLPreviewItem
        {
            url as NSURL
        }
    }
}

struct UserMessageBubbleView: View {
    let message: RenderedChatMessage
    let onEdit: () -> Void
    let onCopy: () -> Void
    let onBranchChange: (Int) -> Void
    let onOpenAttachment: (ChatAttachment) -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let bubbleShape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let bubbleFill = colorScheme == .dark ? EnsuColor.fillFaint : EnsuColor.border.opacity(0.2)

        HStack(alignment: .bottom) {
            Spacer(minLength: EnsuSpacing.messageBubbleInset)

            VStack(alignment: .trailing, spacing: EnsuSpacing.sm) {
                if !message.attachments.isEmpty {
                    FlowLayout(spacing: EnsuSpacing.sm) {
                        ForEach(message.attachments) { attachment in
                            if attachment.kind == .image, attachment.url != nil {
                                ImageAttachmentThumbnail(
                                    url: attachment.url,
                                    accessibilityLabel: attachment.name,
                                    width: 164,
                                    height: 124,
                                    portraitWidth: 124,
                                    portraitHeight: 164,
                                    squareSize: 140,
                                    isUploading: attachment.isUploading
                                )
                                .onTapGesture {
                                    hapticTap()
                                    onOpenAttachment(attachment)
                                }
                            } else {
                                AttachmentChip(
                                    name: attachment.name,
                                    size: attachment.url == nil
                                        ? "Unavailable on this device"
                                        : attachment.formattedSize,
                                    icon: attachment.iconName,
                                    isUploading: attachment.isUploading
                                )
                                .onTapGesture {
                                    hapticTap()
                                    onOpenAttachment(attachment)
                                }
                                .allowsHitTesting(attachment.url != nil)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .trailing, spacing: EnsuSpacing.sm) {
                    Text(message.text)
                        .font(EnsuTypography.message)
                        .foregroundStyle(EnsuColor.userMessageText)
                        .lineSpacing(EnsuLineHeight.spacing(fontSize: 15, lineHeight: 22.0 / 15))
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)
                }
                .padding(EnsuSpacing.md)
                .background(bubbleFill)
                .clipShape(bubbleShape)
                .contextMenu {
                    Button("Edit") {
                        hapticTap()
                        onEdit()
                    }
                    Button("Copy") {
                        hapticTap()
                        onCopy()
                    }
                }

                HStack(spacing: EnsuSpacing.sm) {
                    Spacer()
                    if message.branchCount > 1 {
                        BranchSwitcherView(
                            currentIndex: message.branchIndex,
                            totalCount: message.branchCount,
                            onPrevious: { onBranchChange(-1) },
                            onNext: { onBranchChange(1) }
                        )
                    }
                    TimestampView(date: message.timestamp)
                }
            }
        }
    }
}

struct AssistantMessageBubbleView: View {
    let message: RenderedChatMessage
    let isLastMessage: Bool
    let onCopy: () -> Void
    let onRetry: () -> Void
    let onBranchChange: (Int) -> Void
    let onOpenAttachment: (ChatAttachment) -> Void
    let showsMetadata: Bool

    @State private var showSources = false

    var body: some View {
        let parsed = parseGroundedAssistantText(storedText: message.text)
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                    AssistantMessageRenderer(
                        text: parsed.text, isStreaming: false, storageId: message.id.uuidString)

                    if !parsed.sourceLabels.isEmpty {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: EnsuSpacing.sm) { sourceChips(parsed.sourceLabels) }
                            VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                                sourceChips(parsed.sourceLabels)
                            }
                        }
                    }

                    if message.isInterrupted {
                        Text("Interrupted")
                            .font(EnsuTypography.small)
                            .italic()
                            .foregroundStyle(EnsuColor.textMuted)
                    }
                }
                .padding(.vertical, EnsuSpacing.md)
                .padding(.horizontal, EnsuSpacing.sm)
                .contextMenu {
                    if !message.isSynthetic {
                        Button("Copy") {
                            hapticTap()
                            onCopy()
                        }
                    }
                    if !message.isSynthetic || isLastMessage {
                        Button("Retry") {
                            hapticMedium()
                            onRetry()
                        }
                    }
                }

                if showsMetadata && !message.isSynthetic {
                    HStack(spacing: EnsuSpacing.sm) {
                        TimestampView(date: message.timestamp)
                        if message.branchCount > 1 {
                            BranchSwitcherView(
                                currentIndex: message.branchIndex,
                                totalCount: message.branchCount,
                                onPrevious: { onBranchChange(-1) },
                                onNext: { onBranchChange(1) }
                            )
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, EnsuSpacing.sm)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.22), value: showsMetadata)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showSources) {
            KnowledgeSourcesSheet(citations: parsed.sources)
        }
    }

    private func sourceChips(_ labels: [String]) -> some View {
        ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
            Button {
                showSources = true
            } label: {
                Text(label)
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .padding(.horizontal, EnsuSpacing.md)
                    .padding(.vertical, EnsuSpacing.sm)
                    .frame(minHeight: 44)
                    .background(EnsuColor.fillFaint)
                    .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.button))
            }
            .buttonStyle(.plain)
            .accessibilityHint("View sources used in this response")
        }
    }
}

private struct KnowledgeSourcesSheet: View {
    let citations: [GroundedSource]
    @EnvironmentObject private var notes: NotesStore

    var body: some View {
        AttributionSheet(title: "Sources") {
            if hasLocalNotes, let error = notes.operationError {
                Text(error)
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.error)
            }
            ForEach(Array(citations.enumerated()), id: \.offset) { index, source in
                EnsuCard(padding: EnsuSpacing.md) {
                    Text(sourceHeader(source, number: index + 1))
                        .font(EnsuTypography.mini)
                        .foregroundStyle(EnsuColor.textMuted)

                    Text(sourceTitle(source))
                        .font(EnsuTypography.large)
                        .foregroundStyle(EnsuColor.textPrimary)

                    if case .localNote(let reference) = source, let section = reference.section {
                        Text(section)
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)
                    }

                    Divider()

                    switch source {
                    case .localNote(let reference):
                        Text(reference.documentId)
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)
                        Button {
                            notes.open(reference)
                        } label: {
                            Label("Open note", systemImage: "arrow.up.right.square")
                                .frame(minHeight: 44)
                        }
                        .font(EnsuTypography.small)
                    case .ensuPack(let citation):
                        Text(citation.credit)
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: EnsuSpacing.lg) { sourceLinks(citation) }
                            VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                                sourceLinks(citation)
                            }
                        }
                        .font(EnsuTypography.small)
                    }
                }
            }
        }
        .sheet(item: $notes.preview) { preview in NotesPreviewView(url: preview.url) }
    }

    private var hasLocalNotes: Bool {
        citations.contains {
            if case .localNote = $0 { return true }
            return false
        }
    }

    private func sourceHeader(_ source: GroundedSource, number: Int) -> String {
        switch source {
        case .localNote(let reference):
            return "SOURCE \(number) · YOUR NOTES"
                + (reference.collectionLabel.map { " · \($0.uppercased())" } ?? "")
        case .ensuPack(let citation):
            return "SOURCE \(number) · ENSU PACK · \(citation.datasetLabel.uppercased())"
        }
    }

    private func sourceTitle(_ source: GroundedSource) -> String {
        switch source {
        case .localNote(let reference): return reference.title
        case .ensuPack(let citation): return citation.title
        }
    }

    @ViewBuilder
    private func sourceLinks(_ citation: SourceCitation) -> some View {
        if let sourceUrl = URL(string: citation.sourceUrl) {
            Link(destination: sourceUrl) {
                Label("Open source", systemImage: "arrow.up.right.square")
                    .frame(minHeight: 44)
            }
        }
        if let licenseUrl = URL(string: citation.licenseUrl) {
            Link(destination: licenseUrl) {
                Label(citation.licenseLabel, systemImage: "arrow.up.right.square")
                    .frame(minHeight: 44)
            }
        }
    }

}

private enum StreamingCursor {
    static let glyph = "▍"
}

struct StreamingBubbleView: View {
    let text: String
    let isGenerating: Bool

    @State private var storageId = UUID().uuidString
    @State private var renderedText = ""

    var body: some View {
        let hasText =
            isGenerating && !renderedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let bubbleVerticalPadding = hasText ? EnsuSpacing.md : 0
        let contentSpacing = hasText ? EnsuSpacing.sm : 0

        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: contentSpacing) {
                if hasText {
                    TimelineView(.periodic(from: .now, by: 0.55)) { context in
                        let phase = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2
                        let showCursor = phase == 0
                        AssistantMessageRenderer(
                            text: renderedText,
                            isStreaming: true,
                            storageId: storageId,
                            showsCursor: showCursor
                        )
                    }
                }

                TimelineView(.periodic(from: .now, by: 0.42)) { context in
                    let step = Int(context.date.timeIntervalSinceReferenceDate / 0.42)
                    let count = (step % 3) + 1
                    Text(String(repeating: ".", count: count))
                        .font(EnsuTypography.message)
                        .monospaced()
                        .foregroundStyle(EnsuColor.textMuted)
                        .frame(minWidth: 24, alignment: .leading)
                }
            }
            .padding(.vertical, bubbleVerticalPadding)
            .padding(.horizontal, EnsuSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(EnsuColor.textPrimary)
        .onAppear {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                renderedText = text
            } else if isGenerating {
                renderedText = ""
            }
        }
        .onChange(of: text) { newValue in
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                renderedText = newValue
                return
            }
            if isGenerating {
                renderedText = ""
            }
        }
        .onChange(of: isGenerating) { generating in
            if !generating {
                renderedText = ""
            } else if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                renderedText = ""
            }
        }
    }
}

struct TimestampView: View {
    let date: Date

    var body: some View {
        Text(Self.formatter.string(from: date))
            .font(EnsuTypography.mini)
            .foregroundStyle(EnsuColor.textMuted)
            .monospacedDigit()
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()
}

struct BranchSwitcherView: View {
    let currentIndex: Int
    let totalCount: Int
    let onPrevious: () -> Void
    let onNext: () -> Void

    var body: some View {
        if totalCount > 1 {
            HStack(spacing: EnsuSpacing.sm) {
                TextActionButton(text: "<", action: onPrevious)
                    .disabled(currentIndex <= 1)
                Text(String(format: "%2d/%d", currentIndex, totalCount))
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)
                    .monospacedDigit()
                TextActionButton(text: ">", action: onNext)
                    .disabled(currentIndex >= totalCount)
            }
        }
    }
}

struct AssistantMessageRenderer: View {
    let text: String
    let isStreaming: Bool
    let storageId: String
    var showsCursor: Bool = false

    @State private var parsedMessage: ParsedMessage
    @State private var cachedText: String

    init(text: String, isStreaming: Bool, storageId: String, showsCursor: Bool = false) {
        self.text = text
        self.isStreaming = isStreaming
        self.storageId = storageId
        self.showsCursor = showsCursor
        let parsed = ParsedMessage(text: text)
        _parsedMessage = State(initialValue: parsed)
        _cachedText = State(initialValue: text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: EnsuSpacing.lg) {
            ForEach(parsedMessage.todoBlocks) { block in
                TodoListCardView(title: block.title, status: block.status, items: block.items)
            }

            if !parsedMessage.markdownBlocks.isEmpty || showsCursor {
                MarkdownView(blocks: parsedMessage.markdownBlocks, showCursor: showsCursor)
            }
        }
        .onChange(of: text) { newValue in
            guard newValue != cachedText else { return }
            cachedText = newValue
            parsedMessage = ParsedMessage(text: newValue)
        }
    }
}

struct ParsedMessage {
    struct TodoBlock: Identifiable {
        let id = UUID()
        let title: String
        let status: String?
        let items: [String]
    }

    let todoBlocks: [TodoBlock]
    let markdown: String
    let markdownBlocks: [MarkdownBlock]

    init(text: String) {
        var remaining = text
        var todos: [TodoBlock] = []

        let thinkMatches = ParsedMessage.extractTags(
            using: ChatMessageTagRegex.think, from: remaining)
        remaining = thinkMatches.cleaned

        let todoMatches = ParsedMessage.extractTags(
            using: ChatMessageTagRegex.todoList, from: remaining)
        remaining = todoMatches.cleaned

        for content in todoMatches.contents {
            if let data = content.data(using: .utf8),
                let payload = try? JSONDecoder().decode(TodoPayload.self, from: data)
            {
                todos.append(
                    TodoBlock(title: payload.title, status: payload.status, items: payload.items))
            }
        }

        self.todoBlocks = todos
        self.markdown = remaining
        self.markdownBlocks = MarkdownParser.parse(remaining)
    }

    private static func extractTags(using regex: NSRegularExpression?, from text: String) -> (
        contents: [String], cleaned: String
    ) {
        guard let regex else {
            return ([], text)
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let contents: [String] = matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        let cleaned = regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
        return (contents, cleaned)
    }

    private struct TodoPayload: Decodable {
        let title: String
        let status: String?
        let items: [String]
    }
}

struct TodoListCardView: View {
    let title: String
    let status: String?
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
            HStack {
                Text(title)
                    .font(EnsuFont.message(size: 14, weight: .semibold))
                    .foregroundStyle(EnsuColor.textPrimary)
                Spacer()
                Text("\(items.count)")
                    .font(EnsuTypography.small)
                    .foregroundStyle(EnsuColor.textMuted)
            }

            if let status {
                Text(status)
                    .font(EnsuFont.message(size: 12.5, weight: .regular))
                    .foregroundStyle(EnsuColor.textMuted)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: EnsuSpacing.sm) {
                        Circle()
                            .fill(EnsuColor.accent)
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        Text(item)
                            .font(EnsuFont.message(size: 14, weight: .regular))
                            .foregroundStyle(EnsuColor.textPrimary)
                            .lineSpacing(EnsuLineHeight.spacing(fontSize: 14, lineHeight: 1.5))
                    }
                }
            }
        }
        .padding(EnsuSpacing.cardPadding)
        .background(EnsuColor.fillFaint)
        .overlay(
            RoundedRectangle(cornerRadius: EnsuCornerRadius.card)
                .stroke(EnsuColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.card, style: .continuous))
    }
}

struct MarkdownView: View {
    let blocks: [MarkdownBlock]
    var showCursor: Bool = false

    private let messageLineSpacing = EnsuLineHeight.spacing(fontSize: 15, lineHeight: 22.0 / 15)

    var body: some View {
        let lastKind = blocks.last?.kind
        let inlineCursorSupported =
            lastKind.map { kind in
                switch kind {
                case .heading, .paragraph, .blockquote, .list:
                    return true
                case .code, .math, .divider:
                    return false
                }
            } ?? false
        let showTrailingCursor = showCursor && (!inlineCursorSupported || blocks.isEmpty)

        VStack(alignment: .leading, spacing: EnsuSpacing.md) {
            ForEach(blocks, id: \.id) { (block: MarkdownBlock) in
                let isLast = block.id == (blocks.last?.id ?? -1)
                switch block.kind {
                case .heading(let level, let text):
                    let displayText =
                        showCursor && isLast ? text.appending(StreamingCursor.glyph) : text
                    if displayText.hasMath {
                        InlineMathTextView(
                            text: displayText,
                            fonts: InlineFontSet(
                                normal: headingFont(for: level),
                                code: EnsuFont.code(
                                    size: headingFontSize(for: level), weight: .semibold),
                                mathSize: headingFontSize(for: level)
                            ),
                            textColor: EnsuColor.textPrimary
                        )
                    } else {
                        Text(displayText.attributedText)
                            .font(headingFont(for: level))
                            .foregroundStyle(EnsuColor.textPrimary)
                    }
                case .paragraph(let text):
                    let displayText =
                        showCursor && isLast ? text.appending(StreamingCursor.glyph) : text
                    if displayText.hasMath {
                        InlineMathTextView(
                            text: displayText,
                            fonts: messageInlineFonts,
                            textColor: EnsuColor.textPrimary
                        )
                    } else {
                        Text(displayText.attributedText)
                            .font(EnsuTypography.message)
                            .foregroundStyle(EnsuColor.textPrimary)
                            .lineSpacing(messageLineSpacing)
                    }
                case .blockquote(let text):
                    let displayText =
                        showCursor && isLast ? text.appending(StreamingCursor.glyph) : text
                    BlockQuoteView(text: displayText)
                case .code(let code):
                    CodeBlockView(code: code)
                case .math(let text):
                    MathBlockView(text: text)
                case .list(let items):
                    let resolvedItems =
                        (showCursor && isLast)
                        ? items.enumerated().map { offset, item in
                            offset == items.count - 1 ? item.appending(StreamingCursor.glyph) : item
                        }
                        : items

                    VStack(alignment: .leading, spacing: EnsuSpacing.md) {
                        ForEach(Array(resolvedItems.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .top, spacing: EnsuSpacing.sm) {
                                Text("•")
                                    .font(EnsuTypography.message)
                                    .foregroundStyle(EnsuColor.textPrimary)
                                if item.hasMath {
                                    InlineMathTextView(
                                        text: item,
                                        fonts: messageInlineFonts,
                                        textColor: EnsuColor.textPrimary
                                    )
                                } else {
                                    Text(item.attributedText)
                                        .font(EnsuTypography.message)
                                        .foregroundStyle(EnsuColor.textPrimary)
                                        .lineSpacing(messageLineSpacing)
                                }
                            }
                        }
                    }
                case .divider:
                    Divider()
                        .background(EnsuColor.border)
                }
            }

            if showTrailingCursor {
                Text(StreamingCursor.glyph)
                    .font(EnsuTypography.message)
                    .foregroundStyle(EnsuColor.textPrimary)
            }
        }
        .textSelection(.enabled)
    }

    private func headingFontSize(for level: Int) -> CGFloat {
        switch level {
        case 1:
            return 22
        case 2:
            return 20
        default:
            return 18
        }
    }

    private func headingFont(for level: Int) -> Font {
        EnsuFont.message(size: headingFontSize(for: level), weight: .semibold)
    }
}

private struct InlineFontSet {
    let normal: Font
    let code: Font
    let mathSize: CGFloat
}

private let messageInlineFonts = InlineFontSet(
    normal: EnsuTypography.message,
    code: EnsuFont.code(size: 15, weight: .regular),
    mathSize: 15
)

private func inlineText(_ content: AttributedString, fonts: InlineFontSet) -> Text {
    var attributed = content
    for run in content.runs where run.inlinePresentationIntent?.contains(.code) == true {
        attributed[run.range].font = fonts.code
    }
    return Text(attributed).font(fonts.normal)
}

private func splitTextChunks(_ text: AttributedString) -> [AttributedString] {
    var chunks: [AttributedString] = []
    var start = text.startIndex
    var previousWasWhitespace = false
    for index in text.characters.indices {
        let character = text.characters[index]
        if previousWasWhitespace && !character.isWhitespace {
            chunks.append(AttributedString(text[start..<index]))
            start = index
        }
        previousWasWhitespace = character.isWhitespace
    }
    if start != text.endIndex {
        chunks.append(AttributedString(text[start..<text.endIndex]))
    }
    return chunks
}

private struct InlineMathTextView: View {
    let text: InlineContent
    let fonts: InlineFontSet
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.lines.enumerated()), id: \.offset) { _, line in
                FlowLayout(spacing: 0) {
                    ForEach(Array(line.segments.enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case .math(let latex):
                            InlineLaTeXView(latex: latex, fontSize: fonts.mathSize)
                                .fixedSize()
                        case .text(let content):
                            ForEach(Array(splitTextChunks(content).enumerated()), id: \.offset) {
                                _, chunk in
                                inlineText(chunk, fonts: fonts)
                                    .foregroundStyle(textColor)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct CodeBlockView: View {
    let code: String

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(EnsuTypography.code)
                    .foregroundStyle(EnsuColor.textPrimary)
                    .lineSpacing(EnsuLineHeight.spacing(fontSize: 13, lineHeight: 1.45))
                    .padding(EnsuSpacing.cardPadding)
                    .textSelection(.enabled)
            }

            Button {
                hapticTap()
                copyToPasteboard(code)
            } label: {
                Image("Copy01Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .padding(6)
                    .background(EnsuColor.fillFaint.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .background(EnsuColor.fillFaint)
        .overlay(
            RoundedRectangle(cornerRadius: EnsuCornerRadius.codeBlock)
                .stroke(EnsuColor.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.codeBlock, style: .continuous))
    }
}

struct MathBlockView: View {
    let text: String

    var body: some View {
        LaTeXView(latex: text)
            .frame(minHeight: 48)
            .background(EnsuColor.fillFaint)
            .overlay(
                RoundedRectangle(cornerRadius: EnsuCornerRadius.codeBlock)
                    .stroke(EnsuColor.border, lineWidth: 1)
            )
            .clipShape(
                RoundedRectangle(cornerRadius: EnsuCornerRadius.codeBlock, style: .continuous))
    }
}

struct BlockQuoteView: View {
    let text: InlineContent

    var body: some View {
        Group {
            if text.hasMath {
                InlineMathTextView(
                    text: text,
                    fonts: messageInlineFonts,
                    textColor: EnsuColor.textPrimary
                )
            } else {
                Text(text.attributedText)
                    .font(EnsuTypography.message)
                    .foregroundStyle(EnsuColor.textPrimary)
            }
        }
        .padding(EnsuSpacing.cardPadding)
        .background(EnsuColor.fillFaint)
        .overlay(
            Rectangle()
                .fill(EnsuColor.border)
                .frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.input, style: .continuous))
    }
}

struct ScrollChange: Equatable {
    var messagesCount: Int = 0
    var sessionId: UUID?
    var streamingLength: Int = 0
    var keyboardHeight: CGFloat = 0
    var inputBarHeight: CGFloat = 0
    var isGenerating: Bool = false
    var isAtBottom: Bool = true
}
