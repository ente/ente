package io.ente.ensu.chat

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.format.formatBytes
import io.ente.ensu.platform.rememberHaptics
import kotlin.math.roundToLong

@Composable
internal fun OverflowDialog(
    onTrim: () -> Unit,
    onCancel: () -> Unit
) {
    val overflowMessage = "This conversation is too long for the model to process. Some older messages will be dropped to make room."

    AlertDialog(
        onDismissRequest = onCancel,
        title = { Text(text = "Conversation too long", style = EnsuTypography.h3) },
        text = {
            Text(
                text = overflowMessage,
                style = EnsuTypography.body,
                color = EnsuColor.textPrimary()
            )
        },
        confirmButton = {
            TextButton(onClick = onTrim) {
                Text(text = "Continue", color = EnsuColor.textPrimary())
            }
        },
        dismissButton = {
            TextButton(onClick = onCancel) {
                Text(text = "Cancel", color = EnsuColor.textMuted())
            }
        },
        containerColor = EnsuColor.backgroundBase()
    )
}

private const val UNSUPPORTED_DEVICE_MESSAGE =
    "This device doesn't have enough memory to run Ensu's AI model. " +
        "You can view existing chats, but can't send new messages."

@Composable
internal fun UnsupportedDeviceDialog(
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(text = "Chat unavailable on this device", style = EnsuTypography.h3) },
        text = {
            Text(
                text = UNSUPPORTED_DEVICE_MESSAGE,
                style = EnsuTypography.body,
                color = EnsuColor.textPrimary()
            )
        },
        confirmButton = {
            TextButton(onClick = onDismiss) {
                Text(text = "Got it", color = EnsuColor.textPrimary())
            }
        },
        containerColor = EnsuColor.backgroundBase()
    )
}

@Composable
internal fun UnsupportedChatInputNotice(
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .padding(horizontal = EnsuSpacing.lg.dp, vertical = EnsuSpacing.md.dp)
            .background(EnsuColor.fillFaint(), RoundedCornerShape(EnsuCornerRadius.card.dp))
            .padding(EnsuSpacing.md.dp)
    ) {
        Text(
            text = "Chat unavailable on this device",
            style = EnsuTypography.large,
            color = EnsuColor.textPrimary()
        )
        Text(
            text = UNSUPPORTED_DEVICE_MESSAGE,
            style = EnsuTypography.body,
            color = EnsuColor.textMuted(),
            modifier = Modifier.padding(top = EnsuSpacing.xs.dp)
        )
    }
}

@Composable
internal fun DownloadToastOverlay(
    status: String,
    percent: Int,
    totalBytes: Long?,
    isLoading: Boolean,
    onCancel: () -> Unit
) {
    val haptic = rememberHaptics()
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = EnsuSpacing.lg.dp),
        contentAlignment = Alignment.TopCenter
    ) {
        val title = if (isLoading) "Loading model" else "Downloading model"
        val clamped = percent.coerceIn(0, 100)
        val statusText = when {
            isLoading -> status
            totalBytes != null -> {
                val downloadedBytes = (totalBytes * (clamped / 100f)).roundToLong()
                "Downloading... ${formatBytes(downloadedBytes)} / ${formatBytes(totalBytes)}"
            }
            else -> status
        }
        Column(
            modifier = Modifier
                .padding(horizontal = EnsuSpacing.lg.dp)
                .background(EnsuColor.fillFaint(), RoundedCornerShape(EnsuCornerRadius.toast.dp))
                .padding(EnsuSpacing.lg.dp)
                .fillMaxWidth()
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(text = title, style = EnsuTypography.large, color = EnsuColor.textPrimary())
                Spacer(modifier = Modifier.weight(1f))
                IconButton(
                    onClick = {
                        haptic.perform(HapticFeedbackType.LongPress)
                        onCancel()
                    },
                    modifier = Modifier.size(28.dp)
                ) {
                    Box(
                        modifier = Modifier
                            .size(22.dp)
                            .background(Color.White, CircleShape),
                        contentAlignment = Alignment.Center
                    ) {
                        Icon(
                            painter = painterResource(HugeIcons.StopIcon),
                            contentDescription = "Cancel download",
                            modifier = Modifier.size(12.dp),
                            tint = EnsuColor.stopButton
                        )
                    }
                }
            }
            Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
            LinearProgressIndicator(
                progress = { clamped / 100f },
                color = if (isLoading) EnsuColor.accent() else EnsuColor.accent(),
                trackColor = EnsuColor.border(),
                modifier = Modifier.fillMaxWidth()
            )
            Spacer(modifier = Modifier.height(EnsuSpacing.sm.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = statusText,
                    style = EnsuTypography.small.copy(fontFeatureSettings = "tnum"),
                    color = EnsuColor.textMuted()
                )
                Spacer(modifier = Modifier.weight(1f))
                Text(text = "$clamped%", style = EnsuTypography.mini, color = EnsuColor.textMuted())
            }
        }
    }
}
