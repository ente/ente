package io.ente.native_video_editor.core

import android.media.MediaMetadataRetriever
import android.os.Build

class VideoMetadataReader {
    fun read(videoPath: String): VideoMetadata {
        val retriever = MediaMetadataRetriever()
        return try {
            retriever.setDataSource(videoPath)
            read(retriever)
        } finally {
            retriever.release()
        }
    }

    fun read(retriever: MediaMetadataRetriever): VideoMetadata {
        val durationMs = retriever.longValue(MediaMetadataRetriever.METADATA_KEY_DURATION) ?: 0L
        val width = retriever.intValue(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH) ?: 0
        val height = retriever.intValue(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT) ?: 0
        val rotation = retriever.intValue(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION) ?: 0
        val bitrate = retriever.extractMetadata(
            MediaMetadataRetriever.METADATA_KEY_BITRATE
        )?.toLongOrNull()?.takeIf { it > 0 }
        val frameRate = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            retriever.extractMetadata(
                MediaMetadataRetriever.METADATA_KEY_CAPTURE_FRAMERATE
            )?.toFloatOrNull()?.takeIf { it > 0 }
        } else {
            null
        }

        val normalizedRotation = ((rotation % 360) + 360) % 360
        require(width > 0 && height > 0 && normalizedRotation in setOf(0, 90, 180, 270)) {
            "Invalid video dimensions or rotation"
        }

        return VideoMetadata(
            durationMs = durationMs,
            width = width,
            height = height,
            rotationDegrees = normalizedRotation,
            bitrate = bitrate,
            frameRate = frameRate
        )
    }

    private fun MediaMetadataRetriever.intValue(key: Int): Int? =
        extractMetadata(key)?.toIntOrNull()

    private fun MediaMetadataRetriever.longValue(key: Int): Long? =
        extractMetadata(key)?.toLongOrNull()
}
