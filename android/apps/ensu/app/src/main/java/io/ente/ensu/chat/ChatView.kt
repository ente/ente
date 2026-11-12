package io.ente.ensu.chat

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.ime
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.device.ChatDeviceCapability

@Composable
internal fun ChatView(
    chatState: ChatState,
    voiceController: VoiceTranscriptionController,
    onOpenVoiceInput: (androidx.compose.ui.text.input.TextFieldValue) -> Unit,
    isDrawerOpen: Boolean,
    onMessageChange: (String) -> Unit,
    onComposerSelection: (Int, Int, Boolean) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
    onCancelDownload: () -> Unit,
    onAttachmentSelected: (AttachmentType) -> Unit,
    onRemoveAttachment: (Attachment) -> Unit,
    onEditMessage: (ChatMessage) -> Unit,
    onRetryMessage: (ChatMessage) -> Unit,
    onCancelEdit: () -> Unit,
    onBranchChange: (String, Int) -> Unit,
    onOpenAttachment: (Attachment) -> Unit,
    onStartDownload: (Boolean) -> Unit,
    onDismissUnsupportedDeviceDialog: () -> Unit,
    onOverflowTrim: () -> Unit,
    onOverflowCancel: () -> Unit,
    onOpenPacks: () -> Unit,
    onOpenNotes: () -> Unit,
    hasSeenSourceIntroduction: Boolean,
    onCompleteSourceIntroduction: () -> Unit,
    onRetrySources: () -> Unit,
) {
    val density = LocalDensity.current
    var inputBarHeightDp by remember { mutableStateOf(0.dp) }
    val sessionKey = chatState.currentSessionId ?: "new-session"
    var introductionSeen by
        remember(hasSeenSourceIntroduction) { mutableStateOf(hasSeenSourceIntroduction) }
    val unsupportedCapability =
        chatState.deviceCapability as? ChatDeviceCapability.UnsupportedLowMemory
    val isChatUnsupported = unsupportedCapability != null
    val editingMessage by
        remember(chatState.editingMessageId, chatState.messages) {
            derivedStateOf {
                chatState.editingMessageId?.let { editingId ->
                    chatState.messages.firstOrNull { it.id == editingId }
                }
            }
        }
    val showDownloadOnboarding by
        remember(
            chatState.isModelDownloaded,
            chatState.isModelStateKnown,
            chatState.isGenerating,
            isChatUnsupported,
        ) {
            derivedStateOf {
                chatState.isModelStateKnown &&
                    !chatState.isModelDownloaded &&
                    !chatState.isGenerating &&
                    !isChatUnsupported
            }
        }

    val focusManager = LocalFocusManager.current
    var didAutoFocusInput by remember { mutableStateOf(false) }
    var focusRequestId by remember { mutableIntStateOf(0) }
    var wasDrawerOpen by remember { mutableStateOf(false) }

    val showIntroduction =
        !introductionSeen &&
            chatState.isModelDownloaded &&
            !chatState.isDownloading &&
            !chatState.isGenerating &&
            !isChatUnsupported &&
            !isDrawerOpen

    val shouldAutoFocusInput =
        !showIntroduction &&
            chatState.isModelDownloaded &&
            !showDownloadOnboarding &&
            !isChatUnsupported &&
            !chatState.isDownloading &&
            !chatState.isGenerating &&
            !didAutoFocusInput &&
            !isDrawerOpen

    LaunchedEffect(shouldAutoFocusInput, isDrawerOpen) {
        if (isDrawerOpen) {
            focusManager.clearFocus()
            wasDrawerOpen = true
            return@LaunchedEffect
        }

        if (shouldAutoFocusInput) {
            focusRequestId += 1
            didAutoFocusInput = true
            wasDrawerOpen = false
            return@LaunchedEffect
        }

        if (wasDrawerOpen) {
            val shouldRestoreFocus =
                chatState.isModelDownloaded &&
                    !showDownloadOnboarding &&
                    !isChatUnsupported &&
                    !chatState.isDownloading &&
                    !chatState.isGenerating
            if (shouldRestoreFocus) {
                focusRequestId += 1
            }
            wasDrawerOpen = false
        }
    }

    if (showIntroduction) {
        SourceIntroductionSheet(
            onDismiss = {
                onCompleteSourceIntroduction()
                introductionSeen = true
            },
            onOpenPacks = onOpenPacks,
            onOpenNotes = onOpenNotes,
        )
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(modifier = Modifier.fillMaxSize().imePadding()) {
            AnimatedContent(
                targetState = sessionKey,
                modifier = Modifier.weight(1f),
                transitionSpec = {
                    val enter =
                        fadeIn(animationSpec = tween(220, easing = FastOutSlowInEasing)) +
                            slideInVertically(
                                animationSpec = tween(320, easing = FastOutSlowInEasing)
                            ) {
                                it / 12
                            }
                    val exit =
                        fadeOut(animationSpec = tween(220, easing = FastOutSlowInEasing)) +
                            slideOutVertically(
                                animationSpec = tween(320, easing = FastOutSlowInEasing)
                            ) {
                                -it / 12
                            }
                    enter.togetherWith(exit)
                },
                label = "session-change",
            ) { targetSessionKey ->
                key(targetSessionKey) {
                    MessageList(
                        modifier =
                            Modifier.fillMaxSize()
                                .padding(
                                    start = EnsuSpacing.pageHorizontal.dp,
                                    end = EnsuSpacing.pageHorizontal.dp,
                                ),
                        messages = chatState.messages,
                        streamingResponse = chatState.streamingResponse,
                        preparationStatus = chatState.preparationStatus,
                        streamingParentId = chatState.streamingParentId,
                        isGenerating = chatState.isGenerating,
                        isModelDownloaded = chatState.isModelDownloaded,
                        isModelStateKnown = chatState.isModelStateKnown,
                        isChatUnsupported = isChatUnsupported,
                        isDownloading = chatState.isDownloading,
                        downloadPercent = chatState.downloadPercent,
                        downloadStatus = chatState.downloadStatus,
                        downloadPhase = chatState.downloadPhase,
                        modelDownloadSizeBytes = chatState.modelDownloadSizeBytes,
                        branchSelections = chatState.branchSelections,
                        onEditMessage = onEditMessage,
                        onRetryMessage = onRetryMessage,
                        onBranchChange = onBranchChange,
                        onOpenAttachment = onOpenAttachment,
                        onStartDownload = onStartDownload,
                    )
                }
            }

            if (chatState.overflowDialog != null) {
                OverflowDialog(
                    onTrim = onOverflowTrim,
                    onCancel = onOverflowCancel,
                )
            }

            if (unsupportedCapability != null) {
                UnsupportedChatInputNotice(
                    modifier =
                        Modifier.fillMaxWidth()
                            .navigationBarsPadding()
                            .background(EnsuColor.backgroundBase())
                            .onGloballyPositioned { coords ->
                                inputBarHeightDp = with(density) { coords.size.height.toDp() }
                            }
                )
            } else if (chatState.isModelStateKnown && !showDownloadOnboarding) {
                val voicePreview = voiceController.composerPreview(chatState.messageText)
                MessageInput(
                    modifier =
                        Modifier.fillMaxWidth()
                            .navigationBarsPadding()
                            .background(EnsuColor.backgroundBase())
                            .onGloballyPositioned { coords ->
                                inputBarHeightDp = with(density) { coords.size.height.toDp() }
                            },
                    messageText = voicePreview?.text ?: chatState.messageText,
                    attachments = chatState.attachments,
                    supportsImageAttachments = chatState.supportsImageAttachments,
                    editingMessage = editingMessage,
                    isProcessingAttachments = chatState.isProcessingAttachments,
                    isGenerating = chatState.isGenerating,
                    isDownloading = chatState.isDownloading,
                    sourcesReady = chatState.sourceSelectionReady,
                    sourcesError = chatState.sourceSelectionError,
                    onRetrySources = onRetrySources,
                    onMessageChange = onMessageChange,
                    onComposerSelection = onComposerSelection,
                    onSend = {
                        focusManager.clearFocus()
                        onSend()
                    },
                    onStop = onStop,
                    onAttachmentSelected = onAttachmentSelected,
                    onRemoveAttachment = onRemoveAttachment,
                    onCancelEdit = onCancelEdit,
                    voiceController = voiceController,
                    onVoiceInput = onOpenVoiceInput,
                    voiceCaret = voicePreview?.caretUtf16?.toInt() ?: voiceController.composerCaret,
                    focusRequestId = focusRequestId,
                )
            }
        }

        if (chatState.showUnsupportedDeviceDialog && unsupportedCapability != null) {
            UnsupportedDeviceDialog(onDismiss = onDismissUnsupportedDeviceDialog)
        }

        val imeVisible = WindowInsets.ime.getBottom(density) > 0
        if (imeVisible && inputBarHeightDp > 0.dp) {
            IconButton(
                onClick = { focusManager.clearFocus() },
                modifier =
                    Modifier.align(Alignment.BottomEnd)
                        .imePadding()
                        .padding(
                            end = EnsuSpacing.pageHorizontal.dp,
                            bottom = inputBarHeightDp + EnsuSpacing.sm.dp,
                        )
                        .background(
                            color = EnsuColor.fillFaint(),
                            shape = CircleShape,
                        ),
            ) {
                Icon(
                    imageVector = Icons.Rounded.KeyboardArrowDown,
                    contentDescription = "Dismiss keyboard",
                    modifier = Modifier.padding(7.dp),
                    tint = EnsuColor.textPrimary(),
                )
            }
        }

        val status = chatState.downloadStatus
        val isLoading = status?.contains("Loading", ignoreCase = true) == true
        val showToast by
            remember(status, chatState.isDownloading, showDownloadOnboarding, isLoading) {
                derivedStateOf {
                    !showDownloadOnboarding &&
                        status != null &&
                        chatState.isDownloading &&
                        !isLoading
                }
            }
        if (showToast) {
            DownloadToastOverlay(
                status = status.orEmpty(),
                percent = chatState.downloadPercent ?: 0,
                totalBytes = chatState.modelDownloadSizeBytes,
                isLoading = isLoading,
                onCancel = onCancelDownload,
            )
        }
    }
}
