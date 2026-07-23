package io.ente.ensu.components

import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.platform.rememberHaptics

@Composable
fun ActionButton(
    icon: ImageVector,
    onTap: () -> Unit,
    contentDescription: String,
    color: Color = EnsuColor.textMuted()
) {
    val haptic = rememberHaptics()
    IconButton(
        onClick = {
            haptic.perform(HapticFeedbackType.TextHandleMove)
            onTap()
        },
        modifier = Modifier.size(36.dp),
        colors = IconButtonDefaults.iconButtonColors(contentColor = color)
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            modifier = Modifier.size(16.dp)
        )
    }
}

@Composable
fun ActionButton(
    iconRes: Int,
    onTap: () -> Unit,
    contentDescription: String,
    color: Color = EnsuColor.textMuted()
) {
    val haptic = rememberHaptics()
    IconButton(
        onClick = {
            haptic.perform(HapticFeedbackType.TextHandleMove)
            onTap()
        },
        modifier = Modifier.size(36.dp),
        colors = IconButtonDefaults.iconButtonColors(contentColor = color)
    ) {
        Icon(
            painter = painterResource(iconRes),
            contentDescription = contentDescription,
            modifier = Modifier.size(16.dp)
        )
    }
}

@Composable
fun TextActionButton(
    text: String,
    onTap: () -> Unit
) {
    val haptic = rememberHaptics()
    TextButton(onClick = {
        haptic.perform(HapticFeedbackType.TextHandleMove)
        onTap()
    }) {
        Text(text = text, style = EnsuTypography.small, color = EnsuColor.textMuted())
    }
}

@Composable
fun PrimaryButton(
    text: String,
    isLoading: Boolean,
    isEnabled: Boolean,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        modifier = Modifier.fillMaxWidth(),
        enabled = isEnabled,
        colors = ButtonDefaults.buttonColors(containerColor = EnsuColor.accent()),
        contentPadding = PaddingValues(vertical = EnsuSpacing.buttonVertical.dp),
        shape = RoundedCornerShape(EnsuCornerRadius.button.dp)
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(18.dp),
                color = MaterialTheme.colorScheme.onPrimary,
                strokeWidth = 2.dp
            )
        } else {
            Text(
                text = text,
                style = EnsuTypography.body.copy(fontSize = 18.sp, fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onPrimary
            )
        }
    }
}
