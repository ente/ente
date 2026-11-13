package io.ente.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

@Composable
public fun PopupMenu(
    modifier: Modifier = Modifier,
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = LocalEntePalette.current
    val shape = RoundedCornerShape(EnteRadius.button)
    Column(
        modifier
            .width(196.dp)
            .clip(shape)
            .background(palette.surface)
            .border(1.dp, palette.faintBorder, shape)
            .verticalScroll(rememberScrollState()),
        content = content,
    )
}

@Composable
public fun MenuItem(
    title: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    selected: Boolean? = null,
    enabled: Boolean = true,
    leading: (@Composable () -> Unit)? = null,
    trailing: (@Composable () -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    Row(
        modifier
            .fillMaxWidth()
            .alpha(if (enabled) 1f else 0.5f)
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .semantics { selected?.let { this.selected = it } }
            .heightIn(min = 52.dp)
            .padding(horizontal = EnteSpacing.lg, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        CompositionLocalProvider(LocalContentColor provides palette.mutedText) {
            leading?.let { Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { it() } }
            Text(
                title,
                Modifier.weight(1f),
                style = EnteTypography.mini,
                color = palette.text,
            )
            trailing?.invoke()
        }
    }
}
