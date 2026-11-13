package io.ente.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp

@Composable
public fun SheetContent(
    title: String,
    modifier: Modifier = Modifier,
    message: String? = null,
    back: (() -> Unit)? = null,
    dismiss: (() -> Unit)? = null,
    backLabel: String = "Back",
    dismissLabel: String = "Close",
    content: @Composable () -> Unit,
) {
    val palette = LocalEntePalette.current
    Column(modifier.background(palette.background).padding(EnteSpacing.xl)) {
        SheetHeader(
            title,
            leading =
                back?.let { onBack ->
                    {
                        IconAction(onBack, kind = IconActionKind.Circular) {
                            Icon(
                                painterResource(R.drawable.component_back),
                                backLabel,
                                Modifier.size(24.dp),
                            )
                        }
                    }
                },
            trailing =
                dismiss?.let { onDismiss ->
                    {
                        IconAction(onDismiss, kind = IconActionKind.Circular) {
                            Icon(
                                painterResource(R.drawable.component_close),
                                dismissLabel,
                                Modifier.size(18.dp),
                            )
                        }
                    }
                },
        )
        Spacer(Modifier.height(EnteSpacing.lg))
        if (message != null) {
            Text(message, style = EnteTypography.body, color = palette.mutedText)
            Spacer(Modifier.height(EnteSpacing.lg))
        }
        content()
    }
}
