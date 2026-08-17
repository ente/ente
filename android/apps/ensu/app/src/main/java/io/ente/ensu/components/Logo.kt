package io.ente.ensu.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import io.ente.ensu.R
import io.ente.ensu.designsystem.EnsuColor

@Composable
fun Logo(
    modifier: Modifier = Modifier,
    height: Dp = 24.dp,
    horizontalPadding: Dp = 4.dp,
    verticalPadding: Dp = 2.dp,
    tint: Color = EnsuColor.textPrimary()
) {
    val imageHeight = height - verticalPadding * 2
    Box(
        modifier = modifier
            .height(height)
            .padding(horizontal = horizontalPadding, vertical = verticalPadding),
        contentAlignment = Alignment.Center
    ) {
        Image(
            painter = painterResource(R.drawable.ensu_logo),
            contentDescription = "Ensu",
            modifier = Modifier
                .height(imageHeight)
                .aspectRatio(906f / 255f),
            contentScale = ContentScale.Fit,
            colorFilter = ColorFilter.tint(tint)
        )
    }
}
