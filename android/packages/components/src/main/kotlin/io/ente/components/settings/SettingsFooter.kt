package io.ente.components.settings

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import io.ente.components.EnteSpacing
import io.ente.components.EnteTypography
import io.ente.components.LocalEntePalette

@Composable
public fun SettingsFooter(
    version: String,
    modifier: Modifier = Modifier,
    links: @Composable () -> Unit,
) {
    Column(
        modifier.fillMaxWidth().padding(vertical = EnteSpacing.xl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(EnteSpacing.lg),
    ) {
        links()
        Text(
            version,
            style = EnteTypography.mini,
            color = LocalEntePalette.current.mutedText,
            textAlign = TextAlign.Center,
        )
    }
}
