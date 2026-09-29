package io.ente.components.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import io.ente.components.CollapsingPage
import io.ente.components.EnteSpacing

@Composable
public fun SettingsPage(
    title: String,
    backLabel: String,
    back: () -> Unit,
    modifier: Modifier = Modifier,
    identifier: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    CollapsingPage(title, backLabel, back, modifier.safeDrawingPadding(), identifier) {
        item {
            Column(verticalArrangement = Arrangement.spacedBy(EnteSpacing.sm), content = content)
        }
    }
}
