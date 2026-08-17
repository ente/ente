package io.ente.ensu.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.ButtonDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuTypography
import io.ente.ensu.platform.rememberHaptics

@Composable
fun BranchSwitcher(
    currentIndex: Int,
    totalCount: Int,
    onPrevious: () -> Unit,
    onNext: () -> Unit
) {
    if (totalCount <= 1) return

    val haptic = rememberHaptics()
    Row(verticalAlignment = Alignment.CenterVertically) {
        TextButton(
            onClick = {
                haptic.perform(HapticFeedbackType.TextHandleMove)
                onPrevious()
            },
            enabled = currentIndex > 1,
            modifier = Modifier.size(36.dp),
            contentPadding = ButtonDefaults.TextButtonContentPadding
        ) {
            Text(text = "<", style = EnsuTypography.small, color = EnsuColor.textMuted())
        }
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = "${currentIndex}/${totalCount}",
            style = EnsuTypography.small.copy(fontFeatureSettings = "tnum"),
            color = EnsuColor.textMuted()
        )
        Spacer(modifier = Modifier.width(4.dp))
        TextButton(
            onClick = {
                haptic.perform(HapticFeedbackType.TextHandleMove)
                onNext()
            },
            enabled = currentIndex < totalCount,
            modifier = Modifier.size(36.dp),
            contentPadding = ButtonDefaults.TextButtonContentPadding
        ) {
            Text(text = ">", style = EnsuTypography.small, color = EnsuColor.textMuted())
        }
    }
}
