package io.ente.ensu.components

import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AlertDialogDefaults
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuTypography

@Composable
fun ChoiceDialog(
    title: String,
    body: String,
    firstButtonLabel: String,
    secondButtonLabel: String? = null,
    isCritical: Boolean = false,
    isDismissible: Boolean = true,
    onFirst: () -> Unit,
    onSecond: (() -> Unit)? = null,
    onDismiss: () -> Unit
) {
    AlertDialog(
        onDismissRequest = { if (isDismissible) onDismiss() },
        title = { Text(text = title, style = EnsuTypography.h3) },
        text = { Text(text = body, style = EnsuTypography.body) },
        confirmButton = {
            if (isCritical) {
                Button(
                    onClick = onFirst,
                    colors = ButtonDefaults.buttonColors(containerColor = EnsuColor.error)
                ) {
                    Text(text = firstButtonLabel)
                }
            } else {
                TextButton(onClick = onFirst) {
                    Text(text = firstButtonLabel, color = EnsuColor.textPrimary())
                }
            }
        },
        dismissButton = {
            if (secondButtonLabel != null && onSecond != null) {
                TextButton(
                    onClick = onSecond,
                    colors = ButtonDefaults.textButtonColors(contentColor = EnsuColor.textMuted())
                ) {
                    Text(text = secondButtonLabel)
                }
            }
        },
        containerColor = EnsuColor.backgroundBase(),
        tonalElevation = 0.dp,
        shape = AlertDialogDefaults.shape
    )
}
