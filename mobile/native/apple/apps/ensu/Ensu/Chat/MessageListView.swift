import SwiftUI

struct MessageListView: View {
    let messages: [RenderedChatMessage]
    let streamingResponse: String
    let streamingParentId: UUID?
    let isGenerating: Bool
    let sessionId: UUID?
    let keyboardHeight: CGFloat
    let inputBarHeight: CGFloat
    let emptyStateTitle: String
    let emptyStateSubtitle: String?
    let onEdit: (RenderedChatMessage) -> Void
    let onCopy: (RenderedChatMessage) -> Void
    let onRetry: (RenderedChatMessage) -> Void
    let onBranchChange: (RenderedChatMessage, Int) -> Void
    let onDismissKeyboard: () -> Void

    @State private var isAtBottom = true
    @State private var autoScrollEnabled = true
    @State private var previewItem: AttachmentPreviewItem?
    @State private var imagePreviewItem: AttachmentPreviewItem?
    @State private var wasAtBottomBeforeKeyboard = false
    @State private var isUserDragging = false
    @State private var lastContentHeight: CGFloat = 0
    @State private var lastScrollChange = ScrollChange()
    @State private var didInitialScroll = false
    @State private var streamingTextStorageId = UUID().uuidString
    @State private var didPerformStreamingStartHaptic = false

