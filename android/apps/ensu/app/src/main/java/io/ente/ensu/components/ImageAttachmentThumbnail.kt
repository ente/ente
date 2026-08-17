package io.ente.ensu.components

import android.graphics.BitmapFactory
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import io.ente.ensu.designsystem.EnsuColor
import io.ente.ensu.designsystem.EnsuCornerRadius
import io.ente.ensu.designsystem.HugeIcons
import io.ente.ensu.designsystem.EnsuSpacing
import io.ente.ensu.platform.rememberHaptics
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

@Composable
fun ImageAttachmentThumbnail(
    path: String?,
    contentDescription: String?,
    width: Dp,
    height: Dp,
    modifier: Modifier = Modifier,
    portraitWidth: Dp? = null,
    portraitHeight: Dp? = null,
    squareSize: Dp? = null,
    isUploading: Boolean = false,
    onDelete: (() -> Unit)? = null,
    onClick: (() -> Unit)? = null
) {
    val density = LocalDensity.current
    val maxWidth = maxOf(width, portraitWidth ?: width, squareSize ?: width)
    val maxHeight = maxOf(height, portraitHeight ?: height, squareSize ?: height)
    val targetWidthPx = with(density) { maxWidth.roundToPx() }
    val targetHeightPx = with(density) { maxHeight.roundToPx() }
    val image by produceState<DecodedImage?>(initialValue = null, path, targetWidthPx, targetHeightPx) {
        value = decodeSampledImage(path, targetWidthPx, targetHeightPx)
    }
    val haptic = rememberHaptics()
    val shape = RoundedCornerShape(EnsuCornerRadius.card.dp)
    val resolvedWidth = when {
        image?.isPortrait == true && portraitWidth != null -> portraitWidth
        image?.isSquare == true && squareSize != null -> squareSize
        else -> width
    }
    val resolvedHeight = when {
        image?.isPortrait == true && portraitHeight != null -> portraitHeight
        image?.isSquare == true && squareSize != null -> squareSize
        else -> height
    }
    val clickModifier = if (onClick != null) {
        Modifier.clickable {
            haptic.perform(HapticFeedbackType.TextHandleMove)
            onClick()
        }
    } else {
        Modifier
    }

    Box(
        modifier = modifier
            .size(width = resolvedWidth, height = resolvedHeight)
            .clip(shape)
            .background(EnsuColor.fillFaint(), shape)
            .then(clickModifier),
        contentAlignment = Alignment.Center
    ) {
        if (image != null) {
            Image(
                bitmap = image!!.bitmap,
                contentDescription = contentDescription,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop
            )
        } else {
            Icon(
                painter = painterResource(HugeIcons.Attachment01Icon),
                contentDescription = contentDescription,
                modifier = Modifier.size(24.dp),
                tint = EnsuColor.textMuted()
            )
        }

        if (isUploading) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(Color.Black.copy(alpha = 0.18f)),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(22.dp),
                    strokeWidth = 2.dp,
                    color = Color.White
                )
            }
        }

        if (onDelete != null) {
            Box(
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(4.dp)
                    .size(20.dp)
                    .background(Color.Black.copy(alpha = 0.42f), CircleShape)
                    .clickable {
                        haptic.perform(HapticFeedbackType.LongPress)
                        onDelete()
                    },
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    painter = painterResource(HugeIcons.Cancel01Icon),
                    contentDescription = "Remove image",
                    modifier = Modifier.size(9.dp),
                    tint = Color.White
                )
            }
        }
    }
}

