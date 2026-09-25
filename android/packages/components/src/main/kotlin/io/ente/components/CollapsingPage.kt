package io.ente.components

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.constrainHeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.roundToInt

@Composable
public fun CollapsingPage(
    title: String,
    backLabel: String,
    back: () -> Unit,
    modifier: Modifier = Modifier,
    identifier: String? = null,
    eyebrow: String? = null,
    subtitle: String? = null,
    actions: @Composable RowScope.() -> Unit = {},
    content: LazyListScope.() -> Unit,
) {
    val palette = LocalEntePalette.current
    val density = LocalDensity.current
    val titleHeight = with(density) { (32 + if (eyebrow == null) 0 else 30).sp.toDp() }
    val collapsedTitleHeight = with(density) { 24.sp.toDp() }
    val subtitleHeight = with(density) { 16.sp.toDp() }
    val toolbarHeight = maxOf(56.dp, collapsedTitleHeight)
    val expandedHeight =
        maxOf(
            if (subtitle == null) 92.dp else 110.dp,
            48.dp +
                titleHeight +
                (if (subtitle == null) 0.dp else 2.dp + subtitleHeight * 2) +
                16.dp,
        )
    val contentTop =
        48.dp +
            if (subtitle == null) 0.dp
            else minOf(subtitleHeight, maxOf(0.dp, toolbarHeight - titleHeight))
    val expansion = expandedHeight - toolbarHeight
    val extent = with(density) { expansion.toPx() }
    var offset by remember { mutableFloatStateOf(0f) }
    val scroll =
        remember(extent) {
            object : NestedScrollConnection {
                fun consume(delta: Float): Offset {
                    val previous = offset
                    offset = (offset - delta).coerceIn(0f, extent)
                    return Offset(0f, previous - offset)
                }

                override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset =
                    if (available.y < 0) consume(available.y) else Offset.Zero

                override fun onPostScroll(
                    consumed: Offset,
                    available: Offset,
                    source: NestedScrollSource,
                ): Offset = if (available.y > 0) consume(available.y) else Offset.Zero

                override suspend fun onPostFling(
                    consumed: Velocity,
                    available: Velocity,
                ): Velocity {
                    if (offset > 1f && offset < extent) {
                        animate(
                            offset,
                            extent,
                            animationSpec = tween(160, easing = HeaderEaseOut),
                        ) { value, _ ->
                            offset = value
                        }
                    }
                    return Velocity.Zero
                }
            }
        }
    val progress = (offset / extent).coerceIn(0f, 1f)
    val eased = HeaderEaseInOut.transform(progress)
    val titleTop = contentTop + ((toolbarHeight - collapsedTitleHeight) / 2 - contentTop) * eased
    val currentTitleHeight = titleHeight + (collapsedTitleHeight - titleHeight) * eased
    val rowHeight = maxOf(toolbarHeight, currentTitleHeight)
    Column(modifier.fillMaxSize().background(palette.background).nestedScroll(scroll)) {
        Box(Modifier.fillMaxWidth().height(expandedHeight - expansion * progress).clipToBounds()) {
            IconAction(
                onClick = back,
                modifier =
                    Modifier.align(Alignment.TopStart)
                        .height(toolbarHeight)
                        .padding(start = 4.dp)
                        .then(identifier?.let { Modifier.testTag("$it.back") } ?: Modifier),
                kind = IconActionKind.Unfilled,
                size = 48.dp,
            ) {
                Icon(painterResource(R.drawable.component_back), backLabel, Modifier.size(24.dp))
            }
            Row(
                Modifier.fillMaxWidth()
                    .offset(y = titleTop - (rowHeight - currentTitleHeight) / 2)
                    .height(rowHeight)
                    .padding(start = EnteSpacing.lg + 36.dp * eased, end = EnteSpacing.lg),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(EnteSpacing.sm),
            ) {
                HeaderTitle(
                    title,
                    eyebrow,
                    eased,
                    Modifier.weight(1f)
                        .height(currentTitleHeight)
                        .semantics(mergeDescendants = true) { heading() }
                        .then(identifier?.let { Modifier.testTag("$it.title") } ?: Modifier),
                )
                actions()
            }
            if (subtitle != null && progress < 1f) {
                Text(
                    subtitle,
                    Modifier.offset(y = contentTop + titleHeight + 2.dp)
                        .padding(start = EnteSpacing.lg + 36.dp * eased, end = EnteSpacing.lg)
                        .alpha(1 - eased)
                        .then(
                            if (progress >= 0.99f) Modifier.clearAndSetSemantics {} else Modifier
                        ),
                    style = EnteTypography.mini,
                    color = palette.mutedText,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        LazyColumn(
            modifier =
                Modifier.weight(1f)
                    .then(identifier?.let { Modifier.testTag("$it.scroll") } ?: Modifier),
            contentPadding =
                PaddingValues(
                    start = EnteSpacing.lg,
                    end = EnteSpacing.lg,
                    bottom = EnteSpacing.lg,
                ),
            content = content,
        )
    }
}

@Composable
private fun HeaderTitle(title: String, eyebrow: String?, progress: Float, modifier: Modifier) {
    val palette = LocalEntePalette.current
    val titleStyle =
        EnteTypography.display2.copy(
            fontSize = (24 - 4 * progress).sp,
            lineHeight = (32 - 8 * progress).sp,
        )
    if (eyebrow == null) {
        Text(
            title,
            modifier,
            style = titleStyle,
            color = palette.text,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    } else {
        val eyebrowHeight = with(LocalDensity.current) { 30.sp.toPx() }
        Layout(
            content = {
                Text(
                    eyebrow,
                    style =
                        EnteTypography.display2.copy(
                            fontSize = (16 + 4 * progress).sp,
                            lineHeight = (30 - 6 * progress).sp,
                        ),
                    color = palette.mutedText,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    title,
                    style = titleStyle,
                    color = palette.text,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            },
            modifier = modifier,
        ) { children, constraints ->
            val width = constraints.maxWidth
            val prefixWidth =
                (children[0].maxIntrinsicWidth(Constraints.Infinity) + 6.dp.roundToPx())
                    .coerceAtMost((width - 24.dp.roundToPx()).coerceAtLeast(0))
            val horizontal = HeaderEaseOut.transform(progress)
            val titleX = (prefixWidth * horizontal).roundToInt()
            val titleY = (eyebrowHeight * (1 - HeaderEaseIn.transform(progress))).roundToInt()
            val prefix =
                children[0].measure(
                    Constraints(
                        maxWidth =
                            (width +
                                    ((prefixWidth - 6.dp.roundToPx()).coerceAtLeast(0) - width) *
                                        horizontal)
                                .roundToInt()
                    )
                )
            val label = children[1].measure(Constraints(maxWidth = width - titleX))
            layout(width, constraints.constrainHeight(label.height + titleY)) {
                prefix.placeRelative(0, 0)
                label.placeRelative(titleX, titleY)
            }
        }
    }
}

private val HeaderEaseInOut = CubicBezierEasing(0.42f, 0f, 0.58f, 1f)
private val HeaderEaseOut = CubicBezierEasing(0f, 0f, 0.58f, 1f)
private val HeaderEaseIn = CubicBezierEasing(0.42f, 0f, 1f, 1f)
