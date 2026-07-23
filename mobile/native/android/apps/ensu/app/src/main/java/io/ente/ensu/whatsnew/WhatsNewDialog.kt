package io.ente.ensu.whatsnew

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.designsystem.EnsuTypography

@Composable
fun WhatsNewDialog(
    entries: List<WhatsNewEntry>,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = {
            Text(
                text = "What's new",
                style = EnsuTypography.h3Bold,
                color = EnsuColor.textPrimary()
            )
        },
        text = {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(max = 360.dp)
                    .verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(EnsuSpacing.lg.dp)
            ) {
                entries.forEach { entry ->
                    WhatsNewEntryContent(entry)
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = onDismiss,
                colors = ButtonDefaults.textButtonColors(contentColor = EnsuColor.textPrimary())
            ) {
                Text(text = "Continue", style = EnsuTypography.body)
            }
        },
        containerColor = EnsuColor.backgroundBase()
    )
}

@Composable
private fun WhatsNewEntryContent(entry: WhatsNewEntry) {
    Column(verticalArrangement = Arrangement.spacedBy(EnsuSpacing.sm.dp)) {
        Text(
            text = entry.title,
            style = EnsuTypography.large,
            color = EnsuColor.textPrimary()
        )
        Text(
            text = entry.description,
            style = EnsuTypography.body,
            color = EnsuColor.textMuted()
        )
    }
}
