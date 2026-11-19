package io.ente.native_video_editor.core

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.net.Uri
import androidx.exifinterface.media.ExifInterface
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.OverlaySettings
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.DefaultGainProvider
import androidx.media3.common.audio.GainProcessor
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.BitmapOverlay
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.inspector.MediaExtractorCompat
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import java.io.Closeable
import java.io.File
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.UUID
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

@UnstableApi
internal class SlideshowComposer(
    private val context: Context,
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

        class Video(
            val file: File,
            val isMuted: Boolean,
            val audioStartUs: Long?,
            val clipEndUs: Long?,
            durationUs: Long
        ) : Segment(durationUs) {
            val playsAudio get() = audioStartUs != null
            val audioStartsAfterSlot get() = audioStartUs != null && audioStartUs >= durationUs
        }
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

                is SlideshowItem.Video -> {
                    val fullDurationUs = mediaDurationUs(file)
                    val clipEndUs = item.maxDurationMs
                        ?.times(1_000L)
                        ?.takeIf { it < fullDurationUs }
                    Segment.Video(
                        file = file,
                        isMuted = item.isMuted,
                        audioStartUs = if (item.isMuted) null else readAudioStartUs(file),
                        clipEndUs = clipEndUs,
                        durationUs = clipEndUs ?: fullDurationUs
                    )
                }
            }
        }

        val videoAudioGain = request.music?.videoAudioGain?.toFloat()
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
                    EditedMediaItem.Builder(videoMediaItem(segment))
                    .setFrameRate(request.frameRate)
                    .setRemoveAudio(segment.isMuted || segment.audioStartsAfterSlot)
                    .setEffects(
                        Effects(
                            listOfNotNull(
                                audioWindow(segment, startsSequence = index == 0),
                                videoAudioGain?.let {
                                    GainProcessor(DefaultGainProvider.Builder(it).build())
                                }
                            ),
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

    private fun readAudioStartUs(file: File): Long? {
        val extractor = MediaExtractorCompat(context)
        return try {
            extractor.setDataSource(Uri.fromFile(file), 0L)
            val audioTracks = (0 until extractor.trackCount).filter {
                MimeTypes.isAudio(extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME))
            }
            when (audioTracks.size) {
                0 -> null
                1 -> {
                    extractor.selectTrack(audioTracks.single())
                    max(0L, extractor.sampleTime)
                }
                else -> 0L
            }
        } finally {
            extractor.release()
        }
    }

    private fun audioWindow(segment: Segment.Video, startsSequence: Boolean): AudioProcessor? {
        val audioStartUs = segment.audioStartUs
        return when {
            audioStartUs == null -> segment.clipEndUs?.let { AudioWindowProcessor(delayUs = 0, lengthUs = it) }
            segment.audioStartsAfterSlot -> AudioWindowProcessor(delayUs = 0, lengthUs = segment.durationUs)
            startsSequence -> AudioWindowProcessor(delayUs = 0, lengthUs = segment.durationUs - audioStartUs)
            else -> AudioWindowProcessor(delayUs = audioStartUs, lengthUs = segment.durationUs)
        }
    }

    private fun videoMediaItem(segment: Segment.Video): MediaItem {
        val builder = MediaItem.Builder().setUri(Uri.fromFile(segment.file))
        segment.clipEndUs?.let { endUs ->
            builder.setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder().setEndPositionUs(endUs).build()
            )
        }
        return builder.build()
    }

    private fun musicSequence(
        segments: List<Segment>,
        music: File,
        trackDurationUs: Long,
        settings: SlideshowMusic
    ): EditedMediaItemSequence {
        val totalUs = segments.sumOf { it.durationUs }
        val envelope = MusicEnvelope(
            totalUs = totalUs,
            fadeInUs = settings.fadeInMs * 1_000L,
            fadeOutUs = settings.fadeOutMs * 1_000L,
            duckedMusicGain = settings.duckedMusicGain,
            duckFadeUs = settings.duckFadeMs * 1_000L,
            videoAudio = videoAudioRanges(segments)
        )
        @Suppress("DEPRECATION")
        val builder = EditedMediaItemSequence.Builder().experimentalSetForceAudioTrack(true)
        var offsetUs = 0L
        while (offsetUs < totalUs) {
            val clipUs = min(totalUs - offsetUs, trackDurationUs)
            builder.addItem(
                EditedMediaItem.Builder(
                    MediaItem.Builder()
                        .setUri(Uri.fromFile(music))
                        .setClippingConfiguration(
                            MediaItem.ClippingConfiguration.Builder()
                                .setEndPositionUs(clipUs)
                                .build()
                        )
                        .build()
                )
                    .setEffects(
                        Effects(
                            listOf(GainProcessor(MusicGainProvider(offsetUs, envelope))),
                            emptyList()
                        )
                    )
                    .build()
            )
            offsetUs += clipUs
        }
        return builder.build()
    }

    private fun videoAudioRanges(segments: List<Segment>): List<LongRange> {
        val ranges = mutableListOf<LongRange>()
        var startUs = 0L
        for (segment in segments) {
            val endUs = startUs + segment.durationUs
            if (segment is Segment.Video && segment.playsAudio) ranges.add(startUs until endUs)
            startUs = endUs
        }
        return ranges
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

private class MusicEnvelope(
    private val totalUs: Long,
    private val fadeInUs: Long,
    private val fadeOutUs: Long,
    private val duckedMusicGain: Double,
    private val duckFadeUs: Long,
    videoAudio: List<LongRange>
) {
    private val ducks = videoAudio.fold(mutableListOf<LongRange>()) { merged, range ->
        val last = merged.lastOrNull()
        if (last != null && range.first - (last.last + 1) <= 2 * duckFadeUs) {
            merged[merged.lastIndex] = last.first..range.last
        } else {
            merged.add(range)
        }
        merged
    }

    fun gainAt(timeUs: Long): Float {
        var gain = 1.0
        if (fadeInUs > 0) gain = min(gain, timeUs.toDouble() / fadeInUs)
        if (fadeOutUs > 0) gain = min(gain, (totalUs - timeUs).toDouble() / fadeOutUs)
        return (gain.coerceIn(0.0, 1.0) * duckLevelAt(timeUs)).toFloat()
    }

    fun nextChangeUs(timeUs: Long): Long? {
        val fadeOutStartUs = (totalUs - fadeOutUs).takeIf { fadeOutUs > 0 && it >= timeUs }
        val duckStartUs = ducks.getOrNull(firstDuckWhere { it.first - duckFadeUs >= timeUs })
            ?.let { it.first - duckFadeUs }
        return listOfNotNull(fadeOutStartUs, duckStartUs).minOrNull()
    }

    private fun duckLevelAt(timeUs: Long): Double {
        var level = 1.0
        var index = firstDuckWhere { it.last >= timeUs - duckFadeUs }
        while (index < ducks.size && ducks[index].first - duckFadeUs <= timeUs) {
            val duck = ducks[index]
            index++
            val depth = when {
                timeUs in duck -> 1.0
                duckFadeUs <= 0 -> 0.0
                timeUs < duck.first -> 1.0 - (duck.first - timeUs).toDouble() / duckFadeUs
                else -> 1.0 - (timeUs - duck.last - 1).toDouble() / duckFadeUs
            }
            if (depth > 0) level = min(level, 1.0 - depth * (1.0 - duckedMusicGain))
        }
        return level
    }

    private inline fun firstDuckWhere(isReached: (LongRange) -> Boolean): Int {
        var low = 0
        var high = ducks.size
        while (low < high) {
            val middle = (low + high) / 2
            if (isReached(ducks[middle])) high = middle else low = middle + 1
        }
        return low
    }
}

private class MusicGainProvider(
    private val offsetUs: Long,
    private val envelope: MusicEnvelope
) : GainProcessor.GainProvider {
    override fun getGainFactorAtSamplePosition(samplePosition: Long, sampleRate: Int): Float =
        envelope.gainAt(timeUs(samplePosition, sampleRate))

    override fun isUnityUntil(samplePosition: Long, sampleRate: Int): Long {
        if (getGainFactorAtSamplePosition(samplePosition, sampleRate) < 1f) return C.TIME_UNSET
        val changeUs = envelope.nextChangeUs(timeUs(samplePosition, sampleRate))
            ?: return C.TIME_END_OF_SOURCE
        val changeSample = (changeUs - offsetUs) * sampleRate / C.MICROS_PER_SECOND
        return if (changeSample > samplePosition) changeSample else samplePosition + 1
    }

    private fun timeUs(samplePosition: Long, sampleRate: Int) =
        offsetUs + samplePosition * C.MICROS_PER_SECOND / sampleRate
}

@UnstableApi
private class AudioWindowProcessor(
    private val delayUs: Long,
    private val lengthUs: Long
) : BaseAudioProcessor() {
    private var pendingSilenceFrames = 0L
    private var remainingFrames = 0L

    override fun onConfigure(inputAudioFormat: AudioProcessor.AudioFormat) = inputAudioFormat

    override fun onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        remainingFrames = frames(max(0L, lengthUs - streamMetadata.positionOffsetUs))
        pendingSilenceFrames = min(frames(delayUs), remainingFrames)
    }

    override fun queueInput(inputBuffer: ByteBuffer) {
        val bytesPerFrame = inputAudioFormat.bytesPerFrame
        if (pendingSilenceFrames > 0) {
            val silenceFrames = min(pendingSilenceFrames, (silenceChunk.size / bytesPerFrame).toLong())
            pendingSilenceFrames -= silenceFrames
            remainingFrames -= silenceFrames
            val silenceBytes = silenceFrames.toInt() * bytesPerFrame
            replaceOutputBuffer(silenceBytes).put(silenceChunk, 0, silenceBytes).flip()
            return
        }
        val keptFrames = min(inputBuffer.remaining().toLong() / bytesPerFrame, remainingFrames)
        val inputEnd = inputBuffer.limit()
        if (keptFrames > 0) {
            remainingFrames -= keptFrames
            inputBuffer.limit(inputBuffer.position() + keptFrames.toInt() * bytesPerFrame)
            replaceOutputBuffer(keptFrames.toInt() * bytesPerFrame).put(inputBuffer).flip()
            inputBuffer.limit(inputEnd)
        }
        inputBuffer.position(inputEnd)
    }

    private fun frames(durationUs: Long) = durationUs * inputAudioFormat.sampleRate / C.MICROS_PER_SECOND
}

private val silenceChunk = ByteArray(64 * 1024)
