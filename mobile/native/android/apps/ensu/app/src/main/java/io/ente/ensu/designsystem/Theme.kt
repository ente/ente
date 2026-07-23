package io.ente.ensu.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ColorScheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import io.ente.ensu.R

object EnsuColor {
    val backgroundBaseLight = Color(0xFFF8F5F0)
    val backgroundBaseDark = Color(0xFF141414)

    val textPrimaryLight = Color(0xFF1A1A1A)
    val textPrimaryDark = Color(0xFFE8E4DF)

    val textMutedLight = Color(0xFF8A8680)
    val textMutedDark = Color(0xFF777777)

    val borderLight = Color(0xFFD4D0C8)
    val borderDark = Color(0xFF2A2A2A)

    val fillFaintLight = Color(0xFFF0EBE4)
    val fillFaintDark = Color(0xFF1E1E1E)

    val accentLight = Color(0xFFFDCE13)
    val accentDark = Color(0xFFFDCE13)

    val actionLight = textPrimaryLight
    val actionDark = accentDark

    val userMessageTextLight = Color(0xFF555555)
    val userMessageTextDark = Color(0xFF999999)

    val error = Color(0xFFFF4444)
    val success = Color(0xFF4CAF50)
    val stopButton = Color(0xFFFF0000)

    val toastBackgroundLight = Color(0xFF1A1A1A)
    val toastBackgroundDark = Color(0xFFF8F5F0)

    val toastTextLight = Color(0xFFF8F5F0)
    val toastTextDark = Color(0xFF1A1A1A)

    @Composable
    fun backgroundBase(): Color = if (isSystemInDarkTheme()) backgroundBaseDark else backgroundBaseLight

    @Composable
    fun textPrimary(): Color = if (isSystemInDarkTheme()) textPrimaryDark else textPrimaryLight

    @Composable
    fun textMuted(): Color = if (isSystemInDarkTheme()) textMutedDark else textMutedLight

    @Composable
    fun border(): Color = if (isSystemInDarkTheme()) borderDark else borderLight

    @Composable
    fun fillFaint(): Color = if (isSystemInDarkTheme()) fillFaintDark else fillFaintLight

    @Composable
    fun accent(): Color = if (isSystemInDarkTheme()) accentDark else accentLight

    @Composable
    fun action(): Color = if (isSystemInDarkTheme()) actionDark else actionLight

    @Composable
    fun userMessageText(): Color = if (isSystemInDarkTheme()) userMessageTextDark else userMessageTextLight

    @Composable
    fun toastBackground(): Color = if (isSystemInDarkTheme()) toastBackgroundDark else toastBackgroundLight

    @Composable
    fun toastText(): Color = if (isSystemInDarkTheme()) toastTextDark else toastTextLight
}

object EnsuSpacing {
    const val xs = 4
    const val sm = 8
    const val md = 12
    const val lg = 16
    const val xl = 20
    const val xxl = 24
    const val xxxl = 32

    const val pageHorizontal = 24
    const val pageVertical = 24
    const val inputHorizontal = 16
    const val inputVertical = 16
    const val buttonVertical = 18
    const val cardPadding = 12
    const val messageBubbleInset = 80
}

object EnsuCornerRadius {
    const val button = 8
    const val input = 8
    const val card = 12
    const val toast = 12
    const val codeBlock = 10
}

object EnsuTypography {
    private val serifFamily = FontFamily(
        Font(R.font.dm_serif_text_regular, FontWeight.Medium),
        Font(R.font.dm_serif_text_regular, FontWeight.SemiBold)
    )

    private val uiFamily = FontFamily(
        Font(R.font.inter_regular, FontWeight.Normal),
        Font(R.font.inter_medium, FontWeight.Medium),
        Font(R.font.inter_semibold, FontWeight.SemiBold),
        Font(R.font.inter_bold, FontWeight.Bold)
    )

    private val messageFamily = uiFamily

    private val codeFamily = FontFamily(
        Font(R.font.jetbrainsmono_regular, FontWeight.Normal)
    )

