package io.ente.ensu.chat

import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ErrorOutline
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.components.ImageAttachmentThumbnail
import io.ente.ensu.chat.Attachment
import io.ente.ensu.chat.AttachmentType
import io.ente.ensu.chat.ChatMessage
import io.ente.ensu.chat.MaxImageAttachmentsPerMessage
import io.ente.ensu.format.formattedFileSize
import io.ente.ensu.platform.rememberHaptics
import kotlinx.coroutines.delay

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun MessageInput(
    modifier: Modifier,
    messageText: String,
    attachments: List<Attachment>,
    editingMessage: ChatMessage?,
    isProcessingAttachments: Boolean,
    isGenerating: Boolean,
    isDownloading: Boolean,
    onMessageChange: (String) -> Unit,
    onSend: () -> Unit,
    onStop: () -> Unit,
    onAttachmentSelected: (AttachmentType) -> Unit,
    onRemoveAttachment: (Attachment) -> Unit,
    onCancelEdit: () -> Unit,
    voiceInputState: VoiceInputState,
    onVoiceInput: () -> Unit,
    focusRequestId: Int
) {
    val haptic = rememberHaptics()
    val placeholder = "Write a message..."

    val focusRequester = remember { FocusRequester() }
    var fieldValue by remember {
        mutableStateOf(
            TextFieldValue(
                text = messageText,
                selection = TextRange(messageText.length)
            )
        )
    }

    LaunchedEffect(messageText) {
        if (messageText != fieldValue.text) {
            fieldValue = TextFieldValue(
                text = messageText,
                selection = TextRange(messageText.length)
            )
        }
    }

    LaunchedEffect(focusRequestId) {
        if (focusRequestId > 0) {
            // Give the screen a moment to settle so IME shows reliably.
            delay(120)
            focusRequester.requestFocus()
        }
    }

    val hasAttachmentContent = attachments.isNotEmpty() || isProcessingAttachments
    val inputVerticalPadding = if (hasAttachmentContent) EnsuSpacing.xs.dp else 10.dp
    val bottomPadding = if (hasAttachmentContent) EnsuSpacing.sm.dp else EnsuSpacing.md.dp
    val isImageAttachmentLimitReached =
        attachments.count { it.type == AttachmentType.Image } >= MaxImageAttachmentsPerMessage

    Column(
        modifier = modifier
            .background(EnsuColor.backgroundBase()),
        verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)
    ) {
        if (editingMessage != null) {
            EditBanner(message = editingMessage, onCancelEdit = onCancelEdit)
        }

        if (attachments.isNotEmpty()) {
            val maxAttachmentHeight = 140.dp
            FlowRow(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = maxAttachmentHeight)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = EnsuSpacing.pageHorizontal.dp),
                horizontalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp),
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)
            ) {
                attachments.forEach { attachment ->
                    if (attachment.type == AttachmentType.Image && attachment.localPath != null) {
                        ImageAttachmentThumbnail(
                            path = attachment.localPath,
                            contentDescription = attachment.name,
                            width = 76.dp,
                            height = 76.dp,
                            isUploading = attachment.isUploading,
                            onDelete = { onRemoveAttachment(attachment) }
                        )
                    } else {
                        io.ente.ensu.components.AttachmentChip(
                            name = attachment.name,
                            size = attachment.sizeBytes.formattedFileSize(),
                            iconRes = HugeIcons.Attachment01Icon,
                            isUploading = attachment.isUploading,
                            onDelete = { onRemoveAttachment(attachment) }
                        )
                    }
                }
            }
        }

        if (isProcessingAttachments) {
            Row(
                modifier = Modifier.padding(horizontal = EnsuSpacing.pageHorizontal.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
                Text(text = "Reading attachment...", style = EnsuTypography.small)
            }
        }

        voiceInputState.statusText()?.let { status ->
            Row(
                modifier = Modifier.padding(horizontal = EnsuSpacing.pageHorizontal.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                when (voiceInputState) {
                    is VoiceInputState.Downloading,
                    VoiceInputState.Transcribing -> {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                    }
                    VoiceInputState.Recording -> {
                        Icon(
                            painter = painterResource(HugeIcons.Mic02Icon),
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = EnsuColor.stopButton
                        )
                    }
                    is VoiceInputState.Error -> {
                        Icon(
                            imageVector = Icons.Rounded.ErrorOutline,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = EnsuColor.stopButton
                        )
                    }
                    VoiceInputState.Idle -> Unit
                }
                Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
                Text(
                    text = status,
                    style = EnsuTypography.small,
                    color = if (voiceInputState is VoiceInputState.Error) {
                        EnsuColor.stopButton
                    } else {
                        EnsuColor.textMuted()
                    }
                )
            }
        }

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = EnsuSpacing.pageHorizontal.dp)
                .padding(bottom = bottomPadding)
                .background(EnsuColor.fillFaint(), RoundedCornerShape((EnsuCornerRadius.input + 4).dp))
                .padding(
                    horizontal = EnsuSpacing.inputHorizontal.dp,
                    vertical = inputVerticalPadding
                )
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BasicTextField(
                    value = fieldValue,
                    onValueChange = { newValue ->
                        fieldValue = newValue
                        onMessageChange(newValue.text)
                    },
                    modifier = Modifier
                        .weight(1f)
                        .focusRequester(focusRequester)
                        .focusable(),
                    textStyle = EnsuTypography.message.copy(color = EnsuColor.textPrimary()),
                    minLines = 1,
                    maxLines = 5,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
                    cursorBrush = SolidColor(EnsuColor.accent())
                ) { innerTextField ->
                    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.CenterStart) {
                        if (fieldValue.text.isBlank()) {
                            Text(
                                text = placeholder,
                                style = EnsuTypography.message,
                                color = EnsuColor.textMuted()
                            )
                        }
                        innerTextField()
                    }
                }

                Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))

                if (editingMessage == null) {
                    val canAddImageAttachment = !isGenerating &&
                        !isDownloading &&
                        !isImageAttachmentLimitReached
                    IconButton(
                        onClick = {
                            haptic.perform(HapticFeedbackType.TextHandleMove)
                            onAttachmentSelected(AttachmentType.Image)
                        },
                        enabled = canAddImageAttachment,
                        modifier = Modifier.size(36.dp)
                    ) {
                        Icon(
                            painter = painterResource(HugeIcons.Upload01Icon),
                            contentDescription = "Attach",
                            modifier = Modifier.size(18.dp)
                        )
                    }
                }

                if (editingMessage == null) {
                    val isVoiceBusy = voiceInputState is VoiceInputState.Downloading ||
                        voiceInputState is VoiceInputState.Transcribing
                    val canUseVoice = voiceInputState.isRecording ||
                        (!isGenerating &&
                            !isDownloading &&
                            !isVoiceBusy)

                    IconButton(
                        onClick = {
                            haptic.perform(
                                if (voiceInputState.isRecording) {
                                    HapticFeedbackType.LongPress
                                } else {
                                    HapticFeedbackType.TextHandleMove
                                }
                            )
                            onVoiceInput()
                        },
                        enabled = canUseVoice,
                        modifier = Modifier.size(36.dp)
                    ) {
                        if (isVoiceBusy) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp)
                        } else if (voiceInputState.isRecording) {
                            Icon(
                                painter = painterResource(HugeIcons.StopIcon),
                                contentDescription = "Stop dictation",
                                modifier = Modifier.size(18.dp),
                                tint = EnsuColor.stopButton
                            )
                        } else {
                            Icon(
                                painter = painterResource(HugeIcons.Mic02Icon),
                                contentDescription = "Dictate",
                                modifier = Modifier.size(18.dp)
                            )
                        }
                    }
                }

                val canSend = (messageText.isNotBlank() || attachments.isNotEmpty()) &&
                    !voiceInputState.blocksSend

                IconButton(
                    onClick = {
                        if (isGenerating) {
                            haptic.perform(HapticFeedbackType.LongPress)
                            onStop()
                        } else {
                            haptic.perform(HapticFeedbackType.TextHandleMove)
                            onSend()
                        }
                    },
                    enabled = isGenerating || (!isDownloading && canSend),
                    modifier = Modifier.size(36.dp)
                ) {
                    val iconRes = when {
                        isGenerating -> HugeIcons.StopIcon
                        else -> HugeIcons.Navigation06Icon
                    }
                    val tint = when {
                        isGenerating -> EnsuColor.stopButton
                        canSend -> EnsuColor.textPrimary()
                        else -> EnsuColor.textMuted()
                    }
                    val rotation = if (iconRes == HugeIcons.Navigation06Icon) 90f else 0f
                    if (iconRes == HugeIcons.StopIcon) {
                        Box(
                            modifier = Modifier
                                .size(22.dp)
                                .background(Color.White, CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                painter = painterResource(iconRes),
                                contentDescription = "Send",
                                modifier = Modifier.size(12.dp),
                                tint = EnsuColor.stopButton
                            )
                        }
                    } else {
                        Icon(
                            painter = painterResource(iconRes),
                            contentDescription = "Send",
                            modifier = Modifier.size(18.dp).rotate(rotation),
                            tint = tint
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EditBanner(message: ChatMessage, onCancelEdit: () -> Unit) {
    val haptic = rememberHaptics()
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = EnsuSpacing.pageHorizontal.dp)
            .background(EnsuColor.fillFaint(), RoundedCornerShape(EnsuCornerRadius.input.dp))
            .height(IntrinsicSize.Min)
    ) {
        Box(
            modifier = Modifier
                .fillMaxHeight()
                .width(3.dp)
                .background(EnsuColor.accent())
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = EnsuSpacing.md.dp, vertical = EnsuSpacing.sm.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                painter = painterResource(HugeIcons.Edit01Icon),
                contentDescription = null,
                tint = EnsuColor.action(),
                modifier = Modifier.size(14.dp)
            )
            Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
            Text(
                text = "Editing:",
                style = EnsuTypography.small,
                color = EnsuColor.textMuted()
            )
            Spacer(modifier = Modifier.width(EnsuSpacing.xs.dp))
            Text(
                text = message.text,
                style = EnsuTypography.small,
                color = EnsuColor.textPrimary(),
                maxLines = 1,
                overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f)
            )
            IconButton(
                onClick = {
                    haptic.perform(HapticFeedbackType.TextHandleMove)
                    onCancelEdit()
                },
                modifier = Modifier.size(24.dp)
            ) {
                Icon(
                    painter = painterResource(HugeIcons.Cancel01Icon),
                    contentDescription = "Cancel edit",
                    tint = EnsuColor.textMuted()
                )
            }
        }
    }
}
