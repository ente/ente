package io.ente.components.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import io.ente.components.EnteSpacing
import io.ente.components.EnteTypography
import io.ente.components.LocalEntePalette

@Composable
public fun SettingsSection(
    modifier: Modifier = Modifier,
    title: String? = null,
    footer: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val palette = LocalEntePalette.current
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(EnteSpacing.sm)) {
        if (title != null) {
            Text(
                title,
                style = EnteTypography.heading2,
                color = palette.text,
                modifier = Modifier.padding(vertical = EnteSpacing.sm).semantics { heading() },
            )
        }
        content()
        if (footer != null) {
            Text(
                footer,
                style = EnteTypography.mini,
                color = palette.mutedText,
                modifier = Modifier.padding(EnteSpacing.sm),
            )
        }
    }
}
