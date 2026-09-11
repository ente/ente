package io.ente.photos.platform.wallpaper

import android.app.WallpaperManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.BitmapRegionDecoder
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.graphics.Point
import android.graphics.Rect
import android.graphics.RectF
import android.net.Uri
import android.os.Build
import androidx.exifinterface.media.ExifInterface
import java.io.IOException
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

internal enum class Destination(val flags: Int) {
    HOME(WallpaperManager.FLAG_SYSTEM),
    LOCK(WallpaperManager.FLAG_LOCK),
    BOTH(WallpaperManager.FLAG_SYSTEM or WallpaperManager.FLAG_LOCK),
}

@android.annotation.TargetApi(24)
internal class WallpaperService(context: Context) {
    private companion object {
        const val maxDecodedPixels = 4_000_000L
    }

    private val resolver = context.contentResolver
    private val manager = WallpaperManager.getInstance(context)

    val isAvailable: Boolean
        get() = manager.isWallpaperSupported && manager.isSetWallpaperAllowed

    fun apply(bitmap: Bitmap, destination: Destination) {
        check(isAvailable) { "Wallpaper changes are not allowed" }
        check(manager.setBitmap(bitmap, null, false, destination.flags) != 0) {
            "Wallpaper manager did not set the image"
        }
    }

    fun render(uri: Uri, crop: Crop): Bitmap {
        val decoder = try {
            resolver.openInputStream(uri)!!.use {
                @Suppress("DEPRECATION")
                requireNotNull(BitmapRegionDecoder.newInstance(it, false))
            }
        } catch (_: IOException) {
            val image = decode(uri, 2 * max(crop.size.x, crop.size.y), Long.MAX_VALUE)
            return try { crop.render(image) } finally { image.recycle() }
        }
        try {
            val transform = orientation(uri)
            val unit = RectF(0f, 0f, 1f, 1f)
            transform.mapRect(unit)
            transform.postTranslate(-unit.left, -unit.top)
            val inverse = Matrix()
            transform.invert(inverse)
            val storageRegion = RectF(crop.normalizedRegion)
            inverse.mapRect(storageRegion)
            storageRegion.set(
                storageRegion.left * decoder.width, storageRegion.top * decoder.height,
                storageRegion.right * decoder.width, storageRegion.bottom * decoder.height,
            )
            val bounds = Rect()
            storageRegion.roundOut(bounds)
            bounds.intersect(0, 0, decoder.width, decoder.height)
            val axes = floatArrayOf(1f, 0f)
            transform.mapVectors(axes)
            val swapAxes = kotlin.math.abs(axes[0]) < 0.5f
            val targetWidth = if (swapAxes) crop.size.y else crop.size.x
            val targetHeight = if (swapAxes) crop.size.x else crop.size.y
            val options = BitmapFactory.Options().apply {
                inSampleSize = max(1, Integer.highestOneBit(min(bounds.width() / targetWidth, bounds.height() / targetHeight)))
            }
            val decoded = requireNotNull(decoder.decodeRegion(bounds, options)) { "Unsupported image region" }
            val image = orient(decoded, transform)
            val available = RectF(
                bounds.left.toFloat() / decoder.width, bounds.top.toFloat() / decoder.height,
                bounds.right.toFloat() / decoder.width, bounds.bottom.toFloat() / decoder.height,
            )
            transform.mapRect(available)
            val region = RectF(
                (crop.normalizedRegion.left - available.left) / available.width(),
                (crop.normalizedRegion.top - available.top) / available.height(),
                (crop.normalizedRegion.right - available.left) / available.width(),
                (crop.normalizedRegion.bottom - available.top) / available.height(),
            )
            return try { Crop(region, crop.size).render(image) } finally { image.recycle() }
        } finally {
            decoder.recycle()
        }
    }

    fun preview(uri: Uri, displaySize: Point): Bitmap {
        val maxSize = max(displaySize.x, displaySize.y)
        return decode(uri, maxSize, maxDecodedPixels)
    }

    private fun decode(uri: Uri, maxSize: Int, maxPixels: Long): Bitmap {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            return ImageDecoder.decodeBitmap(ImageDecoder.createSource(resolver, uri)) { decoder, info, _ ->
                decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                val scale = minOf(
                    1.0,
                    maxSize.toDouble() / max(info.size.width, info.size.height),
                    sqrt(maxPixels.toDouble() / (info.size.width.toLong() * info.size.height)),
                )
                decoder.setTargetSize(
                    max(1, (info.size.width * scale).toInt()),
                    max(1, (info.size.height * scale).toInt()),
                )
            }
        }
        return decodeSampled(uri, maxSize, maxPixels)
    }

    private fun decodeSampled(uri: Uri, maxSize: Int, maxPixels: Long): Bitmap {
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
            inSampleSize = 1
        }
        resolver.openInputStream(uri)!!.use { BitmapFactory.decodeStream(it, null, options) }
        while (
            max(options.outWidth, options.outHeight) / options.inSampleSize > maxSize ||
            options.outWidth.toLong() * options.outHeight / (options.inSampleSize.toLong() * options.inSampleSize) > maxPixels
        ) {
            options.inSampleSize *= 2
        }
        options.inJustDecodeBounds = false
        val bitmap = resolver.openInputStream(uri)!!.use {
            requireNotNull(BitmapFactory.decodeStream(it, null, options)) { "Unsupported image" }
        }
        return orient(bitmap, orientation(uri))
    }

    private fun orientation(uri: Uri): Matrix {
        val exif = resolver.openInputStream(uri)!!.use { ExifInterface(it) }
        return Matrix().apply {
            if (exif.isFlipped) postScale(-1f, 1f)
            postRotate(exif.rotationDegrees.toFloat())
        }
    }

    private fun orient(bitmap: Bitmap, transform: Matrix): Bitmap {
        return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, transform, true).also {
            if (it !== bitmap) bitmap.recycle()
        }
    }
}
