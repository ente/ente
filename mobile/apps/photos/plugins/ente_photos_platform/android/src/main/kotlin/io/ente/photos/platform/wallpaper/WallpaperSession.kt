package io.ente.photos.platform.wallpaper

import android.content.ContentResolver
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Point
import android.graphics.RectF
import android.net.Uri
import java.io.ByteArrayOutputStream
import java.util.concurrent.CompletableFuture
import java.util.concurrent.Executors

@android.annotation.TargetApi(24)
internal class WallpaperSession(context: Context, private val uri: Uri?, private val size: Point) : AutoCloseable {
    private companion object {
        const val maxPreviewBytes = 24 * 1024 * 1024
    }

    private val service = WallpaperService(context.applicationContext)
    private val executor = Executors.newSingleThreadExecutor()

    fun preview(): CompletableFuture<ByteArray> = CompletableFuture.supplyAsync({
        require(uri?.scheme == ContentResolver.SCHEME_CONTENT) { "Expected an image content URI" }
        if (!service.isAvailable) throw UnsupportedOperationException("Wallpaper changes are not allowed")
        val bitmap = service.preview(requireNotNull(uri), size)
        try {
            BoundedByteArrayOutputStream(maxPreviewBytes).use {
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                it.toByteArray()
            }
        } finally {
            bitmap.recycle()
        }
    }, executor)

    fun apply(region: RectF, destination: Destination): CompletableFuture<Unit> = CompletableFuture.supplyAsync({
        val bitmap = service.render(requireNotNull(uri), Crop(region, size))
        try {
            service.apply(bitmap, destination)
        } finally {
            bitmap.recycle()
        }
    }, executor)

    override fun close() { executor.shutdown() }
}

private class BoundedByteArrayOutputStream(private val limit: Int) : ByteArrayOutputStream() {
    override fun write(value: Int) {
        checkSize(1)
        super.write(value)
    }

    override fun write(bytes: ByteArray, offset: Int, length: Int) {
        checkSize(length)
        super.write(bytes, offset, length)
    }

    private fun checkSize(length: Int) {
        check(count.toLong() + length <= limit) { "Wallpaper preview is too large" }
    }
}
