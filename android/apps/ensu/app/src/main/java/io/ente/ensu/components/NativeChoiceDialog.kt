package io.ente.ensu.components

import android.app.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.platform.LocalContext

@Composable
fun NativeChoiceDialog(
    title: String,
    body: String,
    firstButtonLabel: String,
    secondButtonLabel: String? = null,
    isDismissible: Boolean = true,
    onFirst: () -> Unit,
    onSecond: (() -> Unit)? = null,
    onDismiss: () -> Unit
) {
    val context = LocalContext.current
    val currentOnFirst by rememberUpdatedState(onFirst)
    val currentOnSecond by rememberUpdatedState(onSecond)
    val currentOnDismiss by rememberUpdatedState(onDismiss)

    DisposableEffect(title, body, firstButtonLabel, secondButtonLabel, isDismissible) {
        val builder = AlertDialog.Builder(context)
            .setTitle(title)
            .setMessage(body)
            .setPositiveButton(firstButtonLabel) { _, _ ->
                currentOnFirst()
            }

        if (secondButtonLabel != null && currentOnSecond != null) {
            builder.setNegativeButton(secondButtonLabel) { _, _ ->
                currentOnSecond?.invoke()
            }
        }

        val dialog = builder.create()
        dialog.setCancelable(isDismissible)
        dialog.setCanceledOnTouchOutside(isDismissible)
        dialog.setOnDismissListener { currentOnDismiss() }
        dialog.show()

        onDispose {
            dialog.setOnDismissListener(null)
            dialog.dismiss()
        }
    }
}
