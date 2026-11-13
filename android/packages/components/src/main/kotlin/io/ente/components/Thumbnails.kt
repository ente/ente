package io.ente.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
public fun ThumbnailTile(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    titleLines: Int = 2,
    enabled: Boolean = true,
    cover: @Composable () -> Unit,
) {
    val palette = LocalEntePalette.current
    Column(
        modifier.clickable(enabled = enabled, role = Role.Button, onClick = onClick),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Box(
            Modifier.fillMaxWidth()
                .aspectRatio(1f)
                .clip(RoundedCornerShape(EnteRadius.button))
                .background(palette.fill)
                .clearAndSetSemantics {}
        ) {
            cover()
        }
        ThumbnailCaption(title, subtitle, titleLines, enabled)
    }
}

@Composable
public fun ThumbnailRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
    trailing: @Composable (() -> Unit)? = null,
    cover: @Composable () -> Unit,
) {
    val palette = LocalEntePalette.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val background by
        animateColorAsState(
            targetValue = if (pressed && enabled) palette.fillDarker else palette.surface,
            animationSpec = tween(EnteMotion.quick),
            label = "thumbnailRowBackground",
        )
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(EnteRadius.button))
            .background(background)
            .clickable(
                enabled = enabled,
                role = Role.Button,
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .padding(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EnteSpacing.md),
    ) {
        Box(
            Modifier.size(52.dp)
                .clip(RoundedCornerShape(EnteRadius.medium))
                .background(palette.fill)
                .clearAndSetSemantics {},
            contentAlignment = Alignment.Center,
        ) {
            cover()
        }
        Box(Modifier.weight(1f)) { ThumbnailCaption(title, subtitle, 1, enabled) }
        if (trailing != null) {
            CompositionLocalProvider(LocalContentColor provides palette.mutedText) { trailing() }
        }
    }
}

@Composable
private fun ThumbnailCaption(title: String, subtitle: String?, titleLines: Int, enabled: Boolean) {
    val palette = LocalEntePalette.current
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            title,
            style = EnteTypography.body,
            color = if (enabled) palette.text else palette.disabledText,
            maxLines = titleLines,
            overflow = TextOverflow.Ellipsis,
        )
        if (!subtitle.isNullOrEmpty()) {
            Text(
                subtitle,
                style = EnteTypography.mini,
                color = palette.mutedText,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
