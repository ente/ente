import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

struct MessageInputView: View {
    @Binding var text: String
    @Binding var attachments: [ChatAttachment]
    let supportsImageAttachments: Bool
    let isGenerating: Bool
    let isSendPending: Bool
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

    @Binding var isFocused: Bool

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showPhotos = false

    private let placeholder = "Ask Ensu"

    private var canSend: Bool {
        !isGenerating && isSendEnabled
    }

    private var isSendEnabled: Bool {
        let hasContent =
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
        return hasContent && !isDownloading && !isSendPending && !voiceInputState.blocksSend
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

                let bottomPadding: CGFloat = EnsuSpacing.md

                let inputStackSpacing: CGFloat = EnsuSpacing.sm

                VStack(alignment: .leading, spacing: inputStackSpacing) {
                    if !attachments.isEmpty {
                        let hasImageAttachment = attachments.contains { $0.kind == .image }
                        let maxAttachmentHeight =
                            hasImageAttachment
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
                        .padding(.horizontal, EnsuSpacing.sm)
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
                        .padding(.horizontal, EnsuSpacing.sm)
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
                                .foregroundStyle(
                                    voiceInputState.isError
                                        ? EnsuColor.stopButton : EnsuColor.textMuted)
                            Spacer()
                        }
                        .padding(.horizontal, EnsuSpacing.sm)
                    }

                    HStack(alignment: .bottom, spacing: EnsuSpacing.xs) {
                        ActionButton(
                            icon: "ImagePlusIcon", tooltip: "Add photos",
                            color: EnsuColor.textPrimary, size: 32
                        ) {
                            dismissInput()
                            showPhotos = true
                        }
                        .disabled(
                            editingMessage != nil || !supportsImageAttachments
                                || isGenerating || isSendPending || isDownloading
                                || isImageAttachmentLimitReached
                        )
                        .photosPicker(
                            isPresented: $showPhotos, selection: $selectedPhotoItem,
                            matching: .images
                        )
                        .onChange(of: selectedPhotoItem) { item in
                            guard let item, !isImageAttachmentLimitReached else {
                                selectedPhotoItem = nil; return
                            }
                            Task {
                                let data = try? await item.loadTransferable(type: Data.self)
                                await MainActor.run {
                                    if let data { onAddImage(data, nil) }
                                    selectedPhotoItem = nil
                                }
                            }
                        }

                        MessageTextView(
                            text: $text,
                            isFocused: $isFocused,
                            moveCursorToEndToken: moveCursorToEndToken,
                            onSubmit: {
                                if canSend {
                                    onSend()
                                    isFocused = false
                                    hideKeyboard()
                                    onDismissKeyboard()
                                }
                            }
                        )
                        .padding(.vertical, 6)
                        .overlay(alignment: .topLeading) {
                            if text.isEmpty {
                                Text(placeholder)
                                    .font(EnsuTypography.message)
                                    .foregroundStyle(Color(uiColor: .placeholderText))
                                    .padding(.vertical, 6)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                        }
                        .onChange(of: isFocused) { focused in
                            if focused {
                                onUserFocus()
                            }
                        }

                        if editingMessage == nil {
                            let isVoiceBusy = voiceInputState.isTranscriptionBusy
                            let canUseVoice =
                                voiceInputState.isRecording
                                || (!isGenerating && !isDownloading && !isVoiceBusy)

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
                                        .frame(
                                            width: composerIconSize, height: composerIconSize
                                        )
                                        .foregroundStyle(EnsuColor.sendButton)
                                        .frame(width: 32, height: 32)
                                } else {
                                    Image("Mic02Icon")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: composerIconSize, height: composerIconSize)
                                        .foregroundStyle(
                                            canUseVoice
                                                ? EnsuColor.textPrimary : EnsuColor.textMuted
                                        )
                                        .frame(width: 32, height: 32)
                                }
                            }
                            .disabled(!canUseVoice)
                            .padding(.leading, EnsuSpacing.xs)
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
                            Image(sendIcon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: composerIconSize, height: composerIconSize)
                                .rotationEffect(
                                    sendIcon == "Navigation06Icon" ? .degrees(90) : .zero
                                )
                                .foregroundStyle(sendColor)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel(isGenerating ? "Stop response" : "Send message")
                        .disabled(isDownloading || (!canSend && !isGenerating))
                        .padding(.leading, EnsuSpacing.xs)
                    }
                    .padding(.horizontal, EnsuSpacing.inputHorizontal)
                    .padding(.vertical, inputVerticalPadding)
                    .frame(maxWidth: .infinity)
                    .background(.ultraThinMaterial)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: EnsuCornerRadius.input + 4, style: .continuous)
                    )
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
                    .padding(.horizontal, EnsuSpacing.sm)
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

    private let composerIconSize: CGFloat = 16
    private func dismissInput() {
        isFocused = false
        hideKeyboard()
        onDismissKeyboard()
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
            return EnsuColor.sendButton
        }
        return isSendEnabled ? EnsuColor.sendButton : EnsuColor.sendButtonInactive
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
        .padding(.horizontal, EnsuSpacing.sm)
    }
}

struct InputBarHeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
