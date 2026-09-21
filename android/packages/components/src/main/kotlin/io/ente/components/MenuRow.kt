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
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
public fun MenuRow(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    selected: Boolean? = null,
    showsChevron: Boolean = false,
    enabled: Boolean = true,
    leading: @Composable (() -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val background by
        animateColorAsState(
            targetValue = if (pressed && enabled) palette.fillDarker else palette.surface,
            animationSpec = tween(EnteMotion.quick),
            label = "menuRowBackground",
        )
    val hasSubtitle = !subtitle.isNullOrEmpty()

    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 58.dp)
            .background(background)
            .clickable(
                enabled = enabled,
                role = Role.Button,
                interactionSource = interactionSource,
                indication = null,
                onClick = onClick,
            )
            .semantics { selected?.let { this.selected = it } }
            .padding(
                start = if (leading == null) EnteSpacing.lg else EnteSpacing.md,
                end = EnteSpacing.md,
                top = 9.dp,
                bottom = 9.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(EnteSpacing.md),
    ) {
        leading?.let {
            CompositionLocalProvider(LocalContentColor provides palette.mutedText) {
                Box(Modifier.size(36.dp), contentAlignment = Alignment.Center) { it() }
            }
        }
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(EnteSpacing.xs)) {
            Text(
                title,
                maxLines = if (hasSubtitle) 1 else 2,
                overflow = TextOverflow.Ellipsis,
                style = EnteTypography.body,
                color = if (enabled) palette.text else palette.disabledText,
            )
            if (!subtitle.isNullOrEmpty()) {
                Text(
                    subtitle,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    style = EnteTypography.mini,
                    color = palette.mutedText,
                )
            }
        }
        if (selected == true || showsChevron) {
            Row(
                Modifier.defaultMinSize(minWidth = 36.dp, minHeight = 36.dp),
                horizontalArrangement = Arrangement.Center,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (selected == true) {
                    Icon(Icons.Default.Check, null, Modifier.size(24.dp), tint = palette.primary)
                }
                if (showsChevron) {
                    if (selected == true) Spacer(Modifier.width(EnteSpacing.xs))
                    Icon(
                        Icons.AutoMirrored.Filled.KeyboardArrowRight,
                        null,
                        Modifier.size(24.dp),
                        tint = palette.mutedText,
                    )
                }
            }
        }
    }
}
