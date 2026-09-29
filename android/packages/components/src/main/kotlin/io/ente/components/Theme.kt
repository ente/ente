package io.ente.components

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.ProvidableCompositionLocal
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import io.ente.fonts.EnteFontFamily

public enum class EnteApp {
    Photos,
    Auth,
    Locker,
}

@Immutable
public class Palette
internal constructor(
    public val isDark: Boolean,
    public val primary: Color,
    public val primarySurface: Color,
    public val primaryDark: Color,
    public val primaryDarker: Color,
    public val text: Color,
    public val mutedText: Color,
    public val hintText: Color,
    public val disabledText: Color,
    public val reverseText: Color,
    public val background: Color,
    public val surface: Color,
    public val fill: Color,
    public val fillDarker: Color,
    public val fillDarkest: Color,
    public val border: Color,
    public val faintBorder: Color,
    public val danger: Color,
    public val dangerDarker: Color,
    public val caution: Color,
    public val information: Color,
)

public val LocalEntePalette: ProvidableCompositionLocal<Palette> = staticCompositionLocalOf {
    palette(EnteApp.Photos, dark = false)
}

public object EnteSpacing {
    public val xs: Dp = 4.dp
    public val sm: Dp = 8.dp
    public val md: Dp = 12.dp
    public val lg: Dp = 16.dp
    public val xl: Dp = 20.dp
}

public object EnteRadius {
    public val medium: Dp = 12.dp
    public val large: Dp = 16.dp
    public val button: Dp = 20.dp
}

public object EnteMotion {
    public const val quick: Int = 120
}

public object EnteTypography {
    public val display2: TextStyle =
        TextStyle(
            fontFamily = EnteFontFamily.outfit,
            fontSize = 24.sp,
            fontWeight = FontWeight.SemiBold,
            lineHeight = 32.sp,
        )
    public val body: TextStyle =
        TextStyle(
            fontFamily = EnteFontFamily.inter,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            lineHeight = 20.sp,
        )
    public val bodyBold: TextStyle = body.copy(fontWeight = FontWeight.SemiBold)
    public val heading2: TextStyle = bodyBold.copy(fontSize = 18.sp, lineHeight = 24.sp)
    public val mini: TextStyle = body.copy(fontSize = 12.sp, lineHeight = 16.sp)
    public val avatarExtraSmall: TextStyle = body.copy(fontSize = 8.sp, lineHeight = 15.sp)
    public val avatarSmall: TextStyle = body.copy(fontSize = 10.sp, lineHeight = 15.sp)
}

@Composable
public fun EnteTheme(
    app: EnteApp = EnteApp.Photos,
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val palette = remember(app, darkTheme) { palette(app, darkTheme) }
    CompositionLocalProvider(LocalEntePalette provides palette, content = content)
}

private fun palette(app: EnteApp, dark: Boolean): Palette {
    val (primary, primaryDarker) =
        when (app) {
            EnteApp.Photos -> Color(0xFF08C225) to Color(0xFF057C18)
            EnteApp.Auth -> Color(0xFF9610D6) to Color(0xFF5D0884)
            EnteApp.Locker -> Color(0xFF1071FF) to Color(0xFF0B4CAD)
        }
    return Palette(
        isDark = dark,
        primary = primary,
        primarySurface =
            when (app) {
                EnteApp.Photos -> Color(if (dark) 0xFF292929 else 0xFFDDEEDF)
                EnteApp.Auth -> Color(if (dark) 0xFF271C32 else 0xFFF4E7FC)
                EnteApp.Locker -> Color(if (dark) 0xFF292929 else 0xFFE7EFFA)
            },
        primaryDark =
            when (app) {
                EnteApp.Photos -> Color(0xFF069D1E)
                EnteApp.Auth -> Color(0xFF7A0CAE)
                EnteApp.Locker -> Color(0xFF0E5FD9)
            },
        primaryDarker = primaryDarker,
        text = if (dark) Color.White else Color.Black,
        mutedText = Color(if (dark) 0xFF999999 else 0xFF666666),
        hintText = Color(0xFF969696),
        disabledText = Color(if (dark) 0xFF414141 else 0xFFD6D6D6),
        reverseText = if (dark) Color.Black else Color.White,
        background = Color(if (dark) 0xFF161616 else 0xFFF4F4F4),
        surface = Color(if (dark) 0xFF212121 else 0xFFFFFFFF),
        fill = Color(if (dark) 0xFF0A0A0A else 0xFFEAEAEA),
        fillDarker = Color(if (dark) 0xFF141414 else 0xFFDEDEDE),
        fillDarkest = Color(if (dark) 0xFF292929 else 0xFFD2D2D2),
        border = Color(if (dark) 0xFF3E3E3E else 0xFFE0E0E0),
        faintBorder = Color(if (dark) 0xFF2A2A2A else 0xFFEBEBEB),
        danger = Color(0xFFF63A3A),
        dangerDarker = Color(0xFFC52E2E),
        caution = Color(0xFFF08A1E),
        information = Color(0xFF1071FF),
    )
}