    var body: some View {
        let content = GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .bottomLeading) {
                    ScrollView {
                        messageListContent(containerHeight: proxy.size.height)
                    }
                    .id(sessionId)
                    .coordinateSpace(name: "scroll")
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { _ in
                                isUserDragging = true
                                autoScrollEnabled = false
                                onDismissKeyboard()
                            }
                            .onEnded { _ in
                                isUserDragging = false
                                if isAtBottom {
                                    autoScrollEnabled = true
                                }
                            }
                    )
                    .simultaneousGesture(
                        TapGesture()
                            .onEnded {
                                onDismissKeyboard()
                            }
                    )
                    .onPreferenceChange(BottomOffsetKey.self) { value in
                        let threshold: CGFloat = EnsuSpacing.xxxl
                        let distanceToBottom = value - proxy.size.height
                        isAtBottom = distanceToBottom <= threshold
                    }
                    .onPreferenceChange(ContentHeightKey.self) { newHeight in
                        let delta = newHeight - lastContentHeight
                        lastContentHeight = newHeight
                        if delta > 1, autoScrollEnabled, !isUserDragging {
                            scrollToBottom(scrollProxy, force: true, animated: false)
                        }
                    }
                    .onChange(of: currentScrollChange) { newValue in
                        handleScrollChange(newValue, scrollProxy: scrollProxy)
                    }
                    .onAppear {
                        lastScrollChange = currentScrollChange
                        didInitialScroll = false
                        scheduleInitialScroll(scrollProxy)
                    }
                }
            }
        }
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }

        content
            .fullScreenCover(item: $imagePreviewItem) { item in
                ImageAttachmentPreview(
                    url: item.url,
                    accessibilityLabel: item.name.isEmpty ? "Image preview" : item.name,
                    onDismiss: { imagePreviewItem = nil }
                )
            }
    }

    private var currentScrollChange: ScrollChange {
        ScrollChange(
            messagesCount: messages.count,
            sessionId: sessionId,
            streamingLength: streamingResponse.count,
            keyboardHeight: keyboardHeight,
            inputBarHeight: inputBarHeight,
            isGenerating: isGenerating,
            isAtBottom: isAtBottom
        )
    }

    private func handleScrollChange(_ newValue: ScrollChange, scrollProxy: ScrollViewProxy) {
        let previous = lastScrollChange
        lastScrollChange = newValue

        if newValue.messagesCount != previous.messagesCount {
            if !didInitialScroll {
                scheduleInitialScroll(scrollProxy)
            } else {
                scrollToBottom(scrollProxy, animated: newValue.isGenerating)
            }
        }

        if newValue.sessionId != previous.sessionId {
            autoScrollEnabled = true
            didInitialScroll = false
            scheduleInitialScroll(scrollProxy)
        }

        if newValue.isGenerating != previous.isGenerating {
            didPerformStreamingStartHaptic = false
            if newValue.isGenerating {
                autoScrollEnabled = true
                scrollToBottom(scrollProxy, force: true, animated: false)
                performStreamingStartHapticIfNeeded()
            }
        }

        if newValue.streamingLength != previous.streamingLength {
            scrollToBottom(scrollProxy, animated: false)
            performStreamingStartHapticIfNeeded()
        }

        if newValue.keyboardHeight != previous.keyboardHeight {
            if newValue.keyboardHeight > 0 {
                wasAtBottomBeforeKeyboard = isAtBottom
            }
            if wasAtBottomBeforeKeyboard {
                autoScrollEnabled = true
                scrollToBottom(scrollProxy, force: true, animated: false)
            }
            if newValue.keyboardHeight == 0 {
                wasAtBottomBeforeKeyboard = false
            }
        }

        if newValue.isAtBottom != previous.isAtBottom {
            if newValue.isAtBottom && !isUserDragging {
                autoScrollEnabled = true
                scrollToBottom(scrollProxy, force: true, animated: false)
            }
        }
    }

    @ViewBuilder
    private func messageListContent(containerHeight: CGFloat) -> some View {
        let emptyStateMinHeight = max(0, containerHeight - contentBottomPadding - (EnsuSpacing.lg * 2))

        VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: EnsuSpacing.lg) {
                if messages.isEmpty && !isGenerating {
                    VStack {
                        Spacer(minLength: 0)
                        VStack(spacing: EnsuSpacing.sm) {
                            Text(emptyStateTitle)
                                .font(EnsuTypography.h2)
                                .foregroundStyle(EnsuColor.textPrimary)
                            if let emptyStateSubtitle {
                                Text(emptyStateSubtitle)
                                    .font(EnsuTypography.body)
                                    .foregroundStyle(EnsuColor.textMuted)
                            }
                        }
                        .multilineTextAlignment(.center)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: emptyStateMinHeight)
                }

                ForEach(messages) { message in
                    if message.role == .user {
                        UserMessageBubbleView(
                            message: message,
                            onEdit: { onEdit(message) },
                            onCopy: { onCopy(message) },
                            onBranchChange: { delta in onBranchChange(message, delta) },
                            onOpenAttachment: openAttachment
                        )
                        .id(message.id)
                        .transition(messageTransition)
                    } else {
                        AssistantMessageBubbleView(
                            message: message,
                            isLastMessage: message.id == messages.last?.id,
                            onCopy: { onCopy(message) },
                            onRetry: { onRetry(message) },
                            onBranchChange: { delta in onBranchChange(message, delta) },
                            onOpenAttachment: openAttachment,
                            showsMetadata: true
                        )
                        .id(message.id)
                        .transition(messageTransition)
                    }

                    if isGenerating, streamingParentId == message.id {
                        inlineStreamingTextBubble
                            .id("streaming-\(message.id.uuidString)")
                    }
                }

                if isGenerating, streamingParentId == nil {
                    inlineStreamingTextBubble
                        .id("streaming")
                }

                if !messages.isEmpty {
                    aiSafetyFooter
                }
            }
            .padding(.horizontal, EnsuSpacing.pageHorizontal)
            .padding(.top, EnsuSpacing.lg)
            .padding(.bottom, EnsuSpacing.lg)
            .animation(nil, value: messages.count)

            Color.clear
                .frame(height: contentBottomPadding)
                .id("bottom")
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: BottomOffsetKey.self, value: geo.frame(in: .named("scroll")).maxY)
                    }
                )
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ContentHeightKey.self, value: geo.size.height)
            }
        )
    }

    private var inlineStreamingTextBubble: some View {
        let trimmed = streamingResponse.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasText = !trimmed.isEmpty

        return HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: hasText ? EnsuSpacing.sm : 0) {
                if hasText {
                    TimelineView(.periodic(from: .now, by: 0.55)) { context in
                        let phase = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2
                        let showCursor = phase == 0
                        AssistantMessageRenderer(
                            text: streamingResponse,
                            isStreaming: true,
                            storageId: streamingTextStorageId,
                            showsCursor: showCursor
                        )
                    }
                }

                StreamingDotsView()
            }
            .padding(.vertical, hasText ? EnsuSpacing.md : 0)
            .padding(.horizontal, EnsuSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(EnsuColor.textPrimary)
    }

    private var aiSafetyFooter: some View {
        Text("Ensu can make mistakes. Please double-check key details.")
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(EnsuColor.textMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, EnsuSpacing.sm)
    }

    private var messageTransition: AnyTransition {
        .identity
    }

    private var contentBottomPadding: CGFloat {
        let fallbackPadding = EnsuSpacing.xxxl + EnsuSpacing.xxl + 60
        let measuredPadding = inputBarHeight > 0 ? inputBarHeight + EnsuSpacing.md : fallbackPadding
        let basePadding = max(fallbackPadding, measuredPadding)
        return basePadding + keyboardHeight
    }

    private func scheduleInitialScroll(_ proxy: ScrollViewProxy) {
        guard !didInitialScroll else { return }
        DispatchQueue.main.async {
            scrollToBottom(proxy, force: true, animated: false)
            didInitialScroll = true
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, force: Bool = false, animated: Bool = true) {
        guard force || (autoScrollEnabled && isAtBottom) else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }

    private func performStreamingStartHapticIfNeeded() {
        guard isGenerating,
              !didPerformStreamingStartHaptic,
              hasVisibleStreamingContent(streamingResponse) else {
            return
        }
        hapticTap()
        didPerformStreamingStartHaptic = true
    }

    private func openAttachment(_ attachment: ChatAttachment) {
        guard let url = attachment.url else { return }
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        if attachment.kind == .image {
            imagePreviewItem = AttachmentPreviewItem(url: url, name: attachment.name)
            return
        }

        let tempDir = FileManager.default.temporaryDirectory
        let fileName = sanitizedAttachmentName(attachment)
        let previewUrl = tempDir.appendingPathComponent(fileName)

        do {
            if FileManager.default.fileExists(atPath: previewUrl.path) {
                try FileManager.default.removeItem(at: previewUrl)
            }
            try FileManager.default.copyItem(at: url, to: previewUrl)
            previewItem = AttachmentPreviewItem(url: previewUrl)
        } catch {
            previewItem = AttachmentPreviewItem(url: url)
        }
    }

    private func sanitizedAttachmentName(_ attachment: ChatAttachment) -> String {
        let rawName = attachment.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = rawName.isEmpty ? attachment.id.uuidString : rawName
        let invalidCharacters = CharacterSet(charactersIn: "/\\:")
        let sanitized = baseName.components(separatedBy: invalidCharacters).joined(separator: "-")
        return sanitized.isEmpty ? attachment.id.uuidString : sanitized
    }

    private func hasVisibleStreamingContent(_ text: String) -> Bool {
        let textWithoutUnclosedThink = removingUnclosedStreamingTag("think", from: text)
        let visibleText = removingUnclosedStreamingTag("todo_list", from: textWithoutUnclosedThink)
        let parsed = ParsedMessage(text: visibleText)
        return !parsed.todoBlocks.isEmpty ||
            !parsed.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func removingUnclosedStreamingTag(_ tag: String, from text: String) -> String {
        let openingTag = "<\(tag)>"
        let closingTag = "</\(tag)>"
        var result = ""
        var cursor = text.startIndex

        while let openRange = text.range(of: openingTag, range: cursor..<text.endIndex) {
            result.append(contentsOf: text[cursor..<openRange.lowerBound])
            guard let closeRange = text.range(of: closingTag, range: openRange.upperBound..<text.endIndex) else {
                return result
            }
            result.append(contentsOf: text[openRange.lowerBound..<closeRange.upperBound])
            cursor = closeRange.upperBound
        }

        result.append(contentsOf: text[cursor..<text.endIndex])
        return result
    }
}

private struct StreamingDotsView: View {
    var body: some View {
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
}
