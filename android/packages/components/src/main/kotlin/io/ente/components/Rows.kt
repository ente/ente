package io.ente.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
public fun InfoRow(
    title: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    leading: @Composable () -> Unit,
) {
    val palette = LocalEntePalette.current
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 54.dp)
            .padding(horizontal = EnteSpacing.md, vertical = 9.dp)
            .semantics(mergeDescendants = true) {},
        verticalAlignment = Alignment.CenterVertically,
    ) {
        CompositionLocalProvider(LocalContentColor provides palette.mutedText) {
            Box(Modifier.size(36.dp), contentAlignment = Alignment.Center) { leading() }
        }
        Spacer(Modifier.width(EnteSpacing.md))
        Column(Modifier.weight(1f)) {
            Text(
                title,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                style = EnteTypography.body,
                color = palette.text,
            )
            if (!subtitle.isNullOrEmpty()) {
                Spacer(Modifier.height(EnteSpacing.xs))
                Text(
                    subtitle,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = EnteTypography.mini,
                    color = palette.mutedText,
                )
            }
        }
    }
}

@Composable
public fun MenuGroup(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val palette = LocalEntePalette.current
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = palette.surface,
        contentColor = palette.text,
        shape = RoundedCornerShape(EnteRadius.button),
    ) {
        Column { content() }
    }
}

@Composable
public fun PropertyRow(label: String, value: String, modifier: Modifier = Modifier) {
    val palette = LocalEntePalette.current
    Row(
        modifier.fillMaxWidth().heightIn(min = 48.dp).padding(EnteSpacing.md).semantics(
            mergeDescendants = true
        ) {},
        horizontalArrangement = Arrangement.spacedBy(EnteSpacing.md),
    ) {
        Text(
            label,
            Modifier.weight(1f).alignByBaseline(),
            style = EnteTypography.mini,
            color = palette.mutedText,
        )
        Text(
            value,
            Modifier.weight(1f).alignByBaseline(),
            textAlign = TextAlign.End,
            style = EnteTypography.body,
            color = palette.text,
        )
    }
}

@Composable
public fun EnteDivider(modifier: Modifier = Modifier) {
    HorizontalDivider(modifier, color = LocalEntePalette.current.faintBorder)
}
