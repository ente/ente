package io.ente.ensu.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.shrinkVertically
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.scrollBy
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Popup
import androidx.compose.ui.window.PopupProperties
import io.ente.ensu.components.BranchSwitcher
import io.ente.ensu.components.ImageAttachmentThumbnail
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.chat.MessageAuthor
import io.ente.ensu.format.formatBytes
import io.ente.ensu.format.formattedFileSize
import io.ente.ensu.platform.rememberHaptics
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.distinctUntilChanged
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.roundToInt
import kotlin.math.roundToLong
import io.ente.ensu.llm.DownloadPhase

@Composable
internal fun MessageList(
    modifier: Modifier,
    messages: List<ChatMessage>,
    streamingResponse: String,
    streamingParentId: String?,
    isGenerating: Boolean,
    isModelDownloaded: Boolean,
    isModelStateKnown: Boolean,
    isChatUnsupported: Boolean,
    isDownloading: Boolean,
    downloadPercent: Int?,
    downloadStatus: String?,
    downloadPhase: DownloadPhase?,
    modelDownloadSizeBytes: Long?,
    branchSelections: Map<String, Int>,
    onEditMessage: (ChatMessage) -> Unit,
    onRetryMessage: (ChatMessage) -> Unit,
    onBranchChange: (String, Int) -> Unit,
    onOpenAttachment: (Attachment) -> Unit,
    onStartDownload: (Boolean) -> Unit
) {
    if (messages.isEmpty() && !isGenerating) {
        if (!isModelStateKnown) {
            return
        }
        if (!isModelDownloaded && !isChatUnsupported) {
            DownloadOnboarding(
                modifier = modifier,
                isDownloading = isDownloading,
                downloadPercent = downloadPercent,
                downloadStatus = downloadStatus,
                downloadPhase = downloadPhase,
                modelDownloadSizeBytes = modelDownloadSizeBytes,
                onDownload = { onStartDownload(true) }
            )
        } else {
            EmptyState(
                modifier = modifier,
                title = "Welcome",
                subtitle = "Type a message to start chatting"
            )
        }
        return
    }

    val listState = rememberLazyListState(
        initialFirstVisibleItemIndex = if (messages.isNotEmpty()) messages.size else 0
    )
    val haptic = rememberHaptics()
    var autoScrollEnabled by remember { mutableStateOf(true) }
    var isAutoScrolling by remember { mutableStateOf(false) }
    var didPerformStreamingStartHaptic by remember { mutableStateOf(false) }
    var shouldJumpToBottomOnLoad by remember { mutableStateOf(true) }
    var wasAtBottomBeforeResize by remember { mutableStateOf(true) }
    var lastViewportHeight by remember { mutableStateOf(0) }
    var lastUserMessageId by remember { mutableStateOf<String?>(null) }
    var previousScrollIndex by remember { mutableStateOf(listState.firstVisibleItemIndex) }
    var previousScrollOffset by remember { mutableStateOf(listState.firstVisibleItemScrollOffset) }
    val isAtBottom by remember {
        derivedStateOf {
            !listState.canScrollForward
        }
    }
    val bottomItemIndex by remember(messages.size, isGenerating) {
        derivedStateOf {
            messages.size +
                (if (isGenerating) 1 else 0) +
                (if (messages.isNotEmpty()) 1 else 0)
        }
    }

    val streamingAnchorId = if (isGenerating) streamingParentId else null

    val lastMessage = messages.lastOrNull()
    LaunchedEffect(isGenerating, streamingParentId) {
        if (isGenerating) {
            autoScrollEnabled = true
            didPerformStreamingStartHaptic = false
        }
    }

    LaunchedEffect(lastMessage?.id) {
        if (lastMessage == null) {
            lastUserMessageId = null
        } else if (lastMessage.author == MessageAuthor.User && lastMessage.id != lastUserMessageId) {
            lastUserMessageId = lastMessage.id
            if (!listState.isScrollInProgress || isAtBottom) {
                autoScrollEnabled = true
            }
        }
    }

    LaunchedEffect(messages.size) {
        if (shouldJumpToBottomOnLoad && messages.isNotEmpty()) {
            if (listState.firstVisibleItemIndex != bottomItemIndex) {
                listState.scrollToItem(bottomItemIndex)
            }
            shouldJumpToBottomOnLoad = false
        }
    }

    LaunchedEffect(listState) {
        snapshotFlow {
            Triple(
                listState.firstVisibleItemIndex,
                listState.firstVisibleItemScrollOffset,
                listState.isScrollInProgress
            )
        }.collect { (index, offset, isScrolling) ->
            if (isScrolling && !isAutoScrolling && !isAtBottom) {
                val movedTowardTop = index < previousScrollIndex ||
                    (index == previousScrollIndex && offset < previousScrollOffset)
                if (movedTowardTop) {
                    autoScrollEnabled = false
                }
            }
            previousScrollIndex = index
            previousScrollOffset = offset
        }
    }

    LaunchedEffect(isAtBottom) {
        if (isAtBottom) {
            autoScrollEnabled = true
        }
    }

    LaunchedEffect(streamingResponse, isGenerating) {
        if (!isGenerating || didPerformStreamingStartHaptic) return@LaunchedEffect
        if (hasVisibleStreamingContent(streamingResponse)) {
            haptic.perform(HapticFeedbackType.TextHandleMove)
            didPerformStreamingStartHaptic = true
        }
    }

    LaunchedEffect(messages.size, streamingResponse, streamingParentId, isGenerating, autoScrollEnabled) {
        if (!autoScrollEnabled) return@LaunchedEffect
        if (listState.isScrollInProgress && !isAutoScrolling) return@LaunchedEffect
        val targetIndex = bottomItemIndex
        if (targetIndex >= 0) {
            isAutoScrolling = true
            try {
                if (isGenerating) {
                    listState.animateScrollToItem(targetIndex)
                } else {
                    listState.scrollToItem(targetIndex)
                }
            } finally {
                isAutoScrolling = false
            }
        }
    }

    LaunchedEffect(listState) {
        snapshotFlow {
            val layoutInfo = listState.layoutInfo
            val viewportHeight = layoutInfo.viewportEndOffset - layoutInfo.viewportStartOffset
            viewportHeight to isAtBottom
        }
            .distinctUntilChanged()
            .collect { (viewportHeight, atBottom) ->
                if (viewportHeight <= 0) {
                    return@collect
                }
                if (lastViewportHeight != 0 && viewportHeight != lastViewportHeight) {
                    if (wasAtBottomBeforeResize) {
                        val totalItems = listState.layoutInfo.totalItemsCount
                        if (totalItems > 0) {
                            isAutoScrolling = true
                            try {
                                listState.scrollToItem(totalItems - 1)
                            } finally {
                                isAutoScrolling = false
                            }
                        }
                    } else if (viewportHeight < lastViewportHeight) {
                        val deltaPx = (lastViewportHeight - viewportHeight).toFloat()
                        if (deltaPx > 0f) {
                            autoScrollEnabled = false
                            isAutoScrolling = true
                            try {
                                listState.scrollBy(deltaPx)
                            } finally {
                                isAutoScrolling = false
                            }
                        }
                    }
                }
                lastViewportHeight = viewportHeight
                wasAtBottomBeforeResize = atBottom
            }
    }

    LazyColumn(
        modifier = modifier,
        state = listState,
        contentPadding = PaddingValues(
            top = EnsuSpacing.pageVertical.dp,
            bottom = (EnsuSpacing.xxxl + EnsuSpacing.xl).dp
        ),
        verticalArrangement = Arrangement.spacedBy(EnsuSpacing.lg.dp)
    ) {
        messages.forEach { message ->
            item(key = message.id) {
                when (message.author) {
                    MessageAuthor.User -> {
                        UserMessageBubble(
                            message = message,
                            branchSelections = branchSelections,
                            onEdit = { onEditMessage(message) },
                            onBranchChange = onBranchChange,
                            onOpenAttachment = onOpenAttachment
                        )
                    }
                    MessageAuthor.Assistant -> {
                        AssistantMessageBubble(
                            message = message,
                            isLastMessage = message == messages.last(),
                            branchSelections = branchSelections,
                            onRetry = { onRetryMessage(message) },
                            onBranchChange = onBranchChange,
                            showsMetadata = true
                        )
                    }
                }
            }

            if (isGenerating && streamingAnchorId == message.id) {
                item(key = "streaming") {
                    StreamingMessageBubble(
                        text = streamingResponse,
                        isGenerating = true
                    )
                }
            }
        }

        if (isGenerating && streamingAnchorId == null) {
            item(key = "streaming") {
                StreamingMessageBubble(
                    text = streamingResponse,
                    isGenerating = true
                )
            }
        }

        if (messages.isNotEmpty()) {
            item(key = "ai-safety-footer") {
                AiSafetyFooter()
            }
        }

        item(key = "bottom") {
            Spacer(modifier = Modifier.height(1.dp))
        }
    }
}