    val h1 = TextStyle(fontFamily = serifFamily, fontSize = 48.sp, fontWeight = FontWeight.Medium, lineHeight = 82.sp)
    val h2 = TextStyle(fontFamily = serifFamily, fontSize = 32.sp, fontWeight = FontWeight.Medium, lineHeight = 39.sp)
    val h3 = TextStyle(fontFamily = serifFamily, fontSize = 24.sp, fontWeight = FontWeight.Medium, lineHeight = 29.sp)
    val large = TextStyle(fontFamily = serifFamily, fontSize = 18.sp, fontWeight = FontWeight.Medium, lineHeight = 22.sp)

    val h1Bold = TextStyle(fontFamily = serifFamily, fontSize = 48.sp, fontWeight = FontWeight.SemiBold, lineHeight = 82.sp)
    val h2Bold = TextStyle(fontFamily = serifFamily, fontSize = 32.sp, fontWeight = FontWeight.SemiBold, lineHeight = 39.sp)
    val h3Bold = TextStyle(fontFamily = serifFamily, fontSize = 24.sp, fontWeight = FontWeight.SemiBold, lineHeight = 29.sp)

    val body = TextStyle(fontFamily = uiFamily, fontSize = 16.sp, fontWeight = FontWeight.Medium, lineHeight = 20.sp)
    val small = TextStyle(fontFamily = uiFamily, fontSize = 14.sp, fontWeight = FontWeight.Medium, lineHeight = 17.sp)
    val mini = TextStyle(fontFamily = uiFamily, fontSize = 12.sp, fontWeight = FontWeight.Medium, lineHeight = 15.sp)
    val tiny = TextStyle(fontFamily = uiFamily, fontSize = 10.sp, fontWeight = FontWeight.Medium, lineHeight = 12.sp)

    val message = TextStyle(fontFamily = messageFamily, fontSize = 15.sp, fontWeight = FontWeight.Normal, lineHeight = 26.sp)
    val code = TextStyle(fontFamily = codeFamily, fontSize = 13.sp, fontWeight = FontWeight.Normal, lineHeight = 19.sp)

    val material = Typography(
        bodyLarge = body,
        bodyMedium = body,
        bodySmall = small,
        titleLarge = h2,
        titleMedium = h3,
        titleSmall = large,
        labelLarge = small,
        labelMedium = mini,
        labelSmall = tiny
    )
}

@Composable
fun Theme(content: @Composable () -> Unit) {
    val isDark = isSystemInDarkTheme()
    MaterialTheme(
        colorScheme = if (isDark) darkEnsuColorScheme() else lightEnsuColorScheme(),
        typography = EnsuTypography.material,
        content = content
    )
}

private fun lightEnsuColorScheme(): ColorScheme = lightColorScheme(
    primary = EnsuColor.accentLight,
    onPrimary = Color.Black,

    secondary = EnsuColor.fillFaintLight,
    onSecondary = EnsuColor.textPrimaryLight,

    background = EnsuColor.backgroundBaseLight,
    onBackground = EnsuColor.textPrimaryLight,

    surface = EnsuColor.fillFaintLight,
    onSurface = EnsuColor.textPrimaryLight,

    // Important for default M3 components (e.g. TextField placeholder/label colors).
    // If not set, Material uses its default palette (purple-ish).
    surfaceVariant = EnsuColor.fillFaintLight,
    onSurfaceVariant = EnsuColor.textMutedLight,

    outline = EnsuColor.borderLight,
    outlineVariant = EnsuColor.borderLight,

    error = EnsuColor.error
)

private fun darkEnsuColorScheme(): ColorScheme = darkColorScheme(
    primary = EnsuColor.accentDark,
    onPrimary = Color.Black,

    secondary = EnsuColor.fillFaintDark,
    onSecondary = EnsuColor.textPrimaryDark,

    background = EnsuColor.backgroundBaseDark,
    onBackground = EnsuColor.textPrimaryDark,

    surface = EnsuColor.fillFaintDark,
    onSurface = EnsuColor.textPrimaryDark,

    surfaceVariant = EnsuColor.fillFaintDark,
    onSurfaceVariant = EnsuColor.textMutedDark,

    outline = EnsuColor.borderDark,
    outlineVariant = EnsuColor.borderDark,

    error = EnsuColor.error
)
