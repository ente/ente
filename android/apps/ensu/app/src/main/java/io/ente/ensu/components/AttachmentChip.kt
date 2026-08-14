package io.ente.ensu.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.platform.rememberHaptics

@Composable
fun AttachmentChip(
    name: String,
    size: String,
    iconRes: Int,
    isUploading: Boolean,
    onDelete: (() -> Unit)? = null,
    onClick: (() -> Unit)? = null
) {
    val haptic = rememberHaptics()
    val clickModifier = if (onClick != null) {
        Modifier.clickable {
            haptic.perform(HapticFeedbackType.TextHandleMove)
            onClick()
        }
    } else {
        Modifier
    }

    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .widthIn(max = 220.dp)
            .background(EnsuColor.fillFaint(), RoundedCornerShape(EnsuCornerRadius.input.dp))
            .then(clickModifier)
            .padding(horizontal = 10.dp, vertical = 6.dp)
    ) {
        Icon(
            painter = painterResource(iconRes),
            contentDescription = null,
            modifier = Modifier.size(14.dp),
            tint = EnsuColor.textMuted()
        )
        Spacer(modifier = Modifier.width(EnsuSpacing.sm.dp))
        Column(
            modifier = Modifier.widthIn(max = 160.dp),
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = name,
                style = EnsuTypography.small,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = EnsuColor.textPrimary()
            )
            Text(
                text = size,
                style = EnsuTypography.mini,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                color = EnsuColor.textMuted()
            )
        }
        if (isUploading) {
            Spacer(modifier = Modifier.width(EnsuSpacing.xs.dp))
            CircularProgressIndicator(
                modifier = Modifier.size(12.dp),
                strokeWidth = 2.dp
            )
        }
        if (onDelete != null) {
            Spacer(modifier = Modifier.width(EnsuSpacing.xs.dp))
            IconButton(
                onClick = {
                    haptic.perform(HapticFeedbackType.LongPress)
                    onDelete()
                },
                modifier = Modifier.size(24.dp)
            ) {
                Icon(
                    painter = painterResource(HugeIcons.Cancel01Icon),
                    contentDescription = "Remove attachment",
                    tint = EnsuColor.textMuted()
                )
            }
        }
    }
}
