package io.ente.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

@Composable
public fun IconAction(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    kind: IconActionKind = IconActionKind.Unfilled,
    enabled: Boolean = true,
    size: Dp = 40.dp,
    content: @Composable () -> Unit,
) {
    val palette = LocalEntePalette.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val colors = iconColors(kind, palette, enabled, pressed)
    val scale by
        animateFloatAsState(
            targetValue = if (pressed && enabled) 0.98f else 1f,
            animationSpec = tween(EnteMotion.quick),
            label = "iconActionScale",
        )

    Box(
        modifier =
            modifier
                .sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                .clickable(
                    enabled = enabled,
                    role = Role.Button,
                    interactionSource = interactionSource,
                    indication = null,
                    onClick = onClick,
                ),
        contentAlignment = Alignment.Center,
    ) {
        CompositionLocalProvider(LocalContentColor provides colors.foreground) {
            Box(
                modifier =
                    Modifier.size(size)
                        .graphicsLayer {
                            scaleX = scale
                            scaleY = scale
                        }
                        .background(
                            colors.background,
                            RoundedCornerShape(
                                if (kind == IconActionKind.Circular) size / 2 else EnteRadius.medium
                            ),
                        ),
                contentAlignment = Alignment.Center,
            ) {
                content()
            }
        }
    }
}

public enum class IconActionKind {
    Primary,
    Unfilled,
    Accent,
    Circular,
    OnMedia,
}

private data class IconColors(val background: Color, val foreground: Color)

private fun iconColors(
    kind: IconActionKind,
    palette: Palette,
    enabled: Boolean,
    pressed: Boolean,
): IconColors {
    if (!enabled && kind != IconActionKind.OnMedia) {
        return IconColors(
            if (kind == IconActionKind.Unfilled) Color.Transparent else palette.fill,
            palette.hintText,
        )
    }
    return when (kind) {
        IconActionKind.Primary,
        IconActionKind.Circular ->
            IconColors(if (pressed) palette.fillDarker else palette.surface, palette.text)
        IconActionKind.Unfilled ->
            IconColors(
                Color.Transparent,
                if (palette.isDark) palette.text else palette.text.copy(alpha = 0.75f),
            )
        IconActionKind.Accent ->
            IconColors(if (pressed) palette.primaryDarker else palette.primary, Color.White)
        IconActionKind.OnMedia ->
            IconColors(
                if (enabled && pressed) Color.White.copy(alpha = 0.12f) else Color.Transparent,
                Color.White.copy(alpha = if (enabled) 1f else 0.4f),
            )
    }
}
