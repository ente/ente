package io.ente.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.ProvideTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
public fun IllustratedPage(
    title: String,
    message: String,
    modifier: Modifier = Modifier,
    illustration: @Composable () -> Unit,
    actions: @Composable () -> Unit,
    footer: @Composable () -> Unit,
) {
    val palette = LocalEntePalette.current
    BoxWithConstraints(modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        val viewportHeight = maxHeight
        Column(
            Modifier.widthIn(max = 480.dp)
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .heightIn(min = viewportHeight)
                .padding(EnteSpacing.lg),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
        ) {
            CompositionLocalProvider(LocalContentColor provides palette.text) {
                Box(
                    Modifier.height(minOf(220.dp, viewportHeight * 0.28f)).clearAndSetSemantics {},
                    contentAlignment = Alignment.Center,
                ) {
                    illustration()
                }
            }
            Text(
                title,
                style = pageTitleStyle,
                color = palette.text,
                textAlign = TextAlign.Center,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                message,
                style = EnteTypography.body,
                color = palette.mutedText,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = EnteSpacing.lg),
            )
            actions()
            CompositionLocalProvider(LocalContentColor provides palette.mutedText) {
                ProvideTextStyle(EnteTypography.mini) { footer() }
            }
        }
    }
}

private val pageTitleStyle = EnteTypography.display2.copy(fontSize = 32.sp, lineHeight = 40.sp)
