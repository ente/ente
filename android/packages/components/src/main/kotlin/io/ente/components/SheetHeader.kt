package io.ente.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow

@Composable
public fun SheetHeader(
    title: String,
    modifier: Modifier = Modifier,
    leading: @Composable (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    CompositionLocalProvider(LocalContentColor provides palette.text) {
        Row(
            modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(EnteSpacing.md),
        ) {
            leading?.invoke()
            Text(
                title,
                Modifier.weight(1f).semantics { heading() },
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = EnteTypography.heading2,
            )
            trailing?.invoke()
        }
    }
}
