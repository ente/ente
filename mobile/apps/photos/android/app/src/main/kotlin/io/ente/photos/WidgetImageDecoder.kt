package io.ente.photos

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface

internal fun decodeWidgetBitmap(imagePath: String): Bitmap {
    val bitmap: Bitmap = BitmapFactory.decodeFile(imagePath)

    return try {
        val exif = ExifInterface(imagePath)
        val rotationDegrees = exif.rotationDegrees
        val isFlipped = exif.isFlipped
        if (rotationDegrees == 0 && !isFlipped) return bitmap

        val transform =
            Matrix().apply {
                if (isFlipped) preScale(-1f, 1f)
                if (rotationDegrees != 0) postRotate(rotationDegrees.toFloat())
            }
        Bitmap.createBitmap(
            bitmap,
            0,
            0,
            bitmap.width,
            bitmap.height,
            transform,
            true
        ).also { corrected ->
            if (corrected !== bitmap) bitmap.recycle()
        }
    } catch (_: Exception) {
        bitmap
    }
}
