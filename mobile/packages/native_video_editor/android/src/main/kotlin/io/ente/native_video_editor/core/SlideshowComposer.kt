package io.ente.native_video_editor.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@UnstableApi
internal class SlideshowComposer(
    context: Context,
    private val request: SlideshowExportRequest
) : Closeable {
    private val workDir = File(context.cacheDir, "slideshow-${UUID.randomUUID()}")
    private val frameWidth = request.width
    private val frameHeight = request.height
    private val crossfadeUs = request.crossfadeMs * 1_000L
    private val bitmaps = SlideshowBitmapBudget()

    private sealed class Segment(val durationUs: Long) {
        class Photo(
            val file: File,
            val backgroundFile: File,
            val motion: SlideshowMotion,
            durationUs: Long
        ) : Segment(durationUs)

        class Video(val file: File, val isMuted: Boolean, durationUs: Long) : Segment(durationUs)
    }

    fun compose(): Composition {
        require(workDir.mkdirs() || workDir.isDirectory) { "Cannot create slideshow work directory" }
        val outputFile = File(request.outputPath).canonicalFile
        val segments = request.items.mapIndexed { index, item ->
            val file = File(item.path).canonicalFile
            require(file.isFile && file != outputFile) { "Invalid slideshow input: ${item.path}" }
            when (item) {
                is SlideshowItem.Photo -> Segment.Photo(
                    file = file,
                    backgroundFile = writeBackground(file, index),
                    motion = item.motion,
                    durationUs = item.durationMs * 1_000L
                )

                is SlideshowItem.Video -> Segment.Video(
                    file = file,
                    isMuted = item.isMuted,
                    durationUs = mediaDurationUs(file)
                )
            }
        }

        var previousPhoto: PhotoOverlay? = null
        val videoItems = segments.mapIndexed { index, segment ->
            val previousOverlay = previousPhoto
            val dissolve = if (index == 0 || crossfadeUs <= 0) {
                null
            } else {
                DissolveOverlay(
                    index = index,
                    budget = bitmaps,
                    crossfadeUs = crossfadeUs,
                    load = {
                        previousFrame(segments.getOrNull(index - 1), previousOverlay?.loadedBitmap)
                    }
                )
            }
            val presentation = Presentation.createForWidthAndHeight(
                frameWidth,
                frameHeight,
                Presentation.LAYOUT_SCALE_TO_FIT
            )
            when (segment) {
                is Segment.Photo -> {
                    val photo = PhotoOverlay(
                        index = index,
                        budget = bitmaps,
                        durationUs = segment.durationUs,
                        motion = segment.motion,
                        frameWidth = frameWidth,
                        frameHeight = frameHeight,
                        load = { decodePhotoForOverlay(segment) }
                    )
                    previousPhoto = photo
                    EditedMediaItem.Builder(
                        MediaItem.Builder()
                            .setUri(Uri.fromFile(segment.backgroundFile))
                            .setMimeType(MimeTypes.IMAGE_JPEG)
                            .setImageDurationMs(segment.durationUs / 1_000L)
                            .build()
                    )
                        .setFrameRate(request.frameRate)
                        .setEffects(
                            Effects(
                                emptyList(),
                                listOf(presentation, OverlayEffect(listOfNotNull(photo, dissolve)))
                            )
                        )
                        .build()
                }

                is Segment.Video -> {
                    previousPhoto = null
                    EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(segment.file)))
                    .setFrameRate(request.frameRate)
                    .setRemoveAudio(segment.isMuted)
                    .setEffects(
                        Effects(
                            emptyList(),
                            listOfNotNull(presentation, dissolve?.let { OverlayEffect(listOf(it)) })
                        )
                    )
                    .build()
                }
            }
        }

        val musicSettings = request.music
        val musicFile = musicSettings?.let { File(it.path).canonicalFile }
        val musicDurationUs = musicFile?.let {
            require(it.isFile && it != outputFile) { "Invalid slideshow music: ${it.path}" }
            mediaDurationUs(it)
        }
        val playsVideoAudio = segments.any { it is Segment.Video && !it.isMuted }
        val hasAudio = musicDurationUs != null || playsVideoAudio

        @Suppress("DEPRECATION")
        val sequences = mutableListOf(
            EditedMediaItemSequence.Builder(videoItems)
                .experimentalSetForceAudioTrack(hasAudio)
                .build()
        )
        if (musicSettings != null && musicFile != null && musicDurationUs != null) {
            sequences.add(musicSequence(segments, musicFile, musicDurationUs, musicSettings))
        }
        return Composition.Builder(sequences)
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            .build()
    }

    private fun musicSequence(
        segments: List<Segment>,
        music: File,
        trackDurationUs: Long,
        settings: SlideshowMusic
    ): EditedMediaItemSequence {
        @Suppress("DEPRECATION")
        val builder = EditedMediaItemSequence.Builder().experimentalSetForceAudioTrack(true)
        var gapUs = 0L
        var positionUs = 0L
        var runDurationUs = 0L

        fun flushRun() {
            if (runDurationUs == 0L) return
            if (gapUs > 0) {
                builder.addGap(gapUs)
                gapUs = 0
            }
            var offsetUs = 0L
            while (offsetUs < runDurationUs) {
                val clipUs = min(runDurationUs - offsetUs, trackDurationUs - positionUs)
                builder.addItem(
                    EditedMediaItem.Builder(
                        MediaItem.Builder()
                            .setUri(Uri.fromFile(music))
                            .setClippingConfiguration(
                                MediaItem.ClippingConfiguration.Builder()
                                    .setStartPositionUs(positionUs)
                                    .setEndPositionUs(positionUs + clipUs)
                                    .build()
                            )
                            .build()
                    )
                        .setEffects(
                            Effects(
                                listOf(
                                    GainProcessor(
                                        FadeGainProvider(
                                            offsetUs = offsetUs,
                                            durationUs = runDurationUs,
                                            fadeInUs = settings.fadeInMs * 1_000L,
                                            fadeOutUs = settings.fadeOutMs * 1_000L
                                        )
                                    )
                                ),
                                emptyList()
                            )
                        )
                        .build()
                )
                positionUs = (positionUs + clipUs) % trackDurationUs
                offsetUs += clipUs
            }
            runDurationUs = 0
        }

        for (segment in segments) {
            when (segment) {
                is Segment.Photo -> runDurationUs += segment.durationUs
                is Segment.Video -> {
                    flushRun()
                    gapUs += segment.durationUs
                }
            }
        }
        flushRun()
        if (gapUs > 0) builder.addGap(gapUs)
        return builder.build()
    }

    private fun writeBackground(photo: File, index: Int): File {
        val tiny = decodePhoto(photo, maxLongSide = BACKGROUND_SAMPLE_SIZE)
        val background = Bitmap.createBitmap(frameWidth, frameHeight, Bitmap.Config.ARGB_8888)
        try {
            val canvas = Canvas(background)
            val intermediate = Bitmap.createScaledBitmap(
                tiny,
                max(1, tiny.width * BACKGROUND_UPSCALE_STEP),
                max(1, tiny.height * BACKGROUND_UPSCALE_STEP),
                true
            )
            try {
                drawCovered(canvas, intermediate)
            } finally {
                if (intermediate !== tiny) intermediate.recycle()
            }
            val file = File(workDir, "background-$index.jpg")
            FileOutputStream(file).use { stream ->
                require(background.compress(Bitmap.CompressFormat.JPEG, BACKGROUND_JPEG_QUALITY, stream)) {
                    "Cannot write slideshow background"
                }
            }
            return file
        } finally {
            background.recycle()
            tiny.recycle()
        }
    }

    private fun decodePhotoForOverlay(segment: Segment.Photo): Bitmap {
        val maxScale = max(segment.motion.startScale, segment.motion.endScale)
        return decodePhoto(segment.file, maxLongSide = (max(frameWidth, frameHeight) * maxScale).roundToInt())
    }

    private fun previousFrame(segment: Segment?, decodedPhoto: Bitmap?): Bitmap {
        val frame = Bitmap.createBitmap(frameWidth, frameHeight, Bitmap.Config.ARGB_8888)
        frame.eraseColor(Color.BLACK)
        val canvas = Canvas(frame)
        when (segment) {
            null -> Unit
            is Segment.Photo -> {
                val background = BitmapFactory.decodeFile(segment.backgroundFile.path)
                    ?: throw IllegalStateException("Cannot read slideshow background")
                try {
                    drawCovered(canvas, background)
                } finally {
                    background.recycle()
                }
                val photo = decodedPhoto ?: decodePhotoForOverlay(segment)
                try {
                    drawPhoto(canvas, photo, segment.motion.endScale, segment.motion.endX, segment.motion.endY)
                } finally {
                    if (photo !== decodedPhoto) photo.recycle()
                }
            }

            is Segment.Video -> {
                val retriever = MediaMetadataRetriever()
                val lastFrame = try {
                    retriever.setDataSource(segment.file.path)
                    retriever.getFrameAtTime(
                        max(0L, segment.durationUs - 1),
                        MediaMetadataRetriever.OPTION_CLOSEST
                    )
                } finally {
                    retriever.release()
                }
                if (lastFrame != null) {
                    try {
                        drawPhoto(canvas, lastFrame, 1f, 0f, 0f)
                    } finally {
                        lastFrame.recycle()
                    }
                }
            }
        }
        return frame
    }

    private fun drawCovered(canvas: Canvas, bitmap: Bitmap) {
        val scale = max(frameWidth.toFloat() / bitmap.width, frameHeight.toFloat() / bitmap.height)
        val matrix = Matrix().apply {
            postTranslate(-bitmap.width / 2f, -bitmap.height / 2f)
            postScale(scale, scale)
            postTranslate(frameWidth / 2f, frameHeight / 2f)
        }
        canvas.drawBitmap(bitmap, matrix, FILTER_PAINT)
    }

    private fun drawPhoto(canvas: Canvas, bitmap: Bitmap, scale: Float, offsetX: Float, offsetY: Float) {
        val contain = min(frameWidth.toFloat() / bitmap.width, frameHeight.toFloat() / bitmap.height)
        val total = contain * scale
        val matrix = Matrix().apply {
            postTranslate(-bitmap.width / 2f, -bitmap.height / 2f)
            postScale(total, total)
            postTranslate(frameWidth / 2f + offsetX * frameWidth, frameHeight / 2f + offsetY * frameHeight)
        }
        canvas.drawBitmap(bitmap, matrix, FILTER_PAINT)
    }

    override fun close() {
        bitmaps.releaseAll()
        workDir.deleteRecursively()
    }

    private companion object {
        const val BACKGROUND_SAMPLE_SIZE = 32
        const val BACKGROUND_UPSCALE_STEP = 8
        const val BACKGROUND_JPEG_QUALITY = 85
        val FILTER_PAINT = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    }
}

