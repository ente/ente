package io.ente.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp

@Composable
public fun Banner(
    title: String,
    modifier: Modifier = Modifier,
    onClick: (() -> Unit)? = null,
    kind: BannerKind = BannerKind.Neutral,
    subtitle: String? = null,
    leading: @Composable (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    val accent =
        when (kind) {
            BannerKind.Failure -> palette.danger
            BannerKind.Information -> palette.information
            BannerKind.Success,
            BannerKind.Neutral -> palette.primaryDark
            BannerKind.Warning -> palette.caution
        }
    val titleColor = if (kind == BannerKind.Neutral) palette.text else accent
    val interaction =
        if (onClick == null) Modifier else Modifier.clickable(role = Role.Button, onClick = onClick)

    Surface(
        color = palette.surface,
        contentColor = palette.text,
        shape = RoundedCornerShape(EnteRadius.button),
        modifier = modifier.fillMaxWidth().defaultMinSize(minHeight = 66.dp).then(interaction),
    ) {
        Row(
            modifier = Modifier.padding(horizontal = EnteSpacing.lg, vertical = EnteSpacing.md),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            leading?.let {
                CompositionLocalProvider(LocalContentColor provides accent) {
                    Box(Modifier.size(24.dp), contentAlignment = Alignment.Center) { it() }
                }
                Spacer(Modifier.width(EnteSpacing.lg))
            }
            Column(Modifier.weight(1f)) {
                Text(
                    title,
                    maxLines = if (subtitle == null) 2 else 1,
                    overflow = TextOverflow.Ellipsis,
                    style = EnteTypography.bodyBold,
                    color = titleColor,
                )
                subtitle?.let {
                    Spacer(Modifier.size(EnteSpacing.xs))
                    Text(
                        it,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        style = EnteTypography.mini,
                        color = palette.mutedText,
                    )
                }
            }
            trailing?.let {
                Spacer(Modifier.width(EnteSpacing.md))
                Box(Modifier.size(38.dp), contentAlignment = Alignment.Center) { it() }
            }
        }
    }
}

public enum class BannerKind {
    Failure,
    Information,
    Success,
    Warning,
    Neutral,
}
