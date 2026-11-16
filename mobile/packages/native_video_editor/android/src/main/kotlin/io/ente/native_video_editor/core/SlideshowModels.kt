package io.ente.native_video_editor.core

data class SlideshowMotion(
    val startScale: Float,
    val endScale: Float,
    val startX: Float,
    val startY: Float,
    val endX: Float,
    val endY: Float
) {
    init {
        require(
            listOf(startScale, endScale, startX, startY, endX, endY).all { it.isFinite() } &&
                startScale > 0f &&
                endScale > 0f
        ) { "Invalid slideshow motion" }
    }
}

sealed class SlideshowItem {
    abstract val path: String

    data class Photo(
        override val path: String,
        val durationMs: Long,
        val motion: SlideshowMotion
    ) : SlideshowItem() {
        init {
            require(path.isNotBlank() && durationMs > 0) { "Invalid slideshow photo" }
        }
    }

    data class Video(override val path: String, val isMuted: Boolean) : SlideshowItem() {
        init {
            require(path.isNotBlank()) { "Invalid slideshow video" }
        }
    }
}

data class SlideshowMusic(val path: String, val fadeInMs: Long, val fadeOutMs: Long) {
    init {
        require(path.isNotBlank() && fadeInMs >= 0 && fadeOutMs >= 0) { "Invalid slideshow music" }
    }
}

data class SlideshowExportRequest(
    val outputPath: String,
    val width: Int,
    val height: Int,
    val frameRate: Int,
    val crossfadeMs: Long,
    val items: List<SlideshowItem>,
    val music: SlideshowMusic?
) {
    init {
        require(outputPath.isNotBlank()) { "Missing output path" }
        require(items.isNotEmpty()) { "Slideshow has no items" }
        require(width > 0 && height > 0 && width % 2 == 0 && height % 2 == 0) {
            "Slideshow size must be positive and even"
        }
        require(frameRate in 1..60) { "Invalid slideshow frame rate" }
        require(crossfadeMs >= 0) { "Invalid slideshow crossfade" }
        require(
            items.filterIsInstance<SlideshowItem.Photo>().all { crossfadeMs <= it.durationMs }
        ) { "Photo durations must exceed the crossfade" }
    }
}
