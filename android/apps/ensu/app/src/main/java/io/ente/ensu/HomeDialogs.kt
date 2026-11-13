package io.ente.ensu

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuTypography

@Composable
internal fun ComingSoonDialog(
    title: String,
    message: String,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = {
            Image(
                painter = painterResource(id = R.drawable.ensu_ducky),
                contentDescription = null,
                modifier = Modifier.height(108.dp),
                contentScale = ContentScale.Fit,
            )
        },
        title = {
            Text(
                text = title,
                style = EnsuTypography.h3Bold,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
        },
        text = {
            Text(
                text = message,
                style = EnsuTypography.body,
                color = EnsuColor.textMuted(),
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
        },
        confirmButton = {
            TextButton(
                onClick = onDismiss,
                colors = ButtonDefaults.textButtonColors(contentColor = EnsuColor.textPrimary()),
            ) {
                Text(text = "Got it")
            }
        },
        containerColor = EnsuColor.backgroundBase(),
    )
}