internal fun smoothstep(value: Float): Float {
    val t = value.coerceIn(0f, 1f)
    return t * t * (3f - 2f * t)
}

private fun mediaDurationUs(file: File): Long {
    val retriever = MediaMetadataRetriever()
    return try {
        retriever.setDataSource(file.path)
        val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLongOrNull()
        require(durationMs != null && durationMs > 0) { "Media duration is unavailable: ${file.path}" }
        durationMs * 1_000L
    } finally {
        retriever.release()
    }
}

private fun decodePhoto(file: File, maxLongSide: Int): Bitmap {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(file.path, bounds)
    require(bounds.outWidth > 0 && bounds.outHeight > 0) { "Cannot decode photo: ${file.path}" }
    var sampleSize = 1
    while (max(bounds.outWidth, bounds.outHeight) / (sampleSize * 2) >= maxLongSide) {
        sampleSize *= 2
    }
    val decoded = BitmapFactory.decodeFile(
        file.path,
        BitmapFactory.Options().apply {
            inSampleSize = sampleSize
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
    ) ?: throw IllegalArgumentException("Cannot decode photo: ${file.path}")
    val scale = min(1f, maxLongSide.toFloat() / max(decoded.width, decoded.height))
    val orientation = exifTransform(file)
    if (scale == 1f && orientation == null) return decoded
    val matrix = Matrix().apply {
        postScale(scale, scale)
        orientation?.let(::postConcat)
    }
    val transformed = Bitmap.createBitmap(decoded, 0, 0, decoded.width, decoded.height, matrix, true)
    if (transformed !== decoded) decoded.recycle()
    return transformed
}

private fun exifTransform(file: File): Matrix? {
    val orientation = try {
        ExifInterface(file.path).getAttributeInt(
            ExifInterface.TAG_ORIENTATION,
            ExifInterface.ORIENTATION_NORMAL
        )
    } catch (_: Exception) {
        ExifInterface.ORIENTATION_NORMAL
    }
    val matrix = Matrix()
    when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.setScale(-1f, 1f)
        ExifInterface.ORIENTATION_ROTATE_180 -> matrix.setRotate(180f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.setScale(1f, -1f)
        ExifInterface.ORIENTATION_TRANSPOSE -> {
            matrix.setRotate(90f)
            matrix.postScale(-1f, 1f)
        }

        ExifInterface.ORIENTATION_ROTATE_90 -> matrix.setRotate(90f)
        ExifInterface.ORIENTATION_TRANSVERSE -> {
            matrix.setRotate(-90f)
            matrix.postScale(-1f, 1f)
        }

        ExifInterface.ORIENTATION_ROTATE_270 -> matrix.setRotate(-90f)
        else -> return null
    }
    return matrix
}

@UnstableApi
internal class SlideshowBitmapBudget {
    private val overlays = mutableListOf<LazyBitmapOverlay>()

    @Synchronized
    fun register(overlay: LazyBitmapOverlay) {
        overlays.add(overlay)
    }

    @Synchronized
    fun onItemStarted(index: Int) {
        overlays.filter { it.index < index - 1 }.forEach(LazyBitmapOverlay::releaseBitmap)
    }

    @Synchronized
    fun releaseAll() {
        overlays.forEach(LazyBitmapOverlay::releaseBitmap)
        overlays.clear()
    }
}

@UnstableApi
internal abstract class LazyBitmapOverlay(
    val index: Int,
    private val budget: SlideshowBitmapBudget,
    private val load: () -> Bitmap
) : BitmapOverlay() {
    private var bitmap: Bitmap? = null
    private var startUs = C.TIME_UNSET

    val loadedBitmap: Bitmap? get() = bitmap

    init {
        budget.register(this)
    }

    protected abstract fun settingsAt(elapsedUs: Long): OverlaySettings

    override fun getBitmap(presentationTimeUs: Long): Bitmap {
        bitmap?.let { return it }
        budget.onItemStarted(index)
        return try {
            load()
        } catch (error: Exception) {
            throw VideoFrameProcessingException(error)
        }.also { bitmap = it }
    }

    override fun getOverlaySettings(presentationTimeUs: Long): OverlaySettings {
        if (startUs == C.TIME_UNSET) startUs = presentationTimeUs
        return settingsAt(presentationTimeUs - startUs)
    }

    fun releaseBitmap() {
        bitmap = null
    }
}

@UnstableApi
private class PhotoOverlay(
    index: Int,
    budget: SlideshowBitmapBudget,
    private val durationUs: Long,
    private val motion: SlideshowMotion,
    private val frameWidth: Int,
    private val frameHeight: Int,
    load: () -> Bitmap
) : LazyBitmapOverlay(index, budget, load) {
    override fun settingsAt(elapsedUs: Long): OverlaySettings {
        val bitmap = getBitmap(elapsedUs)
        val progress = smoothstep(elapsedUs.toFloat() / durationUs)
        val scale = motion.startScale + (motion.endScale - motion.startScale) * progress
        val offsetX = motion.startX + (motion.endX - motion.startX) * progress
        val offsetY = motion.startY + (motion.endY - motion.startY) * progress
        val contain = min(frameWidth.toFloat() / bitmap.width, frameHeight.toFloat() / bitmap.height)
        val overlayScale = contain * scale
        return StaticOverlaySettings.Builder()
            .setScale(overlayScale, overlayScale)
            .setBackgroundFrameAnchor(2f * offsetX, -2f * offsetY)
            .setOverlayFrameAnchor(0f, 0f)
            .build()
    }
}

@UnstableApi
private class DissolveOverlay(
    index: Int,
    budget: SlideshowBitmapBudget,
    private val crossfadeUs: Long,
    load: () -> Bitmap
) : LazyBitmapOverlay(index, budget, load) {
    override fun settingsAt(elapsedUs: Long): OverlaySettings {
        val alpha = if (crossfadeUs <= 0 || elapsedUs >= crossfadeUs) {
            0f
        } else {
            1f - smoothstep(elapsedUs.toFloat() / crossfadeUs)
        }
        return StaticOverlaySettings.Builder().setAlphaScale(alpha).build()
    }
}

private class FadeGainProvider(
    private val offsetUs: Long,
    private val durationUs: Long,
    private val fadeInUs: Long,
    private val fadeOutUs: Long
) : GainProcessor.GainProvider {
    override fun getGainFactorAtSamplePosition(samplePosition: Long, sampleRate: Int): Float {
        val timeUs = offsetUs + samplePosition * C.MICROS_PER_SECOND / sampleRate
        var gain = 1f
        if (fadeInUs > 0) gain = min(gain, timeUs.toFloat() / fadeInUs)
        if (fadeOutUs > 0) gain = min(gain, (durationUs - timeUs).toFloat() / fadeOutUs)
        return gain.coerceIn(0f, 1f)
    }

    override fun isUnityUntil(samplePosition: Long, sampleRate: Int): Long {
        if (getGainFactorAtSamplePosition(samplePosition, sampleRate) < 1f) return C.TIME_UNSET
        if (fadeOutUs <= 0) return C.TIME_END_OF_SOURCE
        val fadeOutStartSample = (durationUs - fadeOutUs - offsetUs) * sampleRate / C.MICROS_PER_SECOND
        return if (fadeOutStartSample > samplePosition) fadeOutStartSample else samplePosition + 1
    }
}
