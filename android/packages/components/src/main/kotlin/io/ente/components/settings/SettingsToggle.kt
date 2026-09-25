package io.ente.components.settings

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import io.ente.components.EnteSpacing
import io.ente.components.EnteTypography
import io.ente.components.LocalEntePalette
import io.ente.components.MenuGroup

@Composable
public fun SettingsToggle(
    title: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val palette = LocalEntePalette.current
    MenuGroup(modifier) {
        Row(
            Modifier.fillMaxWidth()
                .toggleable(checked, enabled, Role.Switch, onCheckedChange)
                .padding(horizontal = EnteSpacing.lg, vertical = EnteSpacing.sm)
                .heightIn(min = 44.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                title,
                Modifier.weight(1f),
                style = EnteTypography.body,
                color = if (enabled) palette.text else palette.disabledText,
            )
            Box(Modifier.size(40.dp, 31.dp), contentAlignment = Alignment.Center) {
                Switch(
                    checked,
                    onCheckedChange = null,
                    enabled = enabled,
                    modifier = Modifier.requiredSize(52.dp, 32.dp).scale(40f / 52f),
                    colors =
                        SwitchDefaults.colors(
                            checkedTrackColor = palette.primary,
                            checkedThumbColor = Color.White,
                            uncheckedTrackColor = palette.fill,
                            uncheckedThumbColor = palette.primary,
                            uncheckedBorderColor = palette.primary,
                        ),
                )
            }
        }
    }
}