@Composable
fun ImageAttachmentPreviewDialog(
    path: String?,
    contentDescription: String?,
    onDismiss: () -> Unit
) {
    val density = LocalDensity.current
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        BoxWithConstraints(
            modifier = Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.94f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onDismiss
                )
        ) {
            val targetWidthPx = with(density) { maxWidth.roundToPx() }
            val targetHeightPx = with(density) { maxHeight.roundToPx() }
            val image by produceState<DecodedImage?>(initialValue = null, path, targetWidthPx, targetHeightPx) {
                value = decodeSampledImage(path, targetWidthPx, targetHeightPx)
            }

            if (image != null) {
                val previewPadding = EnsuSpacing.md.dp
                val availableWidth = maxOf(0.dp, maxWidth - previewPadding - previewPadding)
                val availableHeight = maxOf(0.dp, maxHeight - previewPadding - previewPadding)
                val (displayWidth, displayHeight) = fittedImageSize(
                    bitmapWidth = image!!.bitmap.width,
                    bitmapHeight = image!!.bitmap.height,
                    availableWidth = availableWidth,
                    availableHeight = availableHeight
                )
                Image(
                    bitmap = image!!.bitmap,
                    contentDescription = contentDescription,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .size(width = displayWidth, height = displayHeight)
                        .clickable(
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            onClick = {}
                        ),
                    contentScale = ContentScale.Fit
                )
            } else {
                Icon(
                    painter = painterResource(HugeIcons.Attachment01Icon),
                    contentDescription = contentDescription,
                    modifier = Modifier
                        .align(Alignment.Center)
                        .size(32.dp),
                    tint = Color.White.copy(alpha = 0.7f)
                )
            }

            IconButton(
                onClick = onDismiss,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(EnsuSpacing.lg.dp)
                    .size(32.dp)
                    .background(Color.Black.copy(alpha = 0.35f), CircleShape)
            ) {
                Icon(
                    painter = painterResource(HugeIcons.Cancel01Icon),
                    contentDescription = "Close image preview",
                    modifier = Modifier.size(14.dp),
                    tint = Color.White
                )
            }
        }
    }
}

private data class DecodedImage(
    val bitmap: ImageBitmap
) {
    val isPortrait: Boolean = bitmap.height > bitmap.width
    val isSquare: Boolean = bitmap.height == bitmap.width
}

private fun fittedImageSize(
    bitmapWidth: Int,
    bitmapHeight: Int,
    availableWidth: Dp,
    availableHeight: Dp
): Pair<Dp, Dp> {
    if (
        bitmapWidth <= 0 ||
        bitmapHeight <= 0 ||
        availableWidth <= 0.dp ||
        availableHeight <= 0.dp
    ) {
        return 0.dp to 0.dp
    }

    val imageAspect = bitmapWidth.toFloat() / bitmapHeight.toFloat()
    val availableAspect = availableWidth.value / availableHeight.value
    return if (imageAspect >= availableAspect) {
        availableWidth to (availableWidth / imageAspect)
    } else {
        (availableHeight * imageAspect) to availableHeight
    }
}

private suspend fun decodeSampledImage(
    path: String?,
    targetWidthPx: Int,
    targetHeightPx: Int
): DecodedImage? = withContext(Dispatchers.IO) {
    if (path.isNullOrBlank() || targetWidthPx <= 0 || targetHeightPx <= 0) {
        return@withContext null
    }

    val bounds = BitmapFactory.Options().apply {
        inJustDecodeBounds = true
    }
    BitmapFactory.decodeFile(path, bounds)
    if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
        return@withContext null
    }

    val options = BitmapFactory.Options().apply {
        inSampleSize = calculateInSampleSize(
            width = bounds.outWidth,
            height = bounds.outHeight,
            targetWidth = targetWidthPx,
            targetHeight = targetHeightPx
        )
    }

    BitmapFactory.decodeFile(path, options)?.asImageBitmap()?.let(::DecodedImage)
}

private fun calculateInSampleSize(
    width: Int,
    height: Int,
    targetWidth: Int,
    targetHeight: Int
): Int {
    var inSampleSize = 1
    if (height > targetHeight || width > targetWidth) {
        val halfHeight = height / 2
        val halfWidth = width / 2
        while (halfHeight / inSampleSize >= targetHeight && halfWidth / inSampleSize >= targetWidth) {
            inSampleSize *= 2
        }
    }
    return inSampleSize
}
