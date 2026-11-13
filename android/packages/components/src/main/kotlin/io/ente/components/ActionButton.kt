package io.ente.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

public enum class ActionVariant {
    Primary,
    Secondary,
    Neutral,
    Critical,
    CriticalText,
    Link,
}

public enum class ActionDensity {
    Regular,
    Compact,
}

public enum class ActionSize {
    Small,
    Large,
}

@Composable
public fun ActionButton(
    label: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variant: ActionVariant = ActionVariant.Primary,
    size: ActionSize = ActionSize.Large,
    density: ActionDensity = ActionDensity.Regular,
    enabled: Boolean = true,
    loading: Boolean = false,
) {
    val palette = LocalEntePalette.current
    val interactionSource = remember { MutableInteractionSource() }
    val pressed by interactionSource.collectIsPressedAsState()
    val colors = actionColors(variant, palette, enabled, pressed && !loading)
    val scale by
        animateFloatAsState(
            targetValue = if (pressed && enabled && !loading) 0.98f else 1f,
            animationSpec = tween(EnteMotion.quick),
            label = "actionScale",
        )
    val inlineLink = variant == ActionVariant.Link && size == ActionSize.Small
    val actionModifier = if (size == ActionSize.Large) modifier.fillMaxWidth() else modifier

    Surface(
        color = colors.background,
        contentColor = colors.foreground,
        shape = RoundedCornerShape(if (inlineLink) 0.dp else EnteRadius.button),
        modifier =
            actionModifier
                .semantics { contentDescription = label }
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .clickable(
                    enabled = enabled && !loading,
                    role = Role.Button,
                    interactionSource = interactionSource,
                    indication = null,
                    onClick = onClick,
                ),
    ) {
        Box(
            modifier =
                Modifier.padding(
                        horizontal = if (inlineLink) 0.dp else EnteSpacing.xl,
                        vertical =
                            if (inlineLink) {
                                4.dp
                            } else if (density == ActionDensity.Regular) {
                                14.dp
                            } else {
                                12.dp
                            },
                    )
                    .heightIn(min = if (inlineLink) 0.dp else 24.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                text = label,
                modifier = Modifier.alpha(if (loading) 0f else 1f).clearAndSetSemantics {},
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                style =
                    if (density == ActionDensity.Regular) {
                        EnteTypography.bodyBold
                    } else {
                        EnteTypography.body
                    },
                textDecoration =
                    if (variant == ActionVariant.CriticalText || variant == ActionVariant.Link) {
                        TextDecoration.Underline
                    } else {
                        null
                    },
            )
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(20.dp).clearAndSetSemantics {},
                    color = colors.foreground,
                    strokeWidth = 2.dp,
                )
            }
        }
    }
}

private data class ActionColors(val background: Color, val foreground: Color)

private fun actionColors(
    variant: ActionVariant,
    palette: Palette,
    enabled: Boolean,
    pressed: Boolean,
): ActionColors {
    if (!enabled) {
        val background =
            if (variant == ActionVariant.CriticalText || variant == ActionVariant.Link) {
                Color.Transparent
            } else {
                palette.fill
            }
        return ActionColors(background, palette.disabledText)
    }
    return when (variant) {
        ActionVariant.Primary ->
            ActionColors(if (pressed) palette.primaryDarker else palette.primary, Color.White)
        ActionVariant.Secondary ->
            ActionColors(if (pressed) palette.fillDarkest else palette.fill, palette.text)
        ActionVariant.Neutral -> ActionColors(palette.text, palette.reverseText)
        ActionVariant.Critical ->
            ActionColors(if (pressed) palette.dangerDarker else palette.danger, Color.White)
        ActionVariant.CriticalText ->
            ActionColors(Color.Transparent, if (pressed) palette.dangerDarker else palette.danger)
        ActionVariant.Link ->
            ActionColors(Color.Transparent, if (pressed) palette.primaryDarker else palette.primary)
    }
}
