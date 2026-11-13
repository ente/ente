package io.ente.components

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp

@Composable
public fun Checkmark(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val palette = LocalEntePalette.current
    val fill by
        animateColorAsState(
            if (checked) if (enabled) palette.primary else palette.fillDarkest
            else Color.Transparent,
            tween(EnteMotion.quick),
            label = "checkmarkFill",
        )
    val stroke = if (checked) fill else if (enabled) palette.mutedText else palette.faintBorder
    Box(
        modifier.then(
            if (onCheckedChange == null) Modifier
            else
                Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                    .toggleable(checked, enabled, Role.Checkbox, onCheckedChange)
        ),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(16.dp)
                .clip(RoundedCornerShape(4.dp))
                .background(fill)
                .border(1.dp, stroke, RoundedCornerShape(4.dp)),
            contentAlignment = Alignment.Center,
        ) {
            if (checked) {
                Icon(
                    painterResource(R.drawable.component_check_rounded),
                    null,
                    Modifier.size(12.dp),
                    tint = Color.White,
                )
            }
        }
    }
}

@Composable
public fun Radio(
    selected: Boolean,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val palette = LocalEntePalette.current
    val active by
        animateColorAsState(
            if (enabled) palette.primary else palette.fillDarkest,
            tween(EnteMotion.quick),
            label = "radioFill",
        )
    Box(
        modifier.then(
            if (onClick == null) Modifier
            else
                Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                    .selectable(selected, enabled, Role.RadioButton, onClick)
        ),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier.size(16.dp)
                .border(
                    if (selected) 2.dp else 1.dp,
                    if (selected) active else palette.border,
                    CircleShape,
                )
                .then(
                    if (selected)
                        Modifier.drawBehind {
                            drawCircle(active, radius = size.minDimension / 2 - 3.dp.toPx())
                        }
                    else Modifier
                )
        )
    }
}

@Composable
public fun Toggle(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val palette = LocalEntePalette.current
    val shape = RoundedCornerShape(12.dp)
    val track by
        animateColorAsState(
            if (checked) palette.primary else palette.fill,
            tween(EnteMotion.quick),
            label = "toggleTrack",
        )
    val thumb by
        animateColorAsState(
            if (checked) Color.White else palette.primary,
            tween(EnteMotion.quick),
            label = "toggleThumb",
        )
    val thumbOffset by
        animateDpAsState(
            if (checked) 19.dp else 3.dp,
            tween(EnteMotion.quick),
            label = "toggleOffset",
        )
    Box(
        modifier.then(
            if (onCheckedChange == null) Modifier
            else
                Modifier.sizeIn(minWidth = 48.dp, minHeight = 48.dp)
                    .toggleable(checked, enabled, Role.Switch, onCheckedChange)
        ),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier =
                Modifier.size(40.dp, 24.dp)
                    .clip(shape)
                    .background(track)
                    .border(1.dp, if (enabled) palette.primary else palette.faintBorder, shape)
        ) {
            Box(
                Modifier.align(Alignment.CenterStart)
                    .padding(start = thumbOffset)
                    .size(18.dp)
                    .background(thumb, CircleShape)
            )
        }
    }
}

@Composable
public fun LabeledControl(
    label: String,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    enabled: Boolean = true,
    control: @Composable () -> Unit,
) {
    val palette = LocalEntePalette.current
    Row(
        modifier = modifier.fillMaxWidth().sizeIn(minHeight = 48.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        control()
        Spacer(Modifier.width(EnteSpacing.md))
        Column(Modifier.weight(1f)) {
            Text(
                label,
                style = EnteTypography.body,
                color = if (enabled) palette.text else palette.disabledText,
            )
            subtitle?.let { Text(it, style = EnteTypography.mini, color = palette.mutedText) }
        }
    }
}
