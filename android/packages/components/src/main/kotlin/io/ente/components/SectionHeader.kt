package io.ente.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
public fun SectionHeader(
    title: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    onClick: (() -> Unit)? = null,
) {
    val palette = LocalEntePalette.current
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .then(
                if (onClick == null) Modifier
                else Modifier.clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            )
            .semantics(mergeDescendants = true) { heading() },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            title,
            Modifier.weight(1f),
            style = sectionTitleStyle,
            color = if (enabled) palette.text else palette.disabledText,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (onClick != null) {
            Icon(
                painterResource(R.drawable.component_chevron),
                null,
                Modifier.size(38.dp).padding(7.dp),
                tint = if (enabled) palette.mutedText else palette.disabledText,
            )
        }
    }
}

private val sectionTitleStyle = EnteTypography.display2.copy(fontSize = 20.sp, lineHeight = 28.sp)