@Composable
private fun EmptyState(
    modifier: Modifier,
    title: String,
    subtitle: String? = null
) {
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = title,
                style = EnsuTypography.h2,
                color = EnsuColor.textPrimary(),
                textAlign = TextAlign.Center
            )
            if (subtitle != null) {
                Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
                Text(
                    text = subtitle,
                    style = EnsuTypography.body,
                    color = EnsuColor.textMuted(),
                    textAlign = TextAlign.Center
                )
            }
        }
    }
}

@Composable
private fun AiSafetyFooter() {
    Text(
        text = "Ensu can make mistakes. Please double-check key details.",
        style = EnsuTypography.small.copy(fontSize = 12.sp),
        color = EnsuColor.textMuted(),
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = EnsuSpacing.sm.dp)
    )
}

@Composable
private fun DownloadOnboarding(
    modifier: Modifier,
    isDownloading: Boolean,
    downloadPercent: Int?,
    downloadStatus: String?,
    downloadPhase: DownloadPhase?,
    modelDownloadSizeBytes: Long?,
    onDownload: () -> Unit
) {
    val haptic = rememberHaptics()
    val downloadAccent = EnsuColor.accentDark
    val downloadButtonTextColor = Color.Black
    val sizeText = modelDownloadSizeBytes?.let { "Approx. ${formatBytes(it)}" } ?: "Approx. size varies by model"
    Box(
        modifier = modifier.fillMaxSize(),
        contentAlignment = Alignment.Center
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(
                text = "Download to begin using the Chat",
                style = EnsuTypography.large,
                color = EnsuColor.textPrimary(),
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(EnsuSpacing.md.dp))
            if (isDownloading) {
                val isLoadingModel = downloadPhase == DownloadPhase.Loading
                val showProgress = downloadPercent != null || isLoadingModel
                val statusText = when {
                    isLoadingModel -> downloadStatus
                    modelDownloadSizeBytes != null && downloadPercent != null && downloadPercent >= 0 -> {
                        val downloadedBytes = (modelDownloadSizeBytes * (downloadPercent / 100f)).roundToLong()
                        "Downloading... ${formatBytes(downloadedBytes)} / ${formatBytes(modelDownloadSizeBytes)}"
                    }
                    !downloadStatus.isNullOrBlank() -> downloadStatus
                    else -> "Downloading..."
                }
                Text(
                    text = statusText ?: "Downloading...",
                    style = EnsuTypography.body.copy(fontFeatureSettings = "tnum"),
                    color = EnsuColor.textMuted(),
                    textAlign = TextAlign.Center
                )
                if (showProgress) {
                    Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
                    val clamped = downloadPercent?.coerceIn(0, 100)
                    if (clamped != null) {
                        LinearProgressIndicator(
                            progress = { clamped / 100f },
                            color = downloadAccent,
                            trackColor = EnsuColor.border(),
                            modifier = Modifier
                                .fillMaxWidth(0.6f)
                                .height(6.dp)
                        )
                    } else {
                        LinearProgressIndicator(
                            color = downloadAccent,
                            trackColor = EnsuColor.border(),
                            modifier = Modifier
                                .fillMaxWidth(0.6f)
                                .height(6.dp)
                        )
                    }
                }
            } else {
                if (!downloadStatus.isNullOrBlank()) {
                    Text(
                        text = downloadStatus,
                        style = EnsuTypography.body,
                        color = if (downloadPhase == DownloadPhase.Failed) {
                            EnsuColor.error
                        } else {
                            EnsuColor.textMuted()
                        },
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
                }
                Button(
                    onClick = {
                        haptic.perform(HapticFeedbackType.TextHandleMove)
                        onDownload()
                    },
                    shape = RoundedCornerShape(EnsuCornerRadius.button.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = downloadAccent)
                ) {
                    Text(text = "Download", style = EnsuTypography.body, color = downloadButtonTextColor)
                }
                Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
                Text(
                    text = sizeText,
                    style = EnsuTypography.small,
                    color = EnsuColor.textMuted()
                )
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun UserMessageBubble(
    message: ChatMessage,
    branchSelections: Map<String, Int>,
    onEdit: () -> Unit,
    onBranchChange: (String, Int) -> Unit,
    onOpenAttachment: (Attachment) -> Unit
) {
    val clipboard = LocalClipboardManager.current
    val haptic = rememberHaptics()
    var showMenu by remember { mutableStateOf(false) }
    var pressOffset by remember { mutableStateOf(Offset.Zero) }
    val bubbleShape = RoundedCornerShape(18.dp)
    val bubbleFill = if (isSystemInDarkTheme()) EnsuColor.fillFaint() else EnsuColor.border().copy(alpha = 0.2f)

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = EnsuSpacing.messageBubbleInset.dp),
        horizontalAlignment = Alignment.End
    ) {
        if (message.attachments.isNotEmpty()) {
            FlowRow(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp, Alignment.End),
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)
            ) {
                message.attachments.forEach { attachment ->
                    if (attachment.type == AttachmentType.Image && attachment.localPath != null) {
                        ImageAttachmentThumbnail(
                            path = attachment.localPath,
                            contentDescription = attachment.name,
                            width = 164.dp,
                            height = 124.dp,
                            portraitWidth = 124.dp,
                            portraitHeight = 164.dp,
                            squareSize = 140.dp,
                            isUploading = attachment.isUploading,
                            onClick = { onOpenAttachment(attachment) }
                        )
                    } else {
                        io.ente.ensu.components.AttachmentChip(
                            name = attachment.name,
                            size = if (attachment.localPath == null) {
                                "Unavailable on this device"
                            } else {
                                attachment.sizeBytes.formattedFileSize()
                            },
                            iconRes = HugeIcons.Attachment01Icon,
                            isUploading = attachment.isUploading,
                            onClick = if (attachment.localPath == null) null else {
                                { onOpenAttachment(attachment) }
                            }
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
        }

        Box {
            Column(
                modifier = Modifier
                    .background(bubbleFill, bubbleShape)
                    .pointerInput(Unit) {
                        detectTapGestures(
                            onLongPress = { offset ->
                                haptic.perform(HapticFeedbackType.LongPress)
                                pressOffset = offset
                                showMenu = true
                            }
                        )
                    }
                    .padding(EnsuSpacing.md.dp)
            ) {
                Text(
                    text = message.text,
                    style = EnsuTypography.message,
                    color = EnsuColor.userMessageText(),
                    textAlign = TextAlign.Start
                )
            }

            MessageActionsMenu(
                showMenu = showMenu,
                pressOffset = pressOffset,
                onDismiss = { showMenu = false },
                actions = listOf(
                    MessageAction("Edit", HugeIcons.Edit01Icon) {
                        haptic.perform(HapticFeedbackType.TextHandleMove)
                        onEdit()
                    },
                    MessageAction("Copy", HugeIcons.Copy01Icon) {
                        haptic.perform(HapticFeedbackType.TextHandleMove)
                        clipboard.setText(AnnotatedString(message.text))
                    }
                )
            )
        }

        Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))

        Row(verticalAlignment = Alignment.CenterVertically) {
            Spacer(modifier = Modifier.weight(1f))
            if (message.branchCount > 1) {
                BranchSwitcher(
                    currentIndex = branchSelections[message.id] ?: 1,
                    totalCount = message.branchCount,
                    onPrevious = {
                        val current = branchSelections[message.id] ?: 1
                        onBranchChange(message.id, (current - 1).coerceAtLeast(1))
                    },
                    onNext = {
                        val current = branchSelections[message.id] ?: 1
                        onBranchChange(message.id, (current + 1).coerceAtMost(message.branchCount))
                    }
                )
                Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
            }
            TimestampText(message.timestampMillis)
        }
    }
}

@Composable
private fun AssistantMessageBubble(
    message: ChatMessage,
    isLastMessage: Boolean,
    branchSelections: Map<String, Int>,
    onRetry: () -> Unit,
    onBranchChange: (String, Int) -> Unit,
    showsMetadata: Boolean
) {
    val clipboard = LocalClipboardManager.current
    val haptic = rememberHaptics()
    var showMenu by remember { mutableStateOf(false) }
    var pressOffset by remember { mutableStateOf(Offset.Zero) }
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.Start
    ) {
        val actions = buildList {
            if (!message.isSynthetic) {
                add(MessageAction("Copy", HugeIcons.Copy01Icon) {
                    haptic.perform(HapticFeedbackType.TextHandleMove)
                    clipboard.setText(AnnotatedString(stripHiddenMessageParts(message.text)))
                })
            }
            if (!message.isSynthetic || isLastMessage) {
                add(MessageAction("Retry", HugeIcons.RepeatIcon) {
                    haptic.perform(HapticFeedbackType.TextHandleMove)
                    onRetry()
                })
            }
        }

        Box {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .pointerInput(message.id, message.isSynthetic, isLastMessage) {
                        detectTapGestures(
                            onLongPress = { offset ->
                                if (actions.isEmpty()) return@detectTapGestures
                                haptic.perform(HapticFeedbackType.LongPress)
                                pressOffset = offset
                                showMenu = true
                            }
                        )
                    }
                    .padding(horizontal = EnsuSpacing.sm.dp, vertical = EnsuSpacing.md.dp)
            ) {
                MarkdownView(
                    markdown = stripHiddenMessageParts(message.text),
                    enableSelection = false
                )

                if (message.isInterrupted) {
                    Spacer(modifier = Modifier.height(EnsuSpacing.xs.dp))
                    Text(
                        text = "Interrupted",
                        style = EnsuTypography.small,
                        color = EnsuColor.textMuted()
                    )
                }
            }

            MessageActionsMenu(
                showMenu = showMenu,
                pressOffset = pressOffset,
                onDismiss = { showMenu = false },
                actions = actions
            )
        }

        AnimatedVisibility(
            visible = showsMetadata,
            enter = fadeIn(animationSpec = tween(durationMillis = 300)),
            exit = fadeOut(animationSpec = tween(durationMillis = 150))
        ) {
            Column {
                Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp), verticalAlignment = Alignment.CenterVertically) {
                    TimestampText(message.timestampMillis)
                    if (message.branchCount > 1) {
                        BranchSwitcher(
                            currentIndex = branchSelections[message.id] ?: 1,
                            totalCount = message.branchCount,
                            onPrevious = {
                                val current = branchSelections[message.id] ?: 1
                                onBranchChange(message.id, (current - 1).coerceAtLeast(1))
                            },
                            onNext = {
                                val current = branchSelections[message.id] ?: 1
                                onBranchChange(message.id, (current + 1).coerceAtMost(message.branchCount))
                            }
                        )
                    }
                }
            }
        }
    }
}

