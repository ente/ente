import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachments: [ChatAttachment]
    let isGenerating: Bool
    let isDownloading: Bool
    let editingMessage: RenderedChatMessage?
    let isProcessingAttachments: Bool
    let voiceInputState: VoiceInputState
    let moveCursorToEndToken: UUID
    let onSend: () -> Void
    let onStop: () -> Void
    let onCancelEdit: () -> Void
    let onVoiceInput: () -> Void
    let onAddImage: (Data, String?) -> Void
    let onAddDocument: (URL) -> Void
    let onRemoveAttachment: (ChatAttachment) -> Void
    let onUserFocus: () -> Void
    let onDismissKeyboard: () -> Void

    @FocusState.Binding var isFocused: Bool

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var inputResetToken = UUID()

    private let placeholder = "Write a message..."

    private var canSend: Bool {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        return hasContent && !isGenerating && !isDownloading && !voiceInputState.blocksSend
    }

    private var isSendEnabled: Bool {
        let hasContent = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        return hasContent && !isDownloading && !voiceInputState.blocksSend
    }

    private var isImageAttachmentLimitReached: Bool {
        attachments.filter { $0.kind == .image }.count >= ChatAttachmentLimits.maxImagesPerMessage
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: EnsuSpacing.sm) {
                if let editingMessage {
                    editBanner(for: editingMessage)
                }

                let inputVerticalPadding: CGFloat = 10
                let textFieldPadding: CGFloat = 6

                // Lift the bar slightly off the bottom edge.
                let bottomPadding: CGFloat = EnsuSpacing.md

                let inputStackSpacing: CGFloat = EnsuSpacing.sm

                VStack(alignment: .leading, spacing: inputStackSpacing) {
                    if !attachments.isEmpty {
                        let hasImageAttachment = attachments.contains { $0.kind == .image }
                        let maxAttachmentHeight = hasImageAttachment
                            ? CGFloat(2) * 76 + EnsuSpacing.sm
                            : CGFloat(3) * 40 + CGFloat(2) * EnsuSpacing.sm
                        let shouldScroll = attachments.count > 4

                        Group {
                            if shouldScroll {
                                ScrollView(.vertical, showsIndicators: false) {
                                    attachmentFlowLayout
                                }
                                .frame(maxHeight: maxAttachmentHeight)
                            } else {
                                attachmentFlowLayout
                            }
                        }
                        .padding(.horizontal, EnsuSpacing.pageHorizontal)
                    }

                if isProcessingAttachments {
                    HStack(spacing: EnsuSpacing.sm) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Reading attachment...")
                            .font(EnsuTypography.small)
                            .foregroundStyle(EnsuColor.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, EnsuSpacing.pageHorizontal)
                }

                if let voiceStatus = voiceInputState.statusText {
                    HStack(spacing: EnsuSpacing.sm) {
                        switch voiceInputState {
                        case .downloading, .transcribing:
                            ProgressView()
                                .scaleEffect(0.8)
                        case .recording:
                            Image("Mic02Icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)
                                .foregroundStyle(EnsuColor.stopButton)
                        case .error:
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(EnsuColor.stopButton)
                        case .idle:
                            EmptyView()
                        }
                        Text(voiceStatus)
                            .font(EnsuTypography.small)
                            .foregroundStyle(voiceInputState.isError ? EnsuColor.stopButton : EnsuColor.textMuted)
                        Spacer()
                    }
                    .padding(.horizontal, EnsuSpacing.pageHorizontal)
                }

                HStack(alignment: .bottom, spacing: EnsuSpacing.sm) {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .id(inputResetToken)
                        .focused($isFocused)
                        .onChange(of: isFocused) { focused in
                            if focused {
                                onUserFocus()
                            }
                        }
                        .lineLimit(1...5)
                        .font(EnsuTypography.message)
                        .foregroundStyle(EnsuColor.textPrimary)
                        .textInputAutocapitalization(.sentences)
                        .padding(.vertical, textFieldPadding)
                        .onSubmit {
                            if canSend {
                                onSend()
                                isFocused = false
                                hideKeyboard()
                                onDismissKeyboard()
                            }
                        }
                        .onChange(of: text) { newValue in
                            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isFocused {
                                inputResetToken = UUID()
                            }
                        }
                        .background(
                            CursorEndSynchronizer(
                                token: moveCursorToEndToken,
                                text: text
                            )
                            .frame(width: 0, height: 0)
                        )

                    if editingMessage == nil {
                        let canUseAttachment = !isGenerating &&
                            !isDownloading &&
                            !isImageAttachmentLimitReached
                        PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                            Image("Upload01Icon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: attachmentIconSize, height: attachmentIconSize)
                                .frame(width: 32, height: 32, alignment: .center)
                        }
                        .disabled(!canUseAttachment)
                        .foregroundStyle(canUseAttachment ? EnsuColor.textPrimary : EnsuColor.textMuted)
                        .simultaneousGesture(TapGesture().onEnded {
                            if canUseAttachment {
                                hapticTap()
                            }
                        })
                        .onChange(of: selectedPhotoItem) { newItem in
                            guard let newItem else { return }
                            guard !isImageAttachmentLimitReached else {
                                selectedPhotoItem = nil
                                return
                            }
                            Task {
                                let data = try? await newItem.loadTransferable(type: Data.self)
                                await MainActor.run {
                                    if let data {
                                        onAddImage(data, nil)
                                    }
                                    selectedPhotoItem = nil
                                }
                            }
                        }
                    }

                    if editingMessage == nil {
                        let isVoiceBusy = voiceInputState.isTranscriptionBusy
                        let canUseVoice = voiceInputState.isRecording ||
                            (!isGenerating && !isDownloading && !isVoiceBusy)

                        Button {
                            if voiceInputState.isRecording {
                                hapticWarning()
                            } else {
                                hapticTap()
                                isFocused = false
                                hideKeyboard()
                                onDismissKeyboard()
                            }
                            onVoiceInput()
                        } label: {
                            if isVoiceBusy {
                                ProgressView()
                                    .scaleEffect(0.75)
                                    .frame(width: 32, height: 32)
                            } else if voiceInputState.isRecording {
                                Image("StopIcon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: attachmentIconSize, height: attachmentIconSize)
                                    .foregroundStyle(EnsuColor.stopButton)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image("Mic02Icon")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: attachmentIconSize, height: attachmentIconSize)
                                    .foregroundStyle(canUseVoice ? EnsuColor.textPrimary : EnsuColor.textMuted)
                                    .frame(width: 32, height: 32)
                            }
                        }
                        .disabled(!canUseVoice)
                    }

                    Button {
                        if isGenerating {
                            hapticWarning()
                            onStop()
                        } else if isSendEnabled {
                            hapticMedium()
                            onSend()
                            isFocused = false
                            hideKeyboard()
                            onDismissKeyboard()
                        }
                    } label: {
                        if sendIcon == "StopIcon" {
                            ZStack {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: attachmentIconSize + 6, height: attachmentIconSize + 6)
                                Image(sendIcon)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: attachmentIconSize - 4, height: attachmentIconSize - 4)
                                    .foregroundStyle(EnsuColor.stopButton)
                            }
                            .frame(width: 32, height: 32)
                        } else {
                            Image(sendIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: attachmentIconSize, height: attachmentIconSize)
                                .rotationEffect(sendIcon == "Navigation06Icon" ? .degrees(90) : .zero)
                                .foregroundStyle(sendColor)
                                .frame(width: 32, height: 32)
                        }
                    }
                    .disabled(isDownloading || (!canSend && !isGenerating))
                }
                .padding(.horizontal, EnsuSpacing.inputHorizontal)
                .padding(.vertical, inputVerticalPadding)
                .frame(maxWidth: .infinity)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: EnsuCornerRadius.input + 4, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 6)
                .overlay(alignment: .topTrailing) {
                    if isFocused {
                        Button {
                            hapticTap()
                            isFocused = false
                            hideKeyboard()
                            onDismissKeyboard()
                        } label: {
                            Image(systemName: keyboardDismissIconName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(EnsuColor.textPrimary)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        }
                        .offset(y: -(32 + EnsuSpacing.sm))
                    }
                }
                .padding(.horizontal, EnsuSpacing.pageHorizontal)
                .padding(.bottom, bottomPadding)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: InputBarHeightKey.self, value: proxy.size.height)
                }
            )
        }
    }
    .padding(.top, EnsuSpacing.sm)
}

    private var attachmentIconSize: CGFloat {
        return 16
    }

    private var keyboardDismissIconName: String {
        UIImage(systemName: "keyboard.chevron.compact.down") != nil
            ? "keyboard.chevron.compact.down"
            : "chevron.down"
    }

    private var attachmentFlowLayout: some View {
        FlowLayout(spacing: EnsuSpacing.sm) {
            ForEach(attachments) { attachment in
                if attachment.kind == .image, attachment.url != nil {
                    ImageAttachmentThumbnail(
                        url: attachment.url,
                        accessibilityLabel: attachment.name,
                        width: 76,
                        height: 76,
                        isUploading: attachment.isUploading
                    ) {
                        onRemoveAttachment(attachment)
                    }
                } else {
                    AttachmentChip(
                        name: attachment.name,
                        size: attachment.formattedSize,
                        icon: attachment.iconName,
                        isUploading: attachment.isUploading
                    ) {
                        onRemoveAttachment(attachment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sendIcon: String {
        if isGenerating {
            return "StopIcon"
        }
        return "Navigation06Icon"
    }

    private var sendColor: Color {
        if isGenerating {
            return EnsuColor.stopButton
        }
        return isSendEnabled ? EnsuColor.textPrimary : EnsuColor.textMuted
    }

    private func editBanner(for message: RenderedChatMessage) -> some View {
        HStack(spacing: EnsuSpacing.sm) {
            Image("Edit01Icon")
                .resizable()
                .scaledToFit()
                .frame(width: 14, height: 14)
                .foregroundStyle(EnsuColor.action)

            Text("Editing:")
                .font(EnsuTypography.small)
                .foregroundStyle(EnsuColor.textMuted)

            Text(message.text)
                .font(EnsuTypography.small)
                .foregroundStyle(EnsuColor.textPrimary)
                .lineLimit(1)

            Spacer()

            Button(action: {
                hapticTap()
                onCancelEdit()
            }) {
                Image("Cancel01Icon")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 12, height: 12)
                    .foregroundStyle(EnsuColor.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, EnsuSpacing.md)
        .padding(.vertical, EnsuSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: EnsuCornerRadius.input, style: .continuous)
                .fill(EnsuColor.fillFaint)
        )
        .overlay(
            Rectangle()
                .fill(EnsuColor.accent)
                .frame(width: 3),
            alignment: .leading
        )
        .padding(.horizontal, EnsuSpacing.pageHorizontal)
    }
}

struct InputBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CursorEndSynchronizer: UIViewRepresentable {
    let token: UUID
    let text: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard context.coordinator.lastToken != token else { return }
        context.coordinator.lastToken = token

        DispatchQueue.main.async {
            Self.moveCursorToEnd(from: uiView, text: text)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            Self.moveCursorToEnd(from: uiView, text: text)
        }
    }

    private static func moveCursorToEnd(from view: UIView, text: String) {
        var currentView: UIView? = view
        while let candidate = currentView {
            let inputs = candidate.cursorEndTextInputs()
            let target = inputs.first(where: { $0.isFirstResponder }) ??
                inputs.first(where: { $0.cursorText == text })
            if let target {
                target.moveCursorToEnd()
                return
            }
            currentView = candidate.superview
        }
    }

    final class Coordinator {
        var lastToken: UUID?
    }
}

private protocol CursorEndTextInput: AnyObject {
    var cursorText: String { get }
    var isFirstResponder: Bool { get }
    func moveCursorToEnd()
}

extension UITextField: CursorEndTextInput {
    var cursorText: String {
        text ?? ""
    }

    func moveCursorToEnd() {
        let end = endOfDocument
        selectedTextRange = textRange(from: end, to: end)
    }
}

extension UITextView: CursorEndTextInput {
    var cursorText: String {
        text ?? ""
    }

    func moveCursorToEnd() {
        selectedRange = NSRange(location: (text as NSString).length, length: 0)
    }
}

private extension UIView {
    func cursorEndTextInputs() -> [CursorEndTextInput] {
        var inputs: [CursorEndTextInput] = []
        if let input = self as? CursorEndTextInput {
            inputs.append(input)
        }
        for subview in subviews {
            inputs.append(contentsOf: subview.cursorEndTextInputs())
        }
        return inputs
    }
}
