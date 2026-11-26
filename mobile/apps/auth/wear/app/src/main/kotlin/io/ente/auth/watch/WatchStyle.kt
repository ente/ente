package io.ente.auth.watch

import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.wear.compose.material3.ColorScheme
import androidx.wear.compose.material3.MaterialTheme

internal object WatchStyle {
    val background = Color.Black
    val accent = Color(0xFF9610D6)
    val warning = Color(0xFFF59E0B)
    val destructive = Color(0xFFF63A3A)
    val secondary = Color(0xFF999999)
    val surface = Color(0xFF212121)
    val track = Color(0xFF3E3E3E)
}

@Composable
internal fun AuthWatchTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = ColorScheme(
            primary = WatchStyle.accent,
            onPrimary = Color.White,
            background = WatchStyle.background,
            onBackground = Color.White,
            surfaceContainer = WatchStyle.surface,
            surfaceContainerHigh = WatchStyle.surface,
            onSurface = Color.White,
            onSurfaceVariant = WatchStyle.secondary,
            error = WatchStyle.destructive,
            onError = Color.White,
        ),
        content = content,
    )
}