private data class MessageAction(
    val label: String,
    val iconRes: Int,
    val onClick: () -> Unit
)

@Composable
private fun MessageActionsMenu(
    showMenu: Boolean,
    pressOffset: Offset,
    onDismiss: () -> Unit,
    actions: List<MessageAction>
) {
    if (!showMenu || actions.isEmpty()) return
    val menuSurface = if (isSystemInDarkTheme()) Color(0xFF1C1C1E) else Color.White
    val offset = IntOffset(pressOffset.x.roundToInt(), pressOffset.y.roundToInt())

    Popup(
        alignment = Alignment.TopStart,
        offset = offset,
        onDismissRequest = onDismiss,
        properties = PopupProperties(focusable = true)
    ) {
        Surface(
            modifier = Modifier.wrapContentSize(),
            color = menuSurface,
            shadowElevation = 4.dp,
            shape = RoundedCornerShape(12.dp)
        ) {
            Column(
                modifier = Modifier
                    .width(IntrinsicSize.Min)
                    .padding(vertical = EnsuSpacing.xs.dp)
            ) {
                actions.forEach { action ->
                    DropdownMenuItem(
                        text = {
                            Text(
                                text = action.label,
                                style = EnsuTypography.body,
                                color = EnsuColor.textPrimary()
                            )
                        },
                        leadingIcon = {
                            Icon(
                                painter = androidx.compose.ui.res.painterResource(action.iconRes),
                                contentDescription = null,
                                modifier = Modifier.size(18.dp),
                                tint = EnsuColor.textPrimary()
                            )
                        },
                        onClick = {
                            onDismiss()
                            action.onClick()
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun StreamingMessageBubble(
    text: String,
    isGenerating: Boolean
) {
    var renderedText by remember { mutableStateOf(text) }
    var showCursor by remember { mutableStateOf(true) }
    val hasText = renderedText.isNotBlank()
    val shouldBlink = isGenerating && hasText

    LaunchedEffect(shouldBlink) {
        if (!shouldBlink) {
            showCursor = true
            return@LaunchedEffect
        }
        while (true) {
            delay(520)
            showCursor = !showCursor
        }
    }

    LaunchedEffect(text, isGenerating) {
        if (!isGenerating) {
            renderedText = ""
            return@LaunchedEffect
        }
        if (text.isBlank()) {
            renderedText = ""
            return@LaunchedEffect
        }
        // Throttle markdown re-rendering while streaming to reduce dropped frames.
        delay(33)
        renderedText = stripHiddenMessageParts(text)
    }

    if (!isGenerating) return

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = EnsuSpacing.sm.dp)
            .padding(vertical = if (hasText) EnsuSpacing.md.dp else 0.dp),
        horizontalAlignment = Alignment.Start,
        verticalArrangement = Arrangement.spacedBy(if (hasText) EnsuSpacing.sm.dp else 0.dp)
    ) {
        if (hasText) {
            MarkdownView(markdown = renderedText, enableSelection = false, trailingCursor = showCursor)
        }

        generatingDotsIndicator()
    }
}

@Composable
private fun generatingDotsIndicator() {
    var dotCount by remember { mutableStateOf(1) }

    LaunchedEffect(Unit) {
        while (true) {
            delay(420)
            dotCount = if (dotCount == 3) 1 else dotCount + 1
        }
    }

    Text(
        text = ".".repeat(dotCount),
        style = EnsuTypography.message,
        color = EnsuColor.textMuted(),
        modifier = Modifier.widthIn(min = 24.dp)
    )
}

private fun stripHiddenMessageParts(text: String): String {
    return text
        .replace(Regex("<think>[\\s\\S]*?</think>"), "")
        .replace(Regex("<todo_list>[\\s\\S]*?</todo_list>"), "")
        .trim()
}

private fun hasVisibleStreamingContent(text: String): Boolean {
    return stripHiddenMessageParts(text)
        .replace(Regex("<think>[\\s\\S]*"), "")
        .replace(Regex("<todo_list>[\\s\\S]*"), "")
        .isNotBlank()
}

@Composable
private fun TimestampText(timestampMillis: Long) {
    Text(
        text = timestampFormatter.format(Date(timestampMillis)),
        style = EnsuTypography.mini,
        color = EnsuColor.textMuted()
    )
}

private val timestampFormatter = SimpleDateFormat("h:mm a", Locale.getDefault())
