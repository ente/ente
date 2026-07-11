import SwiftUI
import Markdown
import QuickLook
import UIKit

struct BottomOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

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

    private func fittedPreviewSize(imageSize: CGSize, containerSize: CGSize, padding: CGFloat) -> CGSize {
        let availableWidth = max(0, containerSize.width - (padding * 2))
        let availableHeight = max(0, containerSize.height - (padding * 2))

        guard imageSize.width > 0, imageSize.height > 0, availableWidth > 0, availableHeight > 0 else {
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

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
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
                        .lineSpacing(EnsuLineHeight.spacing(fontSize: 15, lineHeight: 1.7))
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

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                    AssistantMessageRenderer(text: message.text, isStreaming: false, storageId: message.id.uuidString)

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
        let hasText = isGenerating && !renderedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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

        let thinkMatches = ParsedMessage.extractTags(using: ChatMessageTagRegex.think, from: remaining)
        remaining = thinkMatches.cleaned

        let todoMatches = ParsedMessage.extractTags(using: ChatMessageTagRegex.todoList, from: remaining)
        remaining = todoMatches.cleaned

        for content in todoMatches.contents {
            if let data = content.data(using: .utf8),
               let payload = try? JSONDecoder().decode(TodoPayload.self, from: data) {
                todos.append(TodoBlock(title: payload.title, status: payload.status, items: payload.items))
            }
        }

        self.todoBlocks = todos
        self.markdown = remaining
        self.markdownBlocks = MarkdownParser.parse(remaining)
    }

    private static func extractTags(using regex: NSRegularExpression?, from text: String) -> (contents: [String], cleaned: String) {
        guard let regex else {
            return ([], text)
        }

        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        let contents: [String] = matches.compactMap { match in
            guard let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
        let cleaned = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
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
                ForEach(items, id: \.self) { item in
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

    var body: some View {
        let lastKind = blocks.last?.kind
        let inlineCursorSupported = lastKind.map { kind in
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
                    let displayText = showCursor && isLast ? text + StreamingCursor.glyph : text
                    if containsInlineMath(displayText) {
                        InlineMathTextView(
                            text: displayText,
                            fonts: InlineFontSet(
                                normal: headingFont(for: level),
                                code: EnsuFont.code(size: headingFontSize(for: level), weight: .semibold),
                                mathSize: headingFontSize(for: level)
                            ),
                            textColor: EnsuColor.textPrimary
                        )
                    } else {
                        markdownText(displayText)
                            .font(headingFont(for: level))
                            .foregroundStyle(EnsuColor.textPrimary)
                    }
                case .paragraph(let text):
                    let displayText = showCursor && isLast ? text + StreamingCursor.glyph : text
                    if containsInlineMath(displayText) {
                        InlineMathTextView(
                            text: displayText,
                            fonts: messageInlineFonts,
                            textColor: EnsuColor.textPrimary
                        )
                    } else {
                        markdownText(displayText)
                            .font(EnsuTypography.message)
                            .foregroundStyle(EnsuColor.textPrimary)
                            .lineSpacing(EnsuLineHeight.spacing(fontSize: 15, lineHeight: 1.7))
                    }
                case .blockquote(let text):
                    let displayText = showCursor && isLast ? text + StreamingCursor.glyph : text
                    BlockQuoteView(text: displayText)
                case .code(let code):
                    CodeBlockView(code: code)
                case .math(let text):
                    MathBlockView(text: text)
                case .list(let items):
                    let resolvedItems = (showCursor && isLast)
                        ? items.enumerated().map { offset, item in
                            offset == items.count - 1 ? item + StreamingCursor.glyph : item
                        }
                        : items

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(resolvedItems, id: \.self) { item in
                            HStack(alignment: .top, spacing: EnsuSpacing.sm) {
                                Text("•")
                                    .font(EnsuTypography.message)
                                    .foregroundStyle(EnsuColor.textPrimary)
                                if containsInlineMath(item) {
                                    InlineMathTextView(
                                        text: item,
                                        fonts: messageInlineFonts,
                                        textColor: EnsuColor.textPrimary
                                    )
                                } else {
                                    markdownText(item)
                                        .font(EnsuTypography.message)
                                        .foregroundStyle(EnsuColor.textPrimary)
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

func markdownText(_ text: String) -> SwiftUI.Text {
    if let attributed = try? AttributedString(markdown: text) {
        return SwiftUI.Text(attributed)
    }
    return SwiftUI.Text(text)
}

private enum InlineMarkdownStyle: Equatable {
    case normal
    case bold
    case italic
    case code
}

private enum InlineSegment: Equatable {
    case text(String, InlineMarkdownStyle)
    case math(String)
}

private struct InlineMathMatch {
    let latex: String
    let endIndex: Int
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

private let inlineMathPattern = try! NSRegularExpression(
    pattern: #"(?<!\\)\$(?!\$)(?:[^$\n\\]|\\.)+?(?<!\\)\$(?!\$)|\\\((?:[^\n\\]|\\.)+?\\\)"#,
    options: []
)

private func parseInlineSegments(_ text: String) -> [InlineSegment] {
    let characters = Array(text)
    var segments: [InlineSegment] = []
    var buffer: [Character] = []
    var currentStyle: InlineMarkdownStyle = .normal
    var index = 0

    func flushBuffer() {
        if !buffer.isEmpty {
            segments.append(.text(String(buffer), currentStyle))
            buffer.removeAll(keepingCapacity: true)
        }
    }

    while index < characters.count {
        if let mathMatch = findInlineMathMatch(characters, startIndex: index) {
            flushBuffer()
            segments.append(.math(mathMatch.latex))
            index = mathMatch.endIndex
            continue
        }

        switch currentStyle {
        case .code:
            if characters[index] == "`" {
                flushBuffer()
                currentStyle = .normal
                index += 1
            } else {
                buffer.append(characters[index])
                index += 1
            }
        case .bold:
            if hasPrefix(characters, at: index, token: ["*", "*"]) {
                flushBuffer()
                currentStyle = .normal
                index += 2
            } else {
                buffer.append(characters[index])
                index += 1
            }
        case .italic:
            if characters[index] == "*" && !hasPrefix(characters, at: index, token: ["*", "*"]) {
                flushBuffer()
                currentStyle = .normal
                index += 1
            } else {
                buffer.append(characters[index])
                index += 1
            }
        case .normal:
            switch true {
            case hasPrefix(characters, at: index, token: ["*", "*"]) && hasClosingDelimiter(characters, startIndex: index + 2, delimiter: ["*", "*"]):
                flushBuffer()
                currentStyle = .bold
                index += 2
            case characters[index] == "*" &&
                !hasPrefix(characters, at: index, token: ["*", "*"]) &&
                hasClosingSingleAsterisk(characters, startIndex: index + 1):
                flushBuffer()
                currentStyle = .italic
                index += 1
            case characters[index] == "`" &&
                hasClosingDelimiter(characters, startIndex: index + 1, delimiter: ["`"]):
                flushBuffer()
                currentStyle = .code
                index += 1
            default:
                buffer.append(characters[index])
                index += 1
            }
        }
    }

    flushBuffer()
    return segments
}

private func findInlineMathMatch(_ characters: [Character], startIndex: Int) -> InlineMathMatch? {
    if startIndex >= characters.count {
        return nil
    }

    if hasPrefix(characters, at: startIndex, token: ["\\", "("]) {
        var index = startIndex + 2
        while index < characters.count {
            if characters[index] == "\n" {
                return nil
            }
            if characters[index] == "\\" {
                if index + 1 >= characters.count {
                    return nil
                }
                if characters[index + 1] == ")" {
                    return InlineMathMatch(
                        latex: String(characters[(startIndex + 2)..<index]),
                        endIndex: index + 2
                    )
                }
                index += 2
                continue
            }
            index += 1
        }
        return nil
    }

    if characters[startIndex] != "$" || (startIndex > 0 && characters[startIndex - 1] == "\\") {
        return nil
    }
    if startIndex + 1 < characters.count && characters[startIndex + 1] == "$" {
        return nil
    }

    var index = startIndex + 1
    while index < characters.count {
        if characters[index] == "\n" {
            return nil
        }
        if characters[index] == "$" &&
            characters[index - 1] != "\\" &&
            (index + 1 >= characters.count || characters[index + 1] != "$") {
            if index == startIndex + 1 {
                return nil
            }
            return InlineMathMatch(
                latex: String(characters[(startIndex + 1)..<index]),
                endIndex: index + 1
            )
        }
        index += 1
    }

    return nil
}

private func hasPrefix(_ characters: [Character], at startIndex: Int, token: [Character]) -> Bool {
    let endIndex = startIndex + token.count
    if startIndex < 0 || endIndex > characters.count {
        return false
    }
    return Array(characters[startIndex..<endIndex]) == token
}

private func hasClosingDelimiter(_ characters: [Character], startIndex: Int, delimiter: [Character]) -> Bool {
    var index = startIndex
    while index < characters.count {
        if characters[index] == "\n" {
            return false
        }
        if hasPrefix(characters, at: index, token: delimiter) {
            return true
        }
        index += 1
    }
    return false
}

private func hasClosingSingleAsterisk(_ characters: [Character], startIndex: Int) -> Bool {
    var index = startIndex
    while index < characters.count {
        if characters[index] == "\n" {
            return false
        }
        if characters[index] == "*" && !hasPrefix(characters, at: index, token: ["*", "*"]) {
            return true
        }
        index += 1
    }
    return false
}

private func containsInlineMath(_ text: String) -> Bool {
    let nsText = text as NSString
    return inlineMathPattern.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) != nil
}

private func styledInlineText(
    _ content: String,
    style: InlineMarkdownStyle,
    fonts: InlineFontSet,
    textColor: Color
) -> some View {
    switch style {
    case .normal:
        return AnyView(
            markdownText(content)
                .font(fonts.normal)
                .foregroundStyle(textColor)
        )
    case .bold:
        return AnyView(
            markdownText(content)
                .font(fonts.normal)
                .fontWeight(.semibold)
                .foregroundStyle(textColor)
        )
    case .italic:
        return AnyView(
            markdownText(content)
                .font(fonts.normal)
                .italic()
                .foregroundStyle(textColor)
        )
    case .code:
        return AnyView(
            Text(verbatim: content)
                .font(fonts.code)
                .foregroundStyle(textColor)
        )
    }
}

private func splitTextChunks(_ text: String) -> [String] {
    var chunks: [String] = []
    var current = ""
    for ch in text {
        if ch.isWhitespace {
            current.append(ch)
        } else {
            if !current.isEmpty && current.last?.isWhitespace == true {
                chunks.append(current)
                current = ""
            }
            current.append(ch)
        }
    }
    if !current.isEmpty {
        chunks.append(current)
    }
    return chunks
}

private struct InlineMathTextView: View {
    let text: String
    let fonts: InlineFontSet
    let textColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, rawLine in
                let line = String(rawLine)
                FlowLayout(spacing: 0) {
                    ForEach(Array(parseInlineSegments(line).enumerated()), id: \.offset) { _, segment in
                        switch segment {
                        case .math(let latex):
                            InlineLaTeXView(latex: latex, fontSize: fonts.mathSize)
                                .fixedSize()
                        case .text(let content, let style):
                            ForEach(Array(splitTextChunks(content).enumerated()), id: \.offset) { _, chunk in
                                styledInlineText(chunk, style: style, fonts: fonts, textColor: textColor)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct MarkdownBlock: Identifiable, Equatable {
    enum Kind: Equatable {
        case heading(level: Int, text: String)
        case paragraph(text: String)
        case blockquote(text: String)
        case code(text: String)
        case math(text: String)
        case list(items: [String])
        case divider
    }

    let id: Int
    let kind: Kind
}

enum MarkdownParser {
    static func parse(_ text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var nextId = 0

        func append(_ kind: MarkdownBlock.Kind) {
            blocks.append(MarkdownBlock(id: nextId, kind: kind))
            nextId += 1
        }

        let segments = text.components(separatedBy: "```")

        for (index, segment) in segments.enumerated() {
            if index % 2 == 1 {
                let code = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                if !code.isEmpty {
                    append(.code(text: code))
                }
                continue
            }

            for piece in splitByMathBlocks(segment) {
                switch piece {
                case .math(let latex):
                    let trimmed = latex.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        append(.math(text: trimmed))
                    }
                case .markdown(let markdown):
                    parseMarkdownBlocks(markdown).forEach { append($0) }
                }
            }
        }

        return blocks
    }

    private enum Segment {
        case markdown(String)
        case math(String)
    }

    private static func splitByMathBlocks(_ text: String) -> [Segment] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var segments: [Segment] = []
        var markdownLines: [String] = []
        var mathLines: [String] = []
        var mathEndDelimiter: String? = nil

        func flushMarkdown() {
            if !markdownLines.isEmpty {
                segments.append(.markdown(markdownLines.joined(separator: "\n")))
                markdownLines.removeAll()
            }
        }

        func flushMath() {
            if !mathLines.isEmpty {
                segments.append(.math(mathLines.joined(separator: "\n")))
            }
            mathLines.removeAll()
            mathEndDelimiter = nil
        }

        func startMath(endDelimiter: String, initialContent: String? = nil) {
            flushMarkdown()
            mathEndDelimiter = endDelimiter
            mathLines.removeAll()
            if let initial = initialContent?.trimmingCharacters(in: .whitespacesAndNewlines), !initial.isEmpty {
                mathLines.append(initial)
            }
        }

        func isBracketMathLine(_ trimmed: String) -> Bool {
            guard trimmed.hasPrefix("["), trimmed.hasSuffix("]"), trimmed.count > 2 else {
                return false
            }
            if trimmed.contains("](") || trimmed.contains("]:") {
                return false
            }
            return true
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let endDelimiter = mathEndDelimiter {
                if trimmed == endDelimiter {
                    flushMath()
                    continue
                }
                if endDelimiter != "]" && trimmed.hasSuffix(endDelimiter) {
                    let content = String(trimmed.dropLast(endDelimiter.count)).trimmingCharacters(in: .whitespaces)
                    if !content.isEmpty {
                        mathLines.append(content)
                    }
                    flushMath()
                    continue
                }
                mathLines.append(line)
                continue
            }

            if trimmed == "\\[" || trimmed == "$$" || trimmed == "[" {
                let endDelimiter = trimmed == "\\[" ? "\\]" : (trimmed == "$$" ? "$$" : "]")
                startMath(endDelimiter: endDelimiter)
                continue
            }

            if trimmed.hasPrefix("\\[") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if content.hasSuffix("\\]") {
                    let inner = String(content.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    flushMarkdown()
                    segments.append(.math(inner))
                } else {
                    startMath(endDelimiter: "\\]", initialContent: content)
                }
                continue
            }

            if trimmed.hasPrefix("$$") {
                let content = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if content.hasSuffix("$$") {
                    let inner = String(content.dropLast(2)).trimmingCharacters(in: .whitespaces)
                    flushMarkdown()
                    segments.append(.math(inner))
                } else {
                    startMath(endDelimiter: "$$", initialContent: content)
                }
                continue
            }

            if isBracketMathLine(trimmed) {
                let inner = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                flushMarkdown()
                segments.append(.math(inner))
                continue
            }

            markdownLines.append(line)
        }

        if mathEndDelimiter != nil {
            flushMath()
        } else {
            flushMarkdown()
        }

        return segments
    }

    private static func parseMarkdownBlocks(_ markdown: String) -> [MarkdownBlock.Kind] {
        guard !markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        let document = Document(parsing: markdown)
        var parsedBlocks: [MarkdownBlock.Kind] = []
        for child in document.children {
            parsedBlocks.append(contentsOf: blocks(for: child))
        }
        return parsedBlocks
    }

    private static func blocks(for markup: Markup) -> [MarkdownBlock.Kind] {
        switch markup {
        case let heading as Heading:
            let text = renderInlineChildren(heading)
            guard !text.isEmpty else { return [] }
            let level = max(1, min(heading.level, 3))
            return [.heading(level: level, text: text)]
        case let paragraph as Paragraph:
            let text = renderInlineChildren(paragraph)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return [.paragraph(text: text)]
        case let blockQuote as BlockQuote:
            let text = renderBlockQuote(blockQuote)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return [.blockquote(text: text)]
        case let codeBlock as CodeBlock:
            let code = codeBlock.code.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !code.isEmpty else { return [] }
            return [.code(text: code)]
        case _ as ThematicBreak:
            return [.divider]
        case let orderedList as OrderedList:
            let items = orderedList.children.compactMap { $0 as? ListItem }.map(renderListItem).filter { !$0.isEmpty }
            return items.isEmpty ? [] : [.list(items: items)]
        case let unorderedList as UnorderedList:
            let items = unorderedList.children.compactMap { $0 as? ListItem }.map(renderListItem).filter { !$0.isEmpty }
            return items.isEmpty ? [] : [.list(items: items)]
        default:
            var nestedBlocks: [MarkdownBlock.Kind] = []
            for child in markup.children {
                nestedBlocks.append(contentsOf: blocks(for: child))
            }
            return nestedBlocks
        }
    }

    private static func renderBlockQuote(_ quote: BlockQuote) -> String {
        var parts: [String] = []
        for child in quote.children {
            if let paragraph = child as? Paragraph {
                let text = renderInlineChildren(paragraph)
                if !text.isEmpty {
                    parts.append(text)
                }
                continue
            }
            if let heading = child as? Heading {
                let text = renderInlineChildren(heading)
                if !text.isEmpty {
                    parts.append(text)
                }
                continue
            }
            if let list = child as? OrderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(items.joined(separator: "\n"))
                }
                continue
            }
            if let list = child as? UnorderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(items.joined(separator: "\n"))
                }
                continue
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func renderListItem(_ item: ListItem) -> String {
        var parts: [String] = []
        for child in item.children {
            if let paragraph = child as? Paragraph {
                let text = renderInlineChildren(paragraph)
                if !text.isEmpty {
                    parts.append(text)
                }
                continue
            }
            if let list = child as? OrderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(items.joined(separator: "\n"))
                }
                continue
            }
            if let list = child as? UnorderedList {
                let items = list.children.compactMap { $0 as? ListItem }.map(renderListItem).filter { !$0.isEmpty }
                if !items.isEmpty {
                    parts.append(items.joined(separator: "\n"))
                }
                continue
            }
        }
        return parts.joined(separator: "\n")
    }

    private static func renderInlineChildren(_ markup: Markup) -> String {
        markup.children.map(renderInline(from:)).joined()
    }

    private static func renderInline(from markup: Markup) -> String {
        switch markup {
        case let text as Markdown.Text:
            return text.string
        case _ as SoftBreak:
            return " "
        case _ as LineBreak:
            return "\n"
        case let emphasis as Emphasis:
            return "*" + renderInlineChildren(emphasis) + "*"
        case let strong as Strong:
            return "**" + renderInlineChildren(strong) + "**"
        case let inlineCode as InlineCode:
            return "`\(inlineCode.code)`"
        case let strikethrough as Strikethrough:
            return "~~" + renderInlineChildren(strikethrough) + "~~"
        case let link as Markdown.Link:
            let label = renderInlineChildren(link)
            let destination = link.destination ?? ""
            return destination.isEmpty ? label : "[\(label)](\(destination))"
        default:
            if !markup.children.contains(where: { _ in true }) {
                return ""
            }
            return renderInlineChildren(markup)
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
            .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.codeBlock, style: .continuous))
    }
}

struct BlockQuoteView: View {
    let text: String

    var body: some View {
        Group {
            if containsInlineMath(text) {
                InlineMathTextView(
                    text: text,
                    fonts: messageInlineFonts,
                    textColor: EnsuColor.textPrimary
                )
            } else {
                markdownText(text)
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
