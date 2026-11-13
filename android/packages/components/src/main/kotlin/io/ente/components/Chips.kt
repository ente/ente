package io.ente.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
public fun FilterChip(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leading: @Composable (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    val background =
        if (selected) {
            if (palette.isDark) Color(0xFFF4F4F4) else Color(0xFF161616)
        } else {
            palette.surface
        }
    val foreground =
        when {
            selected -> palette.reverseText
            enabled -> palette.mutedText
            else -> palette.disabledText
        }
    val startPadding =
        when {
            leading != null && trailing == null -> EnteSpacing.md
            trailing != null -> EnteSpacing.lg
            else -> 18.dp
        }
    val endPadding =
        when {
            leading != null && trailing == null -> if (selected) EnteSpacing.md else EnteSpacing.lg
            trailing != null || selected -> EnteSpacing.md
            else -> 18.dp
        }

    Surface(
        color = background,
        contentColor = foreground,
        shape = RoundedCornerShape(percent = 50),
        modifier =
            modifier.heightIn(min = 40.dp).toggleable(
                value = selected,
                enabled = enabled,
                role = Role.Button,
            ) {
                onClick()
            },
    ) {
        Row(
            modifier =
                Modifier.padding(
                    start = startPadding,
                    end = endPadding,
                    top = EnteSpacing.md,
                    bottom = EnteSpacing.md,
                ),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leading?.let {
                Box(Modifier.size(16.dp), contentAlignment = Alignment.Center) { it() }
                Spacer(Modifier.width(EnteSpacing.sm))
            }
            Text(
                label,
                modifier = Modifier.weight(1f, fill = false),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = EnteTypography.mini,
            )
            if (trailing != null || selected) {
                Spacer(Modifier.width(EnteSpacing.sm))
                if (trailing != null) {
                    Box(Modifier.size(16.dp), contentAlignment = Alignment.Center) { trailing() }
                } else {
                    Icon(
                        painterResource(R.drawable.component_close),
                        null,
                        Modifier.size(14.dp),
                        tint = foreground,
                    )
                }
            }
        }
    }
}

@Composable
public fun Tag(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    leading: @Composable (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    Surface(
        color = if (selected) palette.primary else palette.surface,
        contentColor =
            if (selected) Color.White else if (enabled) palette.mutedText else palette.disabledText,
        shape = RoundedCornerShape(EnteRadius.large),
        modifier =
            modifier.heightIn(min = 44.dp).toggleable(
                value = selected,
                enabled = enabled,
                role = Role.Button,
            ) {
                onClick()
            },
    ) {
        Row(
            modifier =
                Modifier.padding(
                    start = if (leading != null) EnteSpacing.md else EnteSpacing.xl,
                    end = if (trailing != null) EnteSpacing.md else EnteSpacing.xl,
                    top = EnteSpacing.md,
                    bottom = EnteSpacing.md,
                ),
            horizontalArrangement = Arrangement.Center,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leading?.let {
                Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) { it() }
                Spacer(Modifier.width(EnteSpacing.xs))
            }
            Text(
                label,
                modifier = Modifier.weight(1f, fill = false),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                style = EnteTypography.body,
            )
            trailing?.let {
                Spacer(Modifier.width(EnteSpacing.xs))
                Box(Modifier.size(20.dp), contentAlignment = Alignment.Center) { it() }
            }
        }
    }
}
