package io.ente.ensu.chat

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import io.ente.ensu.bindings.Transcriber
import io.ente.ensu.llm.ModelDownloader
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.device.ChatDeviceCapability
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.chat.ChatState
import kotlinx.coroutines.delay

@Composable
fun ChatView(
    chatState: ChatState,
    modelDownloader: ModelDownloader,
    transcriber: Transcriber,
    isDrawerOpen: Boolean,
    onMessageChange: (String) -> Unit,
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
    onOverflowCancel: () -> Unit
) {
    val density = LocalDensity.current
    val context = LocalContext.current
    var inputBarHeightDp by remember { mutableStateOf(0.dp) }
    val latestMessageText by rememberUpdatedState(chatState.messageText)
    val latestOnMessageChange by rememberUpdatedState(onMessageChange)
    val sessionKey = chatState.currentSessionId ?: "new-session"
    val latestSessionKey by rememberUpdatedState(sessionKey)
    val unsupportedCapability = chatState.deviceCapability as? ChatDeviceCapability.UnsupportedLowMemory
    val isChatUnsupported = unsupportedCapability != null
    var pendingVoiceSessionKey by remember { mutableStateOf<String?>(null) }
    val voiceController = rememberVoiceTranscriptionController(
        modelDownloader = modelDownloader,
        transcriber = transcriber,
        onTranscript = { transcript ->
            latestOnMessageChange(appendVoiceTranscript(latestMessageText, transcript))
        }
    )

    val editingMessage by remember(chatState.editingMessageId, chatState.messages) {
        derivedStateOf {
            chatState.editingMessageId?.let { editingId ->
                chatState.messages.firstOrNull { it.id == editingId }
            }
        }
    }
    val canStartVoiceInput = !chatState.isGenerating &&
        !chatState.isDownloading &&
        !isChatUnsupported &&
        editingMessage == null
    val latestCanStartVoiceInput by rememberUpdatedState(canStartVoiceInput)

    val microphonePermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission()
    ) { granted ->
        val requestedSessionKey = pendingVoiceSessionKey
        pendingVoiceSessionKey = null
        if (granted) {
            if (requestedSessionKey != null) {
                voiceController.startRecording {
                    latestSessionKey == requestedSessionKey && latestCanStartVoiceInput
                }
            }
        } else {
            voiceController.onPermissionDenied()
        }
    }

    val showDownloadOnboarding by remember(
        chatState.isModelDownloaded,
        chatState.isModelStateKnown,
        chatState.messages,
        chatState.isGenerating,
        isChatUnsupported
    ) {
        derivedStateOf {
            chatState.isModelStateKnown &&
                !chatState.isModelDownloaded &&
                chatState.messages.isEmpty() &&
                !chatState.isGenerating &&
                !isChatUnsupported
        }
    }

    val focusManager = LocalFocusManager.current
    var didAutoFocusInput by remember { mutableStateOf(false) }
    var focusRequestId by remember { mutableStateOf(0) }
    var wasDrawerOpen by remember { mutableStateOf(false) }

    val shouldAutoFocusInput = chatState.isModelDownloaded &&
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
            val shouldRestoreFocus = chatState.isModelDownloaded &&
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

    LaunchedEffect(sessionKey) {
        pendingVoiceSessionKey = null
        voiceController.cancelActiveVoiceInput()
    }

    Box(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
        ) {
            AnimatedContent(
                targetState = sessionKey,
                modifier = Modifier
                    .weight(1f),
                transitionSpec = {
                    val enter = fadeIn(animationSpec = tween(220, easing = FastOutSlowInEasing)) +
                        slideInVertically(animationSpec = tween(320, easing = FastOutSlowInEasing)) {
                            it / 12
                        }
                    val exit = fadeOut(animationSpec = tween(220, easing = FastOutSlowInEasing)) +
                        slideOutVertically(animationSpec = tween(320, easing = FastOutSlowInEasing)) {
                            -it / 12
                        }
                    enter.togetherWith(exit)
                },
                label = "session-change"
            ) { targetSessionKey ->
                key(targetSessionKey) {
                    MessageList(
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(
                                start = EnsuSpacing.pageHorizontal.dp,
                                end = EnsuSpacing.pageHorizontal.dp
                            ),
                        messages = chatState.messages,
                        streamingResponse = chatState.streamingResponse,
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
                        onStartDownload = onStartDownload
                    )
                }
            }

            if (chatState.overflowDialog != null) {
                OverflowDialog(
                    onTrim = onOverflowTrim,
                    onCancel = onOverflowCancel
                )
            }

            if (unsupportedCapability != null) {
                UnsupportedChatInputNotice(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .background(EnsuColor.backgroundBase())
                        .onGloballyPositioned { coords ->
                            inputBarHeightDp = with(density) { coords.size.height.toDp() }
                        }
                )
            } else if (chatState.isModelStateKnown && !showDownloadOnboarding) {
                MessageInput(
                    modifier = Modifier
                        .fillMaxWidth()
                        .navigationBarsPadding()
                        .background(EnsuColor.backgroundBase())
                        .onGloballyPositioned { coords ->
                            inputBarHeightDp = with(density) { coords.size.height.toDp() }
                        },
                    messageText = chatState.messageText,
                    attachments = chatState.attachments,
                    editingMessage = editingMessage,
                    isProcessingAttachments = chatState.isProcessingAttachments,
                    isGenerating = chatState.isGenerating,
                    isDownloading = chatState.isDownloading,
                    onMessageChange = onMessageChange,
                    onSend = {
                        focusManager.clearFocus()
                        onSend()
                    },
                    onStop = onStop,
                    onAttachmentSelected = onAttachmentSelected,
                    onRemoveAttachment = onRemoveAttachment,
                    onCancelEdit = onCancelEdit,
                    voiceInputState = voiceController.state,
                    onVoiceInput = {
                        if (voiceController.state.isRecording) {
                            voiceController.stopAndTranscribe()
                        } else {
                            val hasMicrophonePermission = ContextCompat.checkSelfPermission(
                                context,
                                Manifest.permission.RECORD_AUDIO
                            ) == PackageManager.PERMISSION_GRANTED
                            if (canStartVoiceInput && hasMicrophonePermission) {
                                val requestedSessionKey = sessionKey
                                voiceController.startRecording {
                                    latestSessionKey == requestedSessionKey && latestCanStartVoiceInput
                                }
                            } else if (canStartVoiceInput) {
                                pendingVoiceSessionKey = sessionKey
                                microphonePermissionLauncher.launch(Manifest.permission.RECORD_AUDIO)
                            }
                        }
                    },
                    focusRequestId = focusRequestId
                )
            }
        }

        if (chatState.showUnsupportedDeviceDialog && unsupportedCapability != null) {
            UnsupportedDeviceDialog(
                onDismiss = onDismissUnsupportedDeviceDialog
            )
        }

        val imeVisible = WindowInsets.ime.getBottom(density) > 0
        if (imeVisible && inputBarHeightDp > 0.dp) {
            IconButton(
                onClick = { focusManager.clearFocus() },
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .imePadding()
                    .padding(
                        end = EnsuSpacing.pageHorizontal.dp,
                        bottom = inputBarHeightDp + EnsuSpacing.sm.dp
                    )
                    .background(
                        color = EnsuColor.fillFaint(),
                        shape = CircleShape
                    )
            ) {
                Icon(
                    imageVector = Icons.Rounded.KeyboardArrowDown,
                    contentDescription = "Dismiss keyboard",
                    modifier = Modifier.padding(7.dp),
                    tint = EnsuColor.textPrimary()
                )
            }
        }

        val status = chatState.downloadStatus
        val isLoading = status?.contains("Loading", ignoreCase = true) == true
        val showToast by remember(status, chatState.isDownloading, showDownloadOnboarding, isLoading) {
            derivedStateOf {
                !showDownloadOnboarding &&
                    status != null &&
                    chatState.isDownloading &&
                    !isLoading
            }
        }
        if (showToast) {
            DownloadToastOverlay(
                status = status ?: "",
                percent = chatState.downloadPercent ?: 0,
                totalBytes = chatState.modelDownloadSizeBytes,
                isLoading = isLoading,
                onCancel = onCancelDownload
            )
        }
    }
}

private fun appendVoiceTranscript(currentText: String, transcript: String): String {
    val cleaned = transcript.trim()
    if (cleaned.isBlank()) {
        return currentText
    }
    val trimmedDraft = currentText.trimEnd()
    if (trimmedDraft.isBlank()) {
        return cleaned
    }
    return "$trimmedDraft $cleaned"
}
