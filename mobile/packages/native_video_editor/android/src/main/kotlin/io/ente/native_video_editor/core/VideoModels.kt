package io.ente.native_video_editor.core

import kotlin.math.max
import kotlin.math.roundToInt

data class VideoMetadata(
    val durationMs: Long,
    val width: Int,
    val height: Int,
    val rotationDegrees: Int,
    val bitrate: Long?,
    val frameRate: Float?
) {
    val displayWidth: Int
        get() = if (rotationDegrees == 90 || rotationDegrees == 270) height else width

    val displayHeight: Int
        get() = if (rotationDegrees == 90 || rotationDegrees == 270) width else height
}

enum class VideoFramePolicy {
    PRECISE,
    NEAREST_SYNC;
}

data class VideoFrameRequest(
    val inputPath: String,
    val outputPaths: List<String>,
    val positionsMs: List<Long>,
    val maxWidth: Int,
    val maxHeight: Int,
    val quality: Int,
    val policy: VideoFramePolicy
) {
    init {
        require(inputPath.isNotBlank()) { "Missing input path" }
        require(outputPaths.isNotEmpty() && outputPaths.size == positionsMs.size) {
            "Every timestamp requires an output path"
        }
        require(outputPaths.none(String::isBlank) && outputPaths.distinct().size == outputPaths.size) {
            "Output paths must be non-empty and unique"
        }
        require(positionsMs.all { it >= 0 }) { "Frame timestamps must be non-negative" }
        require(maxWidth > 0 && maxHeight > 0) { "Frame bounds must be positive" }
        require(quality in 1..100) { "JPEG quality must be between 1 and 100" }
    }
}

data class VideoFrameResult(
    val outputPath: String,
    val width: Int,
    val height: Int
)

data class VideoFrameExtractionResult(
    val videoInfo: VideoMetadata,
    val frames: List<VideoFrameResult>
)

data class VideoCrop(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int
) {
    init {
        require(x >= 0 && y >= 0 && width > 0 && height > 0) {
            "Invalid crop rectangle"
        }
    }
}

data class VideoEditRequest(
    val inputPath: String,
    val outputPath: String,
    val trimStartMs: Long?,
    val trimEndMs: Long?,
    val rotateDegrees: Int?,
    val crop: VideoCrop?,
    val speed: Float
) {
    init {
        require(inputPath.isNotBlank() && outputPath.isNotBlank()) { "Missing video path" }
        require((trimStartMs == null) == (trimEndMs == null)) {
            "Trim bounds must be provided together"
        }
        require(trimStartMs == null || (trimStartMs >= 0 && trimStartMs < trimEndMs!!)) {
            "Invalid trim bounds"
        }
        require(rotateDegrees == null || rotateDegrees in setOf(0, 90, 180, 270)) {
            "Invalid rotation"
        }
        require(speed.isFinite() && speed > 0f) { "Invalid speed" }
    }
}

data class VideoEditResult(val outputPath: String, val isReEncoded: Boolean)

internal data class PixelSize(val width: Int, val height: Int)

internal fun boundedVideoSize(
    width: Int,
    height: Int,
    maxWidth: Int,
    maxHeight: Int
): PixelSize {
    require(width > 0 && height > 0) { "Video dimensions are unavailable" }
    val scale = minOf(
        1.0,
        maxWidth.toDouble() / width,
        maxHeight.toDouble() / height
    )
    return PixelSize(
        max(1, (width * scale).roundToInt()),
        max(1, (height * scale).roundToInt())
    )
}

internal fun clampFramePositionMs(positionMs: Long, durationMs: Long): Long {
    if (durationMs <= 0) return max(0L, positionMs)
    return positionMs.coerceIn(0L, max(0L, durationMs - 1L))
}
