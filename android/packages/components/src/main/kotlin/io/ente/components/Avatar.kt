package io.ente.components

import android.icu.text.BreakIterator
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import java.util.Locale

@Composable
public fun Avatar(
    name: String,
    modifier: Modifier = Modifier,
    identity: String = name,
    size: AvatarSize = AvatarSize.Regular,
    painter: Painter? = null,
) {
    val palette = LocalEntePalette.current
    val colorIndex = remember(identity) { avatarIndex(identity) }
    val color = avatarColors(palette)[colorIndex]
    Box(
        modifier =
            modifier
                .size(size.dimension)
                .clip(CircleShape)
                .background(color)
                .border(size.border, palette.background, CircleShape)
                .clearAndSetSemantics {
                    contentDescription = name
                    role = Role.Image
                },
        contentAlignment = Alignment.Center,
    ) {
        if (painter == null) {
            val initials = remember(name) { avatarInitials(name) }
            Text(initials, style = size.textStyle, color = Color.White)
        } else {
            Image(painter, null, Modifier.matchParentSize(), contentScale = ContentScale.Crop)
        }
    }
}

public enum class AvatarSize(
    internal val dimension: Dp,
    internal val border: Dp,
    internal val textStyle: TextStyle,
) {
    ExtraSmall(16.dp, 1.dp, EnteTypography.avatarExtraSmall),
    Small(20.dp, 1.dp, EnteTypography.avatarSmall),
    Regular(24.dp, 1.dp, EnteTypography.mini),
    Medium(28.dp, 1.dp, EnteTypography.mini),
    Large(32.dp, 2.dp, EnteTypography.mini),
    Contact(56.dp, 2.dp, EnteTypography.heading2),
}

private fun avatarColors(palette: Palette) =
    listOf(
        palette.caution,
        palette.primary,
        Color(0xFFF24822),
        Color(0xFFDF61BB),
        Color(0xFF9610D6),
        Color(0xFF1071FF),
        Color(0xFF00B8D4),
    )

private fun avatarIndex(identity: String): Int {
    var hash = 0x811c9dc5L
    identity.trim().lowercase(Locale.ROOT).toByteArray(Charsets.UTF_8).forEach { byte ->
        hash = (hash xor (byte.toLong() and 0xff)) * 0x01000193L and 0xffffffffL
    }
    return (hash % 7).toInt()
}

private val wordSeparator = Regex("\\s+")

private fun avatarInitials(name: String): String {
    val words = name.split(wordSeparator).filter(String::isNotEmpty)
    if (words.isEmpty()) return "?"
    val characters = BreakIterator.getCharacterInstance(Locale.ROOT)
    fun initial(word: String): String {
        characters.setText(word)
        return word.substring(0, characters.next()).uppercase(Locale.ROOT)
    }
    return initial(words.first()) + if (words.size > 1) initial(words.last()) else ""
}
