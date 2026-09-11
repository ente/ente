package io.ente.photos.platform.wallpaper

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Point
import android.graphics.RectF

internal data class Crop(val normalizedRegion: RectF, val size: Point) {
    fun render(orientedImage: Bitmap): Bitmap {
        val result = Bitmap.createBitmap(size.x, size.y, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(result)
        canvas.drawColor(Color.BLACK)
        canvas.scale(size.x / (normalizedRegion.width() * orientedImage.width), size.y / (normalizedRegion.height() * orientedImage.height))
        canvas.translate(-normalizedRegion.left * orientedImage.width, -normalizedRegion.top * orientedImage.height)
        canvas.drawBitmap(orientedImage, 0f, 0f, Paint(Paint.FILTER_BITMAP_FLAG))
        return result
    }
}
